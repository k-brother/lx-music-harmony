/**
 * 歌单详情的列表操作（排序 / 去重 / 落库）
 *
 * 这些是纯数据变换 + 一次存储写入，与页面渲染无关；
 * 从页面抽出来以后，页面只负责「确认弹窗 + 提示 + 刷新状态」。
 * 顺序落库见 SonglistLocalLibrary.persistLocalOrder（那里会复用库里的原始 MusicItem）。
 */
import { sortSongs, dedupeSongs, countDuplicateGroups, type SortField, type SortOrder } from '../../utils/ListTools';
import type { SongItem } from './SonglistTypes';

/** 排序后的行（保持原对象引用，播放态等字段不丢） */
export function sortRows(
  rows: SongItem[], field: SortField, order: SortOrder, locale: string
): SongItem[] {
  return sortSongs(rows, field, order, locale);
}

/** 重复歌曲分组数（用于确认弹窗前提示） */
export function countDuplicateGroupsOf(rows: SongItem[], ignoreVariant: boolean): number {
  return countDuplicateGroups(rows, ignoreVariant);
}

export interface DedupeOutcome {
  rows: SongItem[];
  removed: number;
}

/** 去重结果（保留先出现的一条） */
export function dedupeRows(rows: SongItem[], ignoreVariant: boolean): DedupeOutcome {
  const before = rows.length;
  const deduped = dedupeSongs(rows, ignoreVariant);
  const outcome: DedupeOutcome = { rows: deduped, removed: before - deduped.length };
  return outcome;
}
