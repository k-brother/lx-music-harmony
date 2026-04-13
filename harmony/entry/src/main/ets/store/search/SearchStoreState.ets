// Search Store - 对应 src/store/search/state.ts
// 搜索状态管理

import { MusicSource } from '../../types/MusicSource';

// 搜索类型
export type SearchType = 'music' | 'songlist';

// 搜索来源（使用统一的 MusicSource 类型）
export type SearchSource = 'kw' | 'kg' | 'tx' | 'mg' | 'wy';

// 搜索状态
export class SearchState {
  // 搜索关键字
  searchText: string = '';

  // 搜索类型
  type: SearchType = 'music';

  // 搜索来源
  source: SearchSource = 'kw';

  // 搜索历史
  searchHistory: string[] = [];

  // 是否正在搜索
  isSearching: boolean = false;

  // 热门搜索列表
  hotSearchList: HotSearchItem[] = [];

  // 搜索结果
  musicResult: MusicSearchResult | null = null;
  songlistResult: SonglistSearchResult | null = null;

  // 歌手热搜列表
  singerHotSearchList: SingerHotSearchItem[] = [];
}

// 热门搜索项
export interface HotSearchItem {
  index: number;
  title: string;
  source: SearchSource;
  url: string;
  engine: string;
}

// 歌手热门搜索项
export interface SingerHotSearchItem {
  name: string;
  singerMid: string;
}

// 音乐搜索结果
export interface MusicSearchResult {
  list: MusicSearchResultItem[];
  source: SearchSource;
}

// 音乐搜索结果项
export interface MusicSearchResultItem {
  id: string;
  name: string;
  singer: string;
  album: string;
  albumId: string | null;
  duration: number;
  source: SearchSource;
  pic: string;
  lrc: string | null;
}

// 歌单搜索结果
export interface SonglistSearchResult {
  list: SonglistSearchResultItem[];
  source: SearchSource;
}

// 歌单搜索结果项
export interface SonglistSearchResultItem {
  id: string;
  name: string;
  desc: string;
  pic: string;
  source: SearchSource;
  playCount: number;
  author: string;
}

// 导出单例
export const searchState = new SearchState();
