/**
 * 薄封装：统一通过 HTTP 客户端拉取远程文本，供版本检查、配置拉取等复用。
 */
import { httpGet, httpResponseBody } from '../core/network/http';

export async function fetchUtf8Text(url: string, readTimeoutMs: number = 15000): Promise<string> {
  const task = httpGet(url, {
    readTimeout: readTimeoutMs,
    connectTimeout: 8000,
    responseType: 'text',
  });
  const resp = await task.promise;
  const raw = httpResponseBody(resp);
  if (typeof raw === 'string') {
    return raw;
  }
  if (raw !== undefined && typeof raw === 'object') {
    return JSON.stringify(raw);
  }
  return '';
}
