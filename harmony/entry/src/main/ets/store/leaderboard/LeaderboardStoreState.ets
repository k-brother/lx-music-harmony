// Leaderboard Store - 对应 src/store/leaderboard/state.ts
// 排行榜状态管理

// 排行榜来源
export type BoardSource = 'kw' | 'kg' | 'tx' | 'wy' | 'mg';

// 排行榜项
export interface BoardItem {
  id: string;
  name: string;
  description: string;
  pic: string;
  source: BoardSource;
  playCount: number | null;
}

// 歌曲项
export interface BoardMusicItem {
  id: string;
  name: string;
  singer: string;
  album: string;
  duration: number;
  pic: string;
  source: BoardSource;
}

// 排行榜状态
export class LeaderboardState {
  // 排行榜来源列表
  sourceList: BoardSource[] = ['kw', 'kg', 'tx', 'mg', 'wy'];

  // 当前来源
  activeSource: BoardSource = 'kw';

  // 排行榜列表
  boardList: BoardItem[] = [];

  // 当前排行榜歌曲列表
  musicList: BoardMusicItem[] = [];

  // 当前排行榜信息
  currentBoard: BoardItem | null = null;

  // 是否正在获取数据
  isFetching: boolean = false;

  // 是否有更多数据
  hasMore: boolean = true;

  // 分页
  page: number = 1;
}

// 导出单例
export const leaderboardState = new LeaderboardState();
