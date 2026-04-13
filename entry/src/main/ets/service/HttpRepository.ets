/**
 * 薄封装：统一通过 HTTP 客户端拉取远程文本，供版本检查、配置拉取等复用。
 */
import { httpGet } from '../core/network/http';

export async function fetchUtf8Text(url: string, readTimeoutMs: number = 15000): Promise<string> {
  const task = httpGet(url, {
    readTimeout: readTimeoutMs,
    connectTimeout: 8000,
  });
  const resp = await task.promise;
  return resp.result as string;
}
