/**
 * 首页搜索执行（单曲 / 歌单）
 *
 * 从 HomePage 抽出：这里只有「调 core/search → 规范化成页面用的结果结构 →
 * 当前源无结果时回退全源」的纯逻辑，页面的 epoch 守卫、加载态、视图切换仍在页面。
 */
import { appLog as hilog } from '../../../core/log/AppLogger';
import { searchMusic, searchSonglist, type Source, type SonglistSearchResult } from '../../../core/search/search';
import type { SearchResultItem } from './SearchResultTypes';

const TAG = 'SearchRunner';
const DOMAIN: number = 0x0001;

/** 单曲搜索：当前源无结果时回退全源聚合 */
export async function runSongSearch(query: string, source: Source): Promise<SearchResultItem[]> {
  let results = await searchMusic(query, 1, source);
  if (results.length === 0 && source !== 'all') {
    results = await searchMusic(query, 1, 'all');
  }
  hilog.info(DOMAIN, TAG, 'doSearch query=%{public}s source=%{public}s count=%{public}d',
    query, source, results.length);
  const items: SearchResultItem[] = [];
  for (let i = 0; i < results.length; i++) {
    const r = results[i];
    const item: SearchResultItem = {
      id: r.id,
      songmid: r.songmid,
      name: r.name,
      singer: r.singer,
      album: r.album,
      pic: r.pic || '',
      duration: r.duration,
      source: r.source,
      albumId: r.albumId,
      hash: r.hash,
      strMediaMid: r.strMediaMid,
      songId: r.songId,
      copyrightId: r.copyrightId,
    };
    items.push(item);
  }
  return items;
}

/** 歌单搜索（结构不同，走独立接口） */
export async function runSonglistSearch(query: string, source: Source): Promise<SonglistSearchResult[]> {
  const results = await searchSonglist(query, 1, source);
  hilog.info(DOMAIN, TAG, 'doSearchSonglist query=%{public}s count=%{public}d', query, results.length);
  return results;
}

/**
 * 搜索历史：把关键词提到最前并按设置截断（返回新数组，页面直接赋值）。
 */
export function promoteHistoryWord(history: string[], query: string, limit: number): string[] {
  const next: string[] = history.filter((word: string): boolean => word !== query);
  next.unshift(query);
  return next.length > limit ? next.slice(0, limit) : next;
}
