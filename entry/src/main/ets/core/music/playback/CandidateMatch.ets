/**
 * 候选匹配与文本归一（从 ResolvePlayback 抽出）
 *
 * 换源、跨源搜索、歌词/封面兜底都要判断"两种来源是不是同一首歌"，
 * 于是有：歌手字段归一（清理 [object Object] 之类的脏数据）、
 * 标题松弛匹配（忽略 Live/现场版后缀）、候选打分、链路标识。
 * 这些是纯计算，独立成模块后可单独推演与回归。
 */
import type { MusicInfo } from '../../../types/MusicTypes';

export interface SingerNameLike {
  name?: string;
}

export function normalizeSingerText(singer: string | SingerNameLike | Array<string | SingerNameLike> | null | undefined): string {
  if (typeof singer === 'string') {
    let v = singer.trim();
    if (v.length === 0) {
      return '';
    }
    // 清理运行期对象被错误字符串化后的噪声（如 [object Object]、[object Object]、[object Object]）
    v = v.replace(/\[object Object\]/g, '').replace(/、{2,}/g, '、').replace(/^[、\s]+|[、\s]+$/g, '');
    return v;
  }
  if (Array.isArray(singer)) {
    const names: string[] = [];
    for (let i = 0; i < singer.length; i++) {
      const item = singer[i];
      if (typeof item === 'string') {
        const name = item.trim();
        if (name.length > 0) {
          names.push(name);
        }
        continue;
      }
      const maybe = item?.name;
      if (typeof maybe === 'string' && maybe.trim().length > 0) {
        names.push(maybe.trim());
      }
    }
    return names.join('、');
  }
  if (singer) {
    const maybeName = singer.name;
    if (typeof maybeName === 'string') {
      return maybeName.trim();
    }
  }
  return '';
}

export function normalizeCompareText(text: string): string {
  if (!text) {
    return '';
  }
  // 去除版本后缀（如“(Live)”“（现场版）”）与空白符，做松弛匹配
  let v = text
    .replace(/\(.*?\)/g, '')
    .replace(/（.*?）/g, '')
    .replace(/\s+/g, '')
    .toLowerCase()
    .trim();
  return v;
}

export function scoreCandidate(baseName: string, baseSinger: string, candidate: MusicInfo): number {
  const candName = normalizeCompareText(candidate.name || '');
  const candSinger = normalizeCompareText(normalizeSingerText(candidate.singer));
  let score = 0;
  if (candName === baseName) {
    score += 100;
  } else if (candName.includes(baseName) || baseName.includes(candName)) {
    score += 60;
  }
  if (candSinger === baseSinger) {
    score += 50;
  } else if (candSinger.includes(baseSinger) || baseSinger.includes(candSinger)) {
    score += 30;
  }
  return score;
}
export function musicInfoTrace(info: MusicInfo): string {
  const singerValue = normalizeSingerText(info.singer);
  return `name=${info.name || ''},singer=${singerValue},source=${info.source || ''},id=${info.id || ''},songmid=${info.songmid || ''},hash=${info.hash || ''},copyrightId=${info.copyrightId || ''}`;
}
