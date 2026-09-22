/**
 * 统一 HTTP 客户端 - 直接使用 @ohos.net.http，不依赖 service 层
 * 单一实现：HttpClient 类 + 便捷函数均基于同一底层
 */
import { http, connection } from '@kit.NetworkKit';
import type { BusinessError } from '@kit.BasicServicesKit';
// 日志经由应用日志门面，既输出 hilog 也进入「设置 → 运行日志」
import { appLog as hilog } from '../../log/AppLogger';
import { flattenHeaders, withQuery, parseHttpBodyJson } from './HttpShared';
import { utf8Decode } from '../../../utils/TextCodec';

const TAG = 'HttpClient';
const DOMAIN = 0x0001;

// ============ 类型定义 ============

export interface HttpRequestConfig {
  url?: string;
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE' | 'PATCH' | 'HEAD';
  headers?: Record<string, string>;
  header?: Record<string, string> | Map<string, string>;
  params?: Record<string, string | number | boolean>;
  data?: string;
  extraData?: string | Object;
  timeout?: number;
  connectTimeout?: number;
  readTimeout?: number;
  responseType?: 'json' | 'text' | 'arraybuffer' | 'blob' | 'binary';
  retryCount?: number;
  loggingEnabled?: boolean;
}

export interface HttpResponse<T> {
  status: number;
  statusText: string;
  data: T;
  result: T;
  /**
   * 响应体原始文本。
   * data/result 在 responseType='json' 时已经是解析后的对象，
   * 需要自己解析文本的调用方（第三方源接口等）请统一用这个字段。
   */
  rawText: string;
  headers: Record<string, string>;
  config: HttpRequestConfig;
  url: string;
}

export interface HttpTask<T = Object> {
  promise: Promise<HttpResponse<T>>;
  cancel: () => void;
}

// ============ 内部核心实现 ============

/**
 * 把 @ohos.net.http 的响应体统一转成文本。
 * 字符串原样返回；ArrayBuffer 按 UTF-8 解码；已解析的对象重新序列化。
 */
function toResponseText(
  raw: string | Object | ArrayBuffer | undefined | null, responseType: string
): string {
  if (raw === undefined || raw === null) {
    return '';
  }
  if (typeof raw === 'string') {
    return raw;
  }
  if (raw instanceof ArrayBuffer) {
    // 二进制响应（图片/音频）不做文本解码，避免无谓的内存拷贝
    if (responseType === 'arraybuffer' || responseType === 'binary' || responseType === 'blob') {
      return '';
    }
    try {
      return utf8Decode(new Uint8Array(raw));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'toResponseText decode failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      return '';
    }
  }
  try {
    return JSON.stringify(raw);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'toResponseText stringify failed: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    return '';
  }
}

/**
 * 执行 HTTP 请求的核心函数
 * 统一处理 headers 合并、options 构建、响应解析
 */
