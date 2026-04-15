// Music Search Store - 对应 src/store/search/music/state.ts
// 音乐搜索状态管理

// 音乐搜索结果项接口
export interface ListInfo {
  list: MusicInfoItem[];
  total: number;
  page: number;
  maxPage: number;
  limit: number;
  key: string | null;
}

// 音乐信息项
export interface MusicInfoItem {
  id: string;
  songmid?: string;
  name: string;
  singer: string;
  album: string;
  albumId: string | null;
  duration: number;
  source: string;
  pic: string;
  hash?: string;
  strMediaMid?: string;
  songId?: number;
  copyrightId?: string;
  lrc: string | null;
  interval: string | null;
}

// 搜索来源类型
export type Source = 'kw' | 'kg' | 'tx' | 'wy' | 'mg' | 'all';

// 搜索状态
class MusicSearchState {
  // 搜索关键字
  searchText: string = '';

  // 当前来源
  source: Source = 'kw';

  // 可用来源列表
  sources: Source[] = ['kw', 'kg', 'tx', 'wy', 'mg', 'all'];

  // 搜索结果列表 - 使用 Map 替代对象
  listInfos: Map<string, ListInfo> = new Map();

  // 最大页数记录 - 使用 Map 替代对象
  maxPages: Map<string, number> = new Map();
}

// 初始化状态
const state: MusicSearchState = new MusicSearchState();

// 初始化各源的状态
const sourceList: Source[] = ['kw', 'kg', 'tx', 'wy', 'mg', 'all'];
for (const src of sourceList) {
  const listInfo: ListInfo = {
    page: 1,
    maxPage: 1,
    limit: 20,
    total: 0,
    list: [],
    key: null,
  };
  state.listInfos.set(src, listInfo);
  state.maxPages.set(src, 1);
}

// 导出单例
export const musicSearchState = state;
