/**
 * 音乐源统一契约（与工厂模式配合）。
 * 各平台实现类负责同一套能力，差异仅在协议与解析逻辑。
 */

import type {
  SingleMusicSdkInterface,
  LeaderboardResult,
  LeaderboardListResult,
  SongListTagsResult,
  SongListResult,
  SongListDetailResult,
  HotSearchResult,
  MusicUrlResult,
} from './MusicSdkContracts';
import type { MusicInfo, LyricInfo, SearchResult } from '../../../types/MusicTypes';

/** 源侧可序列化配置（展示/超时等，可按需扩展） */
export interface MusicSourceClientConfig {
  timeoutMs?: number;
  userAgent?: string;
}

export interface IMusicSource {
  /** 源标识：kw | kg | tx | wy | mg */
  readonly sourceId: string;

  getConfig(): MusicSourceClientConfig;

  /**
   * 首次使用前初始化（如探测网络）；工厂在创建实例后触发，可为空实现。
   */
  initialize(): Promise<void>;

  /** 歌曲搜索 */
  search(keyword: string, page: number, limit: number): Promise<SearchResult | null>;

  /** 搜索联想词（可选，如酷我） */
  getSearchTip?(keyword: string): Promise<string[]>;

  getLyric(songInfo: MusicInfo): Promise<LyricInfo>;

  /** 封面图（曲目维度，对应业务里的 getPic） */
  getPic(songInfo: MusicInfo): Promise<string>;

  getMusicUrl(songInfo: MusicInfo, quality: string): Promise<MusicUrlResult>;

  getLeaderboards(): Promise<LeaderboardResult>;

  getLeaderboardSongs(bangId: string, page: number): Promise<LeaderboardListResult>;

  getSongListTags(): Promise<SongListTagsResult>;

  getSongList(sortId: string, tagId: string, page: number): Promise<SongListResult>;

  getSongListDetail(listId: string, page: number): Promise<SongListDetailResult>;

  getHotSearch(): Promise<HotSearchResult>;

  /** 兼容既有扁平 SDK（musicSdk / MusicSdkAggregate） */
  toSingleMusicSdkInterface(): SingleMusicSdkInterface;
}