function doRequest<T>(
  url: string,
  config: HttpRequestConfig
): Promise<HttpResponse<T>> {
  // 合并 headers 和 header
  const header: Record<string, string | number> = {};
  if (config.headers) {
    const keys = Object.keys(config.headers);
    for (let i = 0; i < keys.length; i++) {
      header[keys[i]] = config.headers[keys[i]];
    }
  }
  if (config.header) {
    if (config.header instanceof Map) {
      config.header.forEach((v: string, k: string) => {
        header[k] = v;
      });
    } else {
      const keys = Object.keys(config.header);
      for (let i = 0; i < keys.length; i++) {
        header[keys[i]] = config.header[keys[i]];
      }
    }
  }

  // 构建请求选项
  const timeout = config.timeout ?? 15000;
  const opts: http.HttpRequestOptions = {
    method: (config.method ?? 'GET') as http.RequestMethod,
    header: header,
    connectTimeout: config.connectTimeout ?? timeout,
    readTimeout: config.readTimeout ?? timeout,
  };
  // 服务端常标 application/json，正文却含 BOM/JSONP/前后杂质；系统层自动解析会抛 SyntaxError。
  // 强制以字符串接收，由 parseHttpBodyJson / 业务层自行解析。
  const rt = config.responseType ?? 'json';
  if (rt === 'json' || rt === 'text') {
    opts.expectDataType = http.HttpDataType.STRING;
  } else if (rt === 'arraybuffer' || rt === 'blob' || rt === 'binary') {
    opts.expectDataType = http.HttpDataType.ARRAY_BUFFER;
  }

  // 处理请求体
  if (config.extraData !== undefined) {
    opts.extraData = typeof config.extraData === 'string'
      ? config.extraData
      : JSON.stringify(config.extraData);
  } else if (config.data !== undefined && config.data.length > 0) {
    opts.extraData = config.data;
  }

  // 应用 URL 参数
  const finalUrl = withQuery(url, config.params);

  return new Promise<HttpResponse<T>>((resolve, reject) => {
    const task = http.createHttp();
    task.request(
      finalUrl,
      opts,
      (err: Error, response: http.HttpResponse) => {
        if (err) {
          task.destroy();
          reject(err);
          return;
        }

        // 解析响应
        const raw = response.result;
        let data: T;
        const responseType = config.responseType ?? 'json';

        if (responseType === 'json') {
          const parsed = parseHttpBodyJson<T>(raw as string | Object | ArrayBuffer | undefined | null);
          if (parsed !== null) {
            data = parsed;
          } else {
            // 只有「看起来是 JSON 却解析失败」才告警；纯文本响应（音频直链等）属于正常情况
            const text = typeof raw === 'string' ? raw : '';
            const looksLikeJson = text.indexOf('{') >= 0 || text.indexOf('[') >= 0;
            if (looksLikeJson) {
              hilog.warn(DOMAIN, TAG, 'doRequest JSON parse fallback to raw text');
            }
            data = raw as T;
          }
        } else {
          data = raw as T;
        }

        const rawText = toResponseText(raw, responseType);
        const headers = flattenHeaders(response.header as Record<string, string | string[]>);

        task.destroy();

        resolve({
          status: response.responseCode,
          statusText: response.responseCode.toString(),
          data,
          result: data,
          rawText,
          headers,
          config,
          url: finalUrl,
        });
      }
    );
  });
}

// ============ HTTP 客户端类 ============

export class HttpClient {
  /**
   * 基础请求方法
   */
  request<T>(url: string, config: HttpRequestConfig = {}): Promise<HttpResponse<T>> {
    return doRequest<T>(url, config);
  }

  /**
   * GET 请求
   */
  get<T>(url: string, config?: HttpRequestConfig): Promise<HttpResponse<T>> {
    const cfg: HttpRequestConfig = { method: 'GET' };
    if (config) {
      cfg.headers = config.headers;
      cfg.header = config.header;
      cfg.params = config.params;
      cfg.data = config.data;
      cfg.timeout = config.timeout;
      cfg.connectTimeout = config.connectTimeout;
      cfg.readTimeout = config.readTimeout;
      cfg.responseType = config.responseType;
      cfg.retryCount = config.retryCount;
      cfg.loggingEnabled = config.loggingEnabled;
    }
    return doRequest<T>(url, cfg);
  }

  /**
   * POST 请求
   */
  post<T>(url: string, data?: string | Object, config?: HttpRequestConfig): Promise<HttpResponse<T>> {
    const cfg: HttpRequestConfig = { method: 'POST' };
    if (config) {
      cfg.headers = config.headers;
      cfg.header = config.header;
      cfg.params = config.params;
      cfg.data = config.data;
      cfg.timeout = config.timeout;
      cfg.connectTimeout = config.connectTimeout;
      cfg.readTimeout = config.readTimeout;
      cfg.responseType = config.responseType;
      cfg.retryCount = config.retryCount;
      cfg.loggingEnabled = config.loggingEnabled;
    }
    if (data !== undefined) {
      cfg.extraData = typeof data === 'string' ? data : JSON.stringify(data);
    }
    return doRequest<T>(url, cfg);
  }
}

// 单例
export const httpClient = new HttpClient();

// ============ 可取消的任务函数 ============

