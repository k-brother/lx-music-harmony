// Songlist Search Store - 对应 src/store/search/songlist/state.ts
// 歌单搜索状态

// 歌单搜索结果项
export interface SonglistSearchResultItem {
  id: string;
  name: string;
  desc: string;
  pic: string;
  source: string;
  playCount: number;
  author: string;
}

// 歌单搜索状态
export class SonglistSearchState {
  // 搜索结果列表
  list: SonglistSearchResultItem[] = [];

  // 搜索来源
  source: string = 'kw';

  // 是否有更多
  hasMore: boolean = true;

  // 分页
  page: number = 1;

  // 是否正在搜索
  isSearching: boolean = false;
}

// 导出单例
export const songlistSearchState = new SonglistSearchState();
