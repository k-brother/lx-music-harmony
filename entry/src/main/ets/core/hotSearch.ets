// HotSearch - 对应 src/core/hotSearch.ts
// 热搜功能

import { musicSdk } from './music/MusicFeatureEntry';
import { getHotSearch as getHotSearchFromSearch, HotSearchItem } from './search/search';

// 获取热搜列表
export async function getHotSearch(source: string = 'kw'): Promise<HotSearchItem[]> {
  try {
    // 使用 search 模块中的 getHotSearch 函数
    return await getHotSearchFromSearch(source);
  } catch {
    return [];
  }
}

// 获取歌手热搜
export async function getSingerHotSearch(): Promise<HotSearchItem[]> {
  try {
    // 使用酷我音乐源的歌手热搜API
    return await getHotSearchFromSearch('kw');
  } catch {
    return [];
  }
}
