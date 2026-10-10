/**
 * 音源策略：启用顺序视图 / 跨源候选 / 候选打分
 *
 * 设置里「音源管理」只存两个列表（启用顺序 + 停用表），搜索聚合、自动跨源切换
 * 都要先把它算成「按用户偏好排序的可用源列表」再消费；这份过滤逻辑只写在这里，
 * 避免各处各写一份逐渐漂移。
 *
 * 纯计算模块：不读设置（列表由 service 层读好传入）、不发事件、不做 IO。
 */
import type { BuiltinSource } from '../../types/MusicSource';
import { SUPPORTED_SOURCES } from '../../types/MusicSource';
import { normalizeCompareText, normalizeSingerText } from './playback/CandidateMatch';

/** 跨源候选最低分：低于它认为不是同一首歌（歌名精确命中单项即 100） */
export const MIN_CROSS_SOURCE_SCORE = 60;

/**
 * 用户视角的可用源列表：按 sourceOrder 顺序、过滤停用表；
 * 顺序表里没有的源（新加入的内置源）按内置默认顺序补在尾部，除非被停用。
 */
export function orderedEnabledSources(sourceOrder: BuiltinSource[], disabledSources: BuiltinSource[]): BuiltinSource[] {
  const result: BuiltinSource[] = [];
  for (let i = 0; i < sourceOrder.length; i++) {
    const id = sourceOrder[i];
    if (disabledSources.indexOf(id) < 0 && result.indexOf(id) < 0) {
      result.push(id);
    }
  }
  for (let i = 0; i < SUPPORTED_SOURCES.length; i++) {
    const id = SUPPORTED_SOURCES[i] as BuiltinSource;
    if (disabledSources.indexOf(id) < 0 && result.indexOf(id) < 0) {
      result.push(id);
    }
  }
  return result;
}

/** 跨源候选：保持用户优先级顺序，剔除当前源（刚失败，不重复尝试） */
export function crossSourceCandidates(current: BuiltinSource, enabled: BuiltinSource[]): BuiltinSource[] {
  const result = enabled.slice();
  const idx = result.indexOf(current);
  if (idx >= 0) {
    result.splice(idx, 1);
  }
  return result;
}

/** 字符串 → 内置源 id（非法返回 null）：供「这歌能不能跨源」这类判断 */
export function toBuiltinSourceId(value: string): BuiltinSource | null {
  if (value === 'kw' || value === 'kg' || value === 'tx' || value === 'wy' || value === 'mg') {
    return value;
  }
  return null;
}

/**
 * 跨源候选打分（0+，越大越像同一首歌）：
 * - 歌名：归一后精确命中 100，互相包含 60，对不上 0（不足以放行）；
 * - 歌手：归一后精确 50 / 包含 30，任一端为空不加分（避免空串互相包含误判）；
 * - 时长：±3s +20，±10s +5，未知不加分。
 *
 * 与 scoreCandidate 的区别：带时长维度、空歌手不白捡分，专门给自动换源用；
 * 手动换源仍走 CandidateMatch.scoreCandidate，语义不动。
 */
export function scoreCrossSourceHit(
  targetName: string,
  targetSinger: string,
  targetDurationSec: number,
  candidateName: string,
  candidateSinger: string,
  candidateDurationSec: number
): number {
  const baseName = normalizeCompareText(targetName);
  if (baseName.length === 0) {
    return 0;
  }
  const candName = normalizeCompareText(candidateName);
  let score = 0;
  if (candName === baseName) {
    score += 100;
  } else if (candName.length > 0 && (candName.includes(baseName) || baseName.includes(candName))) {
    score += 60;
  }

  const baseSinger = normalizeCompareText(normalizeSingerText(targetSinger));
  const candSinger = normalizeCompareText(normalizeSingerText(candidateSinger));
  if (baseSinger.length > 0 && candSinger.length > 0) {
    if (candSinger === baseSinger) {
      score += 50;
    } else if (candSinger.includes(baseSinger) || baseSinger.includes(candSinger)) {
      score += 30;
    }
  }

  if (targetDurationSec > 0 && candidateDurationSec > 0) {
    const diff = Math.abs(targetDurationSec - candidateDurationSec);
    if (diff <= 3) {
      score += 20;
    } else if (diff <= 10) {
      score += 5;
    }
  }
  return score;
}
