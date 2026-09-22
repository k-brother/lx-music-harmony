/**
 * 简繁转换（对齐安卓版「播放设置 → 简繁转换」）
 *
 * 转换表来自 S2TTable（与安卓版同源），两个方向共用一份映射：
 * - s2t：简体 → 繁体
 * - t2s：繁体 → 简体（反向映射）
 *
 * 只对歌词文本生效，不改动歌曲名/歌手等元数据，避免影响搜索与匹配。
 */
import { SIMPLIFIED_CHARS, TRADITIONAL_CHARS } from './S2TTable';

/** 简繁转换模式 */
export type S2TMode = 'off' | 's2t' | 't2s';

let s2tMap: Map<string, string> | null = null;
let t2sMap: Map<string, string> | null = null;

function buildMap(source: string, target: string, reverse: boolean): Map<string, string> {
  const map = new Map<string, string>();
  const length = Math.min(source.length, target.length);
  for (let i = 0; i < length; i++) {
    const from = reverse ? target.charAt(i) : source.charAt(i);
    const to = reverse ? source.charAt(i) : target.charAt(i);
    // 同一个繁体字可能对应多个简体字，只在缺失时登记，保证反向结果稳定
    if (!map.has(from)) {
      map.set(from, to);
    }
  }
  return map;
}

function getS2TMap(): Map<string, string> {
  if (!s2tMap) {
    s2tMap = buildMap(SIMPLIFIED_CHARS, TRADITIONAL_CHARS, false);
  }
  return s2tMap;
}

function getT2SMap(): Map<string, string> {
  if (!t2sMap) {
    t2sMap = buildMap(SIMPLIFIED_CHARS, TRADITIONAL_CHARS, true);
  }
  return t2sMap;
}

function convertWith(map: Map<string, string>, source: string): string {
  if (source.length === 0) {
    return source;
  }
  let changed = false;
  const result: string[] = [];
  for (let i = 0; i < source.length; i++) {
    const char = source.charAt(i);
    const mapped = map.get(char);
    if (mapped !== undefined && mapped !== char) {
      result.push(mapped);
      changed = true;
    } else {
      result.push(char);
    }
  }
  return changed ? result.join('') : source;
}

/** 简体 → 繁体 */
export function toTraditional(source: string): string {
  return convertWith(getS2TMap(), source);
}

/** 繁体 → 简体 */
export function toSimplified(source: string): string {
  return convertWith(getT2SMap(), source);
}

/** 按模式转换；off 或未知模式原样返回 */
export function convertChinese(source: string, mode: S2TMode): string {
  if (!source || source.length === 0 || mode === 'off') {
    return source;
  }
  if (mode === 's2t') {
    return toTraditional(source);
  }
  if (mode === 't2s') {
    return toSimplified(source);
  }
  return source;
}
