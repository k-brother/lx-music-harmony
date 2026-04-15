/**
 * @ohos.net.http 对 application/json 可能直接返回 Object，勿对 Object 再 JSON.parse。
 * 部分接口 200 但 body 为空字符串，JSON.parse('') 会抛错；非法 JSON 同样返回 null。
 */
export function parseHttpBodyJson<T>(raw: string | Object | ArrayBuffer | undefined | null): T | null {
  if (raw === undefined || raw === null) {
    return null;
  }
  if (typeof raw === 'string') {
    const text = raw.trim();
    if (text.length === 0) {
      return null;
    }
    try {
      return JSON.parse(text) as T;
    } catch {
      return null;
    }
  }
  if (typeof raw === 'object' && raw !== null) {
    return raw as T;
  }
  return null;
}
