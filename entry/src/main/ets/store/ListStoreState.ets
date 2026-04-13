// List Store - 对应 src/store/list/state.ts
// 播放列表状态管理

// 列表类型
export type ListType = 'default' | 'love' | 'user';

// 列表信息基础接口
export interface ListInfoBase {
  id: string;
  name: string;
  source: string;
  desc: string;
  pic: string;
  count: number;
  createTime: number;
  updateTime: number;
}

// 默认列表信息
export interface DefaultListInfo extends ListInfoBase {
  type: 'default';
}

// 我喜欢的列表信息
export interface LoveListInfo extends ListInfoBase {
  type: 'love';
}

// 用户列表信息
export interface UserListInfo extends ListInfoBase {
  type: 'user';
  // revoke: boolean;
}

// 音乐项信息
export interface MusicItem {
  id: string;
  name: string;
  singer: string;
  album: string;
  albumId: string | null;
  pic: string;
  lrc: string | null;
  tlrc: string | null;
  rlrc: string | null;
  lxlrc: string | null;
  duration: number;
  source: string;
}

// 列表状态
export class ListState {
  // 列表信息
  defaultList: DefaultListInfo | null = null;
  loveList: LoveListInfo | null = null;
  userList: UserListInfo[] = [];

  // 音乐列表
  defaultListMusic: MusicItem[] = [];
  loveListMusic: MusicItem[] = [];
  userListMusic: Map<string, MusicItem[]> = new Map();

  // 当前播放列表
  playList: MusicItem[] = [];
  playListId: string | null = null;
  playIndex: number = -1;

  // 其他状态
  fetchingListStatus: boolean = false;
  listUpdateId: string | null = null;
}

// 导出单例
export const listState = new ListState();
