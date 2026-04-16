/** HTTP 层共用工具，供 HttpClient / HttpCompat 复用，避免两套实现漂移 */

import hilog from '@ohos.hilog';

const TAG = 'HttpShared';
const DOMAIN = 0x0001;

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

/**
 * @ohos.net.http 对 application/json 可能直接返回 Object；空串 / 非法 JSON 返回 null。
 * 与 parseHttpBodyJson 同文件导出，避免经 index 二次导出时 Ark 运行时丢符号。
 */

export interface HttpResponseBodyHolder {
  result?: Object | string;
  data?: Object | string;
}

export function httpResponseBody(res: HttpResponseBodyHolder): string | Object | undefined {
  const r = res.result;
  if (r !== undefined && r !== null) {
    return r as string | Object;
  }
  const d = res.data;
  if (d !== undefined && d !== null) {
    return d as string | Object;
  }
  return undefined;
}

/** 去掉 UTF-8 BOM、JSONP 外壳；不再按首尾 `}` 截断（易误伤字段中含 `}` 的合法 JSON）。 */
function normalizeHttpJsonText(text: string): string {
  let t = text.trim();
  if (t.length === 0) {
    return t;
  }
  if (t.charCodeAt(0) === 0xfeff) {
    t = t.substring(1).trim();
  }
  const head = t.charCodeAt(0);
  if (head !== 0x7b && head !== 0x5b) {
    const lp = t.indexOf('(');
    const rp = t.lastIndexOf(')');
    if (lp >= 0 && rp > lp) {
      t = t.substring(lp + 1, rp).trim();
    }
  }
  return t;
}

export function parseHttpBodyJson<T>(raw: string | Object | ArrayBuffer | undefined | null): T | null {
  if (raw === undefined || raw === null) {
    return null;
  }
  if (typeof raw === 'string') {
    const text = normalizeHttpJsonText(raw);
    if (text.length === 0) {
      return null;
    }
    try {
      return JSON.parse(text) as T;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'parseHttpBodyJson JSON.parse failed: %{public}s', (e as Error)?.message);
      return null;
    }
  }
  if (typeof raw === 'object' && raw !== null) {
    return raw as T;
  }
  return null;
}
