/** HTTP 层共用工具，供 HttpClient / HttpCompat 复用，避免两套实现漂移 */

export function withQuery(url: string, params?: Record<string, string | number | boolean>): string {
  if (!params) {
    return url;
  }
  const keys = Object.keys(params);
  if (keys.length === 0) {
    return url;
  }
  const parts: string[] = [];
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    parts.push(`${encodeURIComponent(k)}=${encodeURIComponent(String(params[k]))}`);
  }
  const sep = url.indexOf('?') >= 0 ? '&' : '?';
  return `${url}${sep}${parts.join('&')}`;
}

export function flattenHeaders(h: Record<string, string | string[]>): Record<string, string> {
  const out: Record<string, string> = {};
  const keys = Object.keys(h);
  for (let i = 0; i < keys.length; i++) {
    const v = h[keys[i]];
    out[keys[i]] = Array.isArray(v) ? v.join(',') : String(v);
  }
  return out;
}
