/**
 * 播放队列推进规则（纯函数）
 *
 * 抽出来的原因：队列的"下一首/上一首/移除后下标怎么变"是 4 种播放模式 × 边界条件的
 * 组合，原来散落在 playNext / playPrev / 播完回调 / 自动清理里，改一处要看四处。
 * 这里只做计算、不持状态，便于推演与回归（也方便以后加"摇一摇""队列去重"等能力）。
 */

/** 播放模式（与设置 PlayMode 一致） */
export type QueuePlayMode = 'listLoop' | 'singleLoop' | 'random' | 'sequential';

/** 顺序播放到末尾时的停止标记 */
export const NO_NEXT_INDEX = -1;

/**
 * 计算下一首下标
 * - singleLoop：原地重播
 * - random：由调用方提供随机下标（需要避开当前，见 pickRandomIndex）
 * - sequential：到末尾返回 -1（停止）
 * - listLoop：到末尾回到第一首
 */
export function nextIndexFor(size: number, currentIndex: number, mode: QueuePlayMode): number {
  if (size <= 0) {
    return NO_NEXT_INDEX;
  }
  if (mode === 'singleLoop') {
    return currentIndex;
  }
  const next = currentIndex + 1;
  if (next <= size - 1) {
    return next;
  }
  return mode === 'sequential' ? NO_NEXT_INDEX : 0;
}

/**
 * 计算上一首下标（不含随机模式，随机模式回退由调用方用随机历史处理）
 * 到队首时回到末尾（列表循环语义）。
 */
export function prevIndexFor(size: number, currentIndex: number): number {
  if (size <= 0) {
    return NO_NEXT_INDEX;
  }
  const prev = currentIndex - 1;
  return prev < 0 ? size - 1 : prev;
}

/**
 * 随机下标（尽量避开当前曲目；只有一首时返回 0）
 * @param exclude 需要避开的候选集合（如最近播放过的下标）
 */
export function pickRandomIndex(size: number, currentIndex: number, exclude: Set<number>): number {
  if (size <= 0) {
    return NO_NEXT_INDEX;
  }
  if (size === 1) {
    return 0;
  }
  const candidates: number[] = [];
  for (let i = 0; i < size; i++) {
    if (i !== currentIndex && !exclude.has(i)) {
      candidates.push(i);
    }
  }
  if (candidates.length === 0) {
    // 全部被排除：退化为"不与当前重复"
    const fallback = currentIndex === size - 1 ? 0 : currentIndex + 1;
    return fallback;
  }
  return candidates[Math.floor(Math.random() * candidates.length)];
}

/**
 * 从队列移除一首后，当前下标应变成什么
 * - 移除的在当前之前：整体左移
 * - 移除的就是当前：回退一格，使"下一首"正好落在后移补位的歌曲上
 * @returns 新的当前下标（队列为空时为 -1）
 */
export function indexAfterRemoval(sizeBefore: number, currentIndex: number, removedAt: number): number {
  const sizeAfter = Math.max(0, sizeBefore - 1);
  if (sizeAfter === 0) {
    return -1;
  }
  let next = currentIndex;
  if (removedAt < currentIndex) {
    next = currentIndex - 1;
  } else if (removedAt === currentIndex) {
    next = removedAt - 1;
  }
  if (next > sizeAfter - 1) {
    next = sizeAfter - 1;
  }
  return next < 0 ? 0 : next;
}

/** 随机历史裁剪：超过上限时只保留最近一段，避免无限增长 */
export function trimRandomHistory(history: number[], limit: number, keep: number): number[] {
  if (history.length <= limit) {
    return history;
  }
  return history.slice(-keep);
}

/**
 * 拖动排序后当前下标变成什么（保持「正在播放的那首」不变）
 * @returns 新的当前下标
 */
export function indexAfterMove(currentIndex: number, from: number, to: number): number {
  if (currentIndex === from) {
    return to;
  }
  if (from < currentIndex && to >= currentIndex) {
    return currentIndex - 1;
  }
  if (from > currentIndex && to <= currentIndex) {
    return currentIndex + 1;
  }
  return currentIndex;
}

/**
 * 「下一首播放」的插入点与插入后当前下标。
 * 队列里已有这首歌时先摘掉再插到当前之后，摘的位置在当前之前会让插入点左移。
 * @param existsAt 歌曲当前所在下标，-1 表示不在队列里
 */
export function insertNextPlan(currentIndex: number, existsAt: number): number[] {
  const insertAt = currentIndex + 1;
  const adjusted = existsAt >= 0 && existsAt < insertAt ? insertAt - 1 : insertAt;
  // [插入点, 插入后当前下标]
  const keepIndex = currentIndex;
  return [adjusted, keepIndex];
}

/** 只带 id 的最小结构：用于在「更完整的列表」里定位当前曲目 */
export interface Identifiable {
  id: string;
}

/** 用更完整的列表替换队列后，当前曲目的新下标（找不到返回 -1） */
export function indexInRefinedList(fullList: Identifiable[], currentId: string): number {
  return fullList.findIndex((item: Identifiable): boolean => item.id === currentId);
}

/**
 * 从队列移除某一首后，当前下标变成什么。
 * 与 indexAfterRemoval 的差别：这里已知「移除的下标」，且保留「移除当前曲目时不打断播放」的语义
 * （下标指向原位置的下一首，越界则退回队尾）。
 */
export function indexAfterRemoveAt(currentIndex: number, removedAt: number, sizeAfter: number): number {
  if (sizeAfter <= 0) {
    return -1;
  }
  if (removedAt < currentIndex) {
    return currentIndex - 1;
  }
  if (removedAt === currentIndex) {
    return Math.min(removedAt, sizeAfter - 1);
  }
  return currentIndex;
}
