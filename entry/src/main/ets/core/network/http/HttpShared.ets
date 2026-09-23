/** HTTP 层共用工具，供 HttpClient / HttpCompat 复用，避免两套实现漂移 */

import { hilog } from '@kit.PerformanceAnalysisKit';

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

function extractBalancedJson(text: string): string {
  const firstObj = text.indexOf('{');
  const firstArr = text.indexOf('[');
  let start = -1;
  if (firstObj >= 0 && firstArr >= 0) {
    start = Math.min(firstObj, firstArr);
  } else if (firstObj >= 0) {
    start = firstObj;
  } else if (firstArr >= 0) {
    start = firstArr;
  }
  if (start < 0 || start >= text.length) {
    return text;
  }
  const open = text[start];
  const close = open === '{' ? '}' : ']';
  let depth = 0;
  let inString = false;
  let escapeNext = false;
  let quote = '"';
  for (let i = start; i < text.length; i++) {
    const ch = text[i];
    if (inString) {
      if (escapeNext) {
        escapeNext = false;
        continue;
      }
      if (ch === '\\') {
        escapeNext = true;
        continue;
      }
      if (ch === quote) {
        inString = false;
      }
      continue;
    }
    if (ch === '"' || ch === '\'') {
      inString = true;
      quote = ch;
      continue;
    }
    if (ch === open) {
      depth += 1;
      continue;
    }
    if (ch === close) {
      depth -= 1;
      if (depth === 0) {
        return text.substring(start, i + 1).trim();
      }
    }
  }
  return text.trim();
}

function toLooseJson(text: string): string {
  let t = text.trim();
  // 1) JS 对象字面量未加引号的 key：{code:0,data:{...}} -> {"code":0,"data":{...}}
  t = t.replace(/([{,]\s*)([A-Za-z_$][\w$]*)\s*:/g, '$1"$2":');
  // 2) 单引号字符串 -> 双引号字符串（简单兜底）
  t = t.replace(/'([^'\\]*(?:\\.[^'\\]*)*)'/g, '"$1"');
  // 3) 去掉尾随逗号
  t = t.replace(/,\s*([}\]])/g, '$1');
  return t;
}

/** 去掉 UTF-8 BOM、JSONP 外壳，并尽量提取正文中的 JSON 片段。 */
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
  return extractBalancedJson(t);
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
    // 正文里没有花括号/方括号说明根本不是 JSON：
    // 例如酷我 anti_server 直接返回音频直链、部分接口返回纯文本。
    // 这些情况调用方会按纯文本处理，这里静默返回，避免刷出误导性的解析告警。
    if (text.indexOf('{') < 0 && text.indexOf('[') < 0) {
      return null;
    }
    try {
      return JSON.parse(text) as T;
    } catch (e) {
      const looseText = toLooseJson(text);
      if (looseText !== text) {
        try {
          return JSON.parse(looseText) as T;
        } catch (_e2) {
          // ignore and fall through to warning
        }
      }
      hilog.warn(DOMAIN, TAG, 'parseHttpBodyJson JSON.parse failed: %{public}s', (e as Error)?.message);
      return null;
    }
  }
  if (typeof raw === 'object' && raw !== null) {
    return raw as T;
  }
  return null;
}
