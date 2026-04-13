/**
 * 内置源聚合 SDK（music 根目录上的「对外能力」实现之一）。
 * 通过 `./MusicSourceRegistry`（内置表 + `resolveBuiltinMusicSdk`）与工厂访问 `sources/` 下各源能力；
 * 本模块与 `MusicFeatureEntry`、`ResolvePlayback` 等共同构成根目录对外接口及其实现，不直接暴露 `sources/*` 给上层模块。
 */

import type { MusicInfo, LyricInfo, SearchResult } from '../../types/MusicTypes';
import type {
  LeaderboardResult,
  LeaderboardListResult,
  SongListTagsResult,
  SongListResult,
  SongListDetailResult,
  HotSearchResult,
  MusicSdkInterface,
  SourceInfo,
} from './sources/MusicSdkContracts';
import { resolveBuiltinMusicSdk, createMusicSdkAggregate } from './MusicSourceRegistry';

export type { MusicInfo, SearchResult };
export * from './sources/MusicSdkContracts';

export const sources: SourceInfo[] = [
  { id: 'kw', name: '酷我音乐' },
  { id: 'kg', name: '酷狗音乐' },
  { id: 'tx', name: 'QQ音乐' },
  { id: 'wy', name: '网易音乐' },
  { id: 'mg', name: '咪咕音乐' },
];

export const musicSdk: MusicSdkInterface = createMusicSdkAggregate();

/**
 * 搜索歌曲
 * @param keyword 搜索关键词
 * @param page 页码
 * @param limit 每页数量
 * @param source 音乐源，不传则搜索所有源
 */
export async function searchMusic(
  keyword: string,
  page: number = 1,
  limit: number = 30,
  source?: string
): Promise<SearchResult[]> {
  const trimKeyword = keyword.trim();
  const tasks: Promise<SearchResult | null>[] = [];
  const excludeSource: string[] = ['xm'];

  for (const sourceInfo of sources) {
    if (source && sourceInfo.id !== source) {
      continue;
    }
    if (excludeSource.includes(sourceInfo.id)) {
      continue;
    }
    const sdk = resolveBuiltinMusicSdk(sourceInfo.id);
    tasks.push(sdk.musicSearch.search(trimKeyword, page, limit).catch(() => null));
  }

  const results = await Promise.all(tasks);
  const filteredResults: SearchResult[] = [];
  for (const r of results) {
    if (r !== null) {
      filteredResults.push(r as SearchResult);
    }
  }
  return filteredResults;
}

/**
 * 获取歌曲歌词
 */
export async function getLyric(songInfo: MusicInfo, isGetLyricx: boolean = true): Promise<LyricInfo> {
  void isGetLyricx;
  const sdk = resolveBuiltinMusicSdk(songInfo.source);
  return sdk.getLyric(songInfo);
}

/**
 * 获取歌曲播放 URL
 */
export async function getMusicUrl(songInfo: MusicInfo, quality: string = '320k'): Promise<string> {
  const sdk = resolveBuiltinMusicSdk(songInfo.source);
  const result = await sdk.getMusicUrl(songInfo, quality);
  return result.url;
}

/**
 * 获取排行榜列表
 */
export async function getLeaderboard(source: string = 'kw'): Promise<LeaderboardResult> {
  return resolveBuiltinMusicSdk(source).leaderboard.getBoards();
}

/**
 * 获取排行榜歌曲列表
 */
export async function getLeaderboardList(
  bangId: string,
  page: number = 1,
  source: string = 'kw'
): Promise<LeaderboardListResult> {
  return resolveBuiltinMusicSdk(source).leaderboard.getList(bangId, page);
}

/**
 * 获取歌单标签
 */
export async function getSongListTags(source: string = 'kw'): Promise<SongListTagsResult> {
  return resolveBuiltinMusicSdk(source).songList.getTags();
}

/**
 * 获取歌单列表
 */
export async function getSongList(
  sortId: string,
  tagId: string,
  page: number = 1,
  source: string = 'kw'
): Promise<SongListResult> {
  return resolveBuiltinMusicSdk(source).songList.getList(sortId, tagId, page);
}

/**
 * 获取歌单详情
 */
export async function getSongListDetail(
  listId: string,
  page: number = 1,
  source: string = 'kw'
): Promise<SongListDetailResult> {
  return resolveBuiltinMusicSdk(source).songList.getListDetail(listId, page);
}

/**
 * 获取热门搜索
 */
export async function getHotSearch(source: string = 'kw'): Promise<HotSearchResult> {
  return resolveBuiltinMusicSdk(source).hotSearch.search();
}
