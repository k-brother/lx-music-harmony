/**
 * 列表工具：排序 / 去重 / 名称归一
 *
 * 对齐安卓版 `Mylist/MyList/utils.ts` 的能力（排序字段与方向、重复歌曲识别规则），
 * 纯函数实现，供歌单详情、我喜欢的列表、本地音乐等复用。
 */

/** 可排序歌曲需具备的最小字段集合 */
export interface SortableSong {
  name: string;
  singer: string;
  album: string;
  /** 时长（秒），0 表示未知 */
  duration: number;
  source: string;
}

/** 排序字段 */
export type SortField = 'name' | 'singer' | 'album' | 'time' | 'source';
/** 排序方向：升序 / 降序 / 随机 */
export type SortOrder = 'up' | 'down' | 'random';

function compareText(a: string, b: string, locale: string): number {
  try {
    return a.localeCompare(b, locale);
  } catch (err) {
    return a < b ? -1 : (a > b ? 1 : 0);
  }
}

function fieldValue(song: SortableSong, field: SortField): string {
  if (field === 'name') {
    return song.name ?? '';
  }
  if (field === 'singer') {
    return song.singer ?? '';
  }
  if (field === 'album') {
    return song.album ?? '';
  }
  if (field === 'source') {
    return song.source ?? '';
  }
  return '';
}

/**
 * 排序比较器：升序时"未知值"排最后，降序时"未知值"排最后（与安卓版一致的手感）
 */
export function compareSongs(
  a: SortableSong,
  b: SortableSong,
  field: SortField,
  order: SortOrder,
  locale: string
): number {
  const ascend = order === 'up';
  if (field === 'time') {
    const at = a.duration ?? 0;
    const bt = b.duration ?? 0;
    if (at === 0 && bt === 0) {
      return 0;
    }
    if (at === 0) {
      return 1;
    }
    if (bt === 0) {
      return -1;
    }
    return ascend ? at - bt : bt - at;
  }
  const av = fieldValue(a, field);
  const bv = fieldValue(b, field);
  if (av.length === 0 && bv.length === 0) {
    return 0;
  }
  if (av.length === 0) {
    return 1;
  }
  if (bv.length === 0) {
    return -1;
  }
  const result = compareText(av, bv, locale);
  return ascend ? result : -result;
}

/** 洗牌（Fisher-Yates，原地） */
function shuffleSongs<T extends SortableSong>(list: T[]): void {
  for (let i = list.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const temp = list[i];
    list[i] = list[j];
    list[j] = temp;
  }
}

/** 排序并返回新的数组（不改动入参） */
export function sortSongs<T extends SortableSong>(
  list: T[],
  field: SortField,
  order: SortOrder,
  locale: string
): T[] {
  const result = list.slice();
  if (order === 'random') {
    shuffleSongs(result);
    return result;
  }
  result.sort((a: T, b: T): number => compareSongs(a, b, field, order, locale));
  return result;
}

/** 歌名里与"版本差异"无关的括号内容：Live / 伴奏 / 重制版 等 */
const VARIANT_PATTERN = /(\(|（).+(\)|）)/g;
/** 歌名里的分隔与标点噪声，归一后再比对，避免标点不同导致漏判重复 */
const NOISE_PATTERN = /\s|'|\.|,|，|&|"|、|\(|\)|（|）|`|~|-|<|>|\||\/|\]|\[/g;

/** 歌名归一：可选忽略 Live/伴奏等版本后缀 */
export function normalizeSongName(name: string, filterVariant: boolean): string {
  const lower = (name ?? '').toLowerCase();
  if (!filterVariant) {
    return lower.trim();
  }
  const withoutVariant = lower.replace(VARIANT_PATTERN, '').replace(NOISE_PATTERN, '');
  if (withoutVariant.length > 0) {
    return withoutVariant;
  }
  return lower.replace(/\s+/g, '');
}

function buildDuplicateGroups(list: SortableSong[], filterVariant: boolean): Map<string, number[]> {
  const groups = new Map<string, number[]>();
  for (let i = 0; i < list.length; i++) {
    const key = normalizeSongName(list[i].name, filterVariant);
    if (key.length === 0) {
      continue;
    }
    const existing = groups.get(key);
    if (existing) {
      existing.push(i);
    } else {
      groups.set(key, [i]);
    }
  }
  return groups;
}

/** 重复歌曲组数（每组至少 2 首） */
export function countDuplicateGroups(list: SortableSong[], filterVariant: boolean): number {
  const groups = buildDuplicateGroups(list, filterVariant);
  let count = 0;
  groups.forEach((indexes: number[]) => {
    if (indexes.length > 1) {
      count++;
    }
  });
  return count;
}

/**
 * 需要移除的下标：每组保留第一首，其余视为重复
 * @returns 升序下标数组
 */
export function findDuplicateIndexes(list: SortableSong[], filterVariant: boolean): number[] {
  const groups = buildDuplicateGroups(list, filterVariant);
  const result: number[] = [];
  groups.forEach((indexes: number[]) => {
    for (let i = 1; i < indexes.length; i++) {
      result.push(indexes[i]);
    }
  });
  result.sort((a: number, b: number): number => a - b);
  return result;
}

/** 去重后的新数组（每组保留第一首） */
export function dedupeSongs<T extends SortableSong>(list: T[], filterVariant: boolean): T[] {
  const removeIndexes = findDuplicateIndexes(list, filterVariant);
  if (removeIndexes.length === 0) {
    return list.slice();
  }
  const removeSet = new Set<number>(removeIndexes);
  const result: T[] = [];
  for (let i = 0; i < list.length; i++) {
    if (!removeSet.has(i)) {
      result.push(list[i]);
    }
  }
  return result;
}

/** 时长文本（秒 → mm:ss），实现统一在 utils/FormatTools，这里保持原有导入路径可用 */
export { formatDuration } from './FormatTools';
