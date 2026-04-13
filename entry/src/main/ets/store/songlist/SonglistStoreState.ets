// Songlist Store - 对应 src/store/songlist/state.ts
// 歌单状态管理

// 歌单来源
export type Source = 'kw' | 'kg' | 'tx' | 'mg' | 'wy';

// 标签信息
export interface TagInfo {
  name: string;
  id: string;
  tagId?: string;
  type?: number;
}

// 歌单信息
export interface SonglistInfo {
  id: string;
  name: string;
  desc: string;
  pic: string;
  author: string;
  source: Source;
  createTime: number | null;
  updateTime: number | null;
  count: number | null;
  playCount: number | null;
  shareCount: number | null;
  collectCount: number | null;
  tags: TagInfo[] | null;
  img?: string;
  play_count?: string;
  total?: number;
}

// 歌单状态
export class SonglistState {
  // 歌单来源列表
  sourceList: Source[] = ['kw', 'kg', 'tx', 'mg', 'wy'];

  // 当前来源
  activeSource: Source = 'kw';

  // 标签列表
  tagList: TagInfo[] = [];

  // 当前标签
  activeTagId: string = '';

  // 歌单列表
  songList: SonglistInfo[] = [];

  // 是否正在获取列表
  isFetching: boolean = false;

  // 是否有更多数据
  hasMore: boolean = true;

  // 分页
  page: number = 1;

  // 详情信息
  detailInfo: object | null = null;

  // 详情列表
  detailList: Array<object> = [];

  // 详情分页
  detailPage: number = 1;
}

// 导出单例
export const songlistState = new SonglistState();
