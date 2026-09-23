/**
 * 搜索结果的页面结构
 *
 * 从 HomePage 抽出：搜索执行（SearchRunner）、结果列表组件（SearchResultLists）
 * 与页面共用同一份字段口径。
 */

/** 单曲搜索结果项 */
export interface SearchResultItem {
  id: string;
  songmid?: string;
  name: string;
  singer: string;
  album: string;
  pic: string;
  duration: number;
  source: string;
  albumId?: string;
  hash?: string;
  strMediaMid?: string;
  songId?: number;
  copyrightId?: string;
}