/**
 * 二进制请求（图片 / 音频 / 压缩体等）
 *
 * 与 httpRequest 的区别：不做文本解码，直接返回 ArrayBuffer。
 * 目前酷我歌词接口返回的就是 zlib 压缩体，需要原始字节才能解压。
 *
 * @returns ArrayBuffer；响应不是二进制时返回 null
 */
export function httpRequestBinary(url: string, config?: HttpRequestConfig): Promise<ArrayBuffer | null> {
  const cfg: HttpRequestConfig = {
    method: config?.method ?? 'GET',
    responseType: 'arraybuffer',
  };
  if (config) {
    cfg.headers = config.headers;
    cfg.header = config.header;
    cfg.params = config.params;
    cfg.timeout = config.timeout;
    cfg.connectTimeout = config.connectTimeout;
    cfg.readTimeout = config.readTimeout;
  }

  return doRequest<ArrayBuffer>(url, cfg).then((response: HttpResponse<ArrayBuffer>) => {
    const raw = response.result;
    return raw instanceof ArrayBuffer ? raw : null;
  });
}

/**
 * HTTP 请求任务（支持取消）
 */
export function httpRequest(url: string, config?: HttpRequestConfig): HttpTask<Object> {
  let cancelled = false;
  const promise = doRequest<Object>(url, config ?? { method: 'GET' });

  return {
    promise: new Promise<HttpResponse<Object>>((resolve, reject) => {
      promise.then((response) => {
        if (cancelled) {
          reject(new Error('Request cancelled'));
        } else {
          resolve(response);
        }
      }).catch((err: Error) => {
        if (cancelled) {
          reject(new Error('Request cancelled'));
        } else {
          reject(err);
        }
      });
    }),
    cancel: () => {
      cancelled = true;
    },
  };
}

/**
 * GET 请求任务（支持取消）
 */
export function httpGet(url: string, config?: HttpRequestConfig): HttpTask<Object> {
  const cfg: HttpRequestConfig = { method: 'GET' };
  if (config) {
    cfg.headers = config.headers;
    cfg.header = config.header;
    cfg.params = config.params;
    cfg.data = config.data;
    cfg.timeout = config.timeout;
    cfg.connectTimeout = config.connectTimeout;
    cfg.readTimeout = config.readTimeout;
    cfg.responseType = config.responseType;
    cfg.retryCount = config.retryCount;
    cfg.loggingEnabled = config.loggingEnabled;
  }
  return httpRequest(url, cfg);
}

/**
 * POST 请求任务（支持取消）
 */
export function httpPost(url: string, data?: string, config?: HttpRequestConfig): HttpTask<Object> {
  const cfg: HttpRequestConfig = { method: 'POST' };
  if (config) {
    cfg.headers = config.headers;
    cfg.header = config.header;
    cfg.params = config.params;
    cfg.data = config.data;
    cfg.timeout = config.timeout;
    cfg.connectTimeout = config.connectTimeout;
    cfg.readTimeout = config.readTimeout;
    cfg.responseType = config.responseType;
    cfg.retryCount = config.retryCount;
    cfg.loggingEnabled = config.loggingEnabled;
  }
  if (data !== undefined) {
    cfg.extraData = data;
  }
  return httpRequest(url, cfg);
}

// ============ 网络检查 ============

export async function checkNetworkConnection(): Promise<boolean> {
  try {
    const netHandle: connection.NetHandle = await connection.getDefaultNet();
    // getDefaultNet returns a valid NetHandle if there is an active network
    return netHandle !== null && netHandle !== undefined;
  } catch (err) {
    const code: number = (err as BusinessError)?.code ?? 0;
    // 201 = 缺少 ohos.permission.GET_NETWORK_INFO，801 = 设备不支持该能力。
    // 这两种情况下探测本身不可用，不能据此判定"无网络"——
    // 真实请求能否成功由 HTTP 层决定，这里必须放行。
    if (code === 201 || code === 801) {
      hilog.warn(0x0001, TAG,
        'Network probe unavailable (code=%{public}d), assume online and let the request decide', code);
      return true;
    }
    hilog.warn(0x0001, TAG, 'checkNetworkConnection failed: %{public}s', JSON.stringify(err));
    return false;
  }
}
