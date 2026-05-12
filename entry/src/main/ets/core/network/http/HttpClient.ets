/**
 * 统一 HTTP 客户端 - 直接使用 @ohos.net.http，不依赖 service 层
 * 单一实现：HttpClient 类 + 便捷函数均基于同一底层
 */
import http from '@ohos.net.http';
import hilog from '@ohos.hilog';
import { flattenHeaders, withQuery, parseHttpBodyJson } from './HttpShared';

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
            if (typeof raw === 'string' && raw.trim().length > 0) {
              hilog.warn(DOMAIN, TAG, 'doRequest JSON parse fallback to raw text');
            }
            data = raw as T;
          }
        } else {
          data = raw as T;
        }

        const headers = flattenHeaders(response.header as Record<string, string | string[]>);

        task.destroy();

        resolve({
          status: response.responseCode,
          statusText: response.responseCode.toString(),
          data,
          result: data,
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
  return true;
}
