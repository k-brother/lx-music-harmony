/**
 * 内置音乐源（kw / kg / tx / wy / mg）统一契约
 * 供各源目录 `kw/`、`kg/` 等仅依赖本文件，避免与工厂/入口循环引用。
 */

import type { MusicInfo, LyricInfo, SearchResult } from '../../../types/MusicTypes';

export interface LeaderboardResult {
  list: LeaderboardItem[];
  source: string;
}

export interface LeaderboardItem {
  id: string;
  name: string;
  bangid: string;
  pic?: string;
}

export interface SongListDetailInfo {
  name: string;
  img: string;
  desc: string;
  author: string;
  play_count: string;
}

export interface SongListDetailResult {
  list: MusicInfo[];
  info: SongListDetailInfo;
  total: number;
  source: string;
  /** 当前页（歌单详情分页，缺省由调用方推断） */
  page?: number;
  /** 每页条数（如网易云单次最多 1000） */
  limit?: number;
}

export interface MusicSearchSdkInterface {
  search: (keyword: string, page: number, limit: number) => Promise<SearchResult | null>;
  tip?: (keyword: string) => Promise<string[]>;
}

export interface LeaderboardSdkInterface {
  getBoards: () => Promise<LeaderboardResult>;
  getList: (bangId: string, page: number) => Promise<LeaderboardListResult>;
}

export interface SongListTag {
  id: string;
  name: string;
  parent_id?: string;
  parent_name?: string;
  source?: string;
}

export interface SongListSdkInterface {
  getTags: () => Promise<SongListTagsResult>;
  getList: (sortId: string, tagId: string, page: number) => Promise<SongListResult>;
  getListDetail: (listId: string, page: number) => Promise<SongListDetailResult>;
  /**
   * 按关键字搜索歌单（可选能力：源未实现时返回 null，由上层跳过该源）
   */
  searchList?: (keyword: string, page: number, limit: number) => Promise<SongListResult | null>;
}

export interface HotSearchSdkInterface {
  search: () => Promise<HotSearchResult>;
}

export interface MusicUrlResult {
  url: string;
  type: string;
}

export interface LeaderboardListResult {
  list: MusicInfo[];
  total: number;
  page: number;
  limit: number;
  source: string;
}

export interface SongListTagsResult {
  tags: SongListTag[];
  hotTag: SongListTag[];
  source: string;
}

export interface SingleMusicSdkInterface {
  getLyric: (songInfo: MusicInfo) => Promise<LyricInfo>;
  getPic: (songInfo: MusicInfo) => Promise<string>;
  getMusicUrl: (songInfo: MusicInfo, quality: string) => Promise<MusicUrlResult>;
  musicSearch: MusicSearchSdkInterface;
  leaderboard: LeaderboardSdkInterface;
  songList: SongListSdkInterface;
  hotSearch: HotSearchSdkInterface;
}

export interface MusicSdkInterface {
  kw: SingleMusicSdkInterface;
  kg: SingleMusicSdkInterface;
  tx: SingleMusicSdkInterface;
  wy: SingleMusicSdkInterface;
  mg: SingleMusicSdkInterface;
}

export interface SourceInfo {
  id: string;
  name: string;
}

export interface SongListInfo {
  id: string;
  name: string;
  author: string;
  img: string;
  play_count: string;
  desc: string;
  total: number;
  source: string;
}

export interface SongListResult {
  list: SongListInfo[];
  total: number;
  page: number;
  limit: number;
  source: string;
}

export interface HotSearchItem {
  index: number;
  title: string;
  source: string;
  url: string | null;
  hot: number;
}

export interface HotSearchResult {
  list: HotSearchItem[];
  source: string;
}

