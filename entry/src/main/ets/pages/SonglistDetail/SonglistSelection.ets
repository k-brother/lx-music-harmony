/**
 * 歌单详情「多选」的纯函数集合
 *
 * 多选用下标而不是 id 收集，这样同一首歌出现多次时能精确删掉被点的那一条。
 * 这些函数不碰状态、不发请求，页面只做赋值，便于单测与复用。
 */
import type { SongItem } from './SonglistTypes';

/** 按对象引用找下标（列表里可能有同 id 的重复项，必须比引用） */
export function indexOfRowRef(rows: SongItem[], target: SongItem): number {
  for (let i = 0; i < rows.length; i++) {
    if (rows[i] === target) {
      return i;
    }
  }
  return -1;
}

/** 勾选 / 取消勾选，返回新的下标数组（调用方负责赋值触发刷新） */
export function toggleIndex(selection: number[], index: number): number[] {
  const next = selection.slice();
  const at = next.indexOf(index);
  if (at >= 0) {
    next.splice(at, 1);
  } else {
    next.push(index);
  }
  return next;
}

/** 全选的下标数组 */
export function allIndexes(count: number): number[] {
  const all: number[] = [];
  for (let i = 0; i < count; i++) {
    all.push(i);
  }
  return all;
}

/** 是否已全选（选中数 == 列表长度，用于「全选/取消全选」按钮） */
export function isAllSelected(selection: number[], count: number): boolean {
  return count > 0 && selection.length === count;
}

/** 下标数组 → 行数组（越界的下标会被跳过） */
export function rowsAt(rows: SongItem[], selection: number[]): SongItem[] {
  const result: SongItem[] = [];
  for (let i = 0; i < selection.length; i++) {
    const song = rows[selection[i]];
    if (song) {
      result.push(song);
    }
  }
  return result;
}

/** 按对象引用判断是否包含某一行 */
export function containsRowRef(rows: SongItem[], target: SongItem): boolean {
  return indexOfRowRef(rows, target) >= 0;
}
