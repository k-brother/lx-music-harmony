/** 酷狗接口：与通用 parseHttpBodyJson 不同，字符串失败时由 JSON.parse 抛错，便于沿用原有 try/catch。 */
export function parseKgHttpJson<T>(raw: string | Object): T {
  if (typeof raw === 'string') {
    return JSON.parse(raw) as T;
  }
  return raw as T;
}
