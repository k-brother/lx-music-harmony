// Leaderboard Core Module - 对应 src/core/leaderboard.ts
// 排行榜核心模块

import { leaderboardState, BoardItem, BoardMusicItem, BoardSource } from '../store/leaderboard/LeaderboardStoreState';
import {
  musicSdk,
  type LeaderboardResult,
  type LeaderboardSdkInterface,
  type LeaderboardItem,
  type LeaderboardListResult,
} from './music/MusicFeatureEntry';
import type { MusicInfo } from '../types/MusicTypes';
import { pluginManager } from './plugin/PluginManager';

// 排行榜详情信息
export interface ListDetailInfo {
  id: string;
  name: string;
  list: BoardMusicItem[];
  total: number;
  page: number;
  limit: number;
}

// 排行榜信息
export interface Board {
  id: string;
  name: string;
  description: string | null;
  pic: string | null;
  playCount: number | null;
  list: BoardItem[];
}

// 缓存
const cache: Map<string, ListDetailInfo[]> = new Map();
const LIST_LOAD_LIMIT = 30;

// 设置排行榜详情信息
export function setListDetailInfo(id: string): void {
  clearListDetail();
  const parts = id.split('__');
  const source = parts[0];
  leaderboardState.activeSource = source as BoardSource;
}

export function setListDetail(result: ListDetailInfo, id: string, page: number): void {
  leaderboardState.musicList = result.list;
  leaderboardState.page = page;
  leaderboardState.hasMore = result.list.length >= result.limit;
}

export function clearListDetail(): void {
  leaderboardState.musicList = [];
  leaderboardState.page = 1;
  leaderboardState.hasMore = true;
}

// 设置排行榜
function setBoard(board: Board, source: BoardSource): void {
  // 更新状态中的排行榜列表
  leaderboardState.boardList = board.list;
  leaderboardState.currentBoard = board.list.length > 0 ? board.list[0] : null;
}

// 获取排行榜列表
export async function getBoardsList(source: BoardSource): Promise<BoardItem[]> {
  try {
    const activePlugin = pluginManager.getActivePlugin();
    if (activePlugin && activePlugin.onGetBoards) {
      try {
        const pluginBoards = await activePlugin.onGetBoards();
        if (pluginBoards && pluginBoards.length > 0) {
          const boardItems: BoardItem[] = pluginBoards.map((item, idx): BoardItem => ({
            id: `${source}__${item.id || String(idx + 1)}`,
            name: item.name || '',
            description: '',
            pic: item.pic || '',
            source: source as BoardSource,
            playCount: item.playCount ?? null,
          }));
          const board: Board = {
            id: source,
            name: source,
            description: null,
            pic: null,
            playCount: null,
            list: boardItems,
          };
          setBoard(board, source);
          return boardItems;
        }
      } catch {
        // fallback to builtin source
      }
    }

    let result: LeaderboardResult | null = null;
    switch (source) {
      case 'kw':
        result = await musicSdk.kw.leaderboard.getBoards();
        break;
      case 'kg':
        result = await musicSdk.kg.leaderboard.getBoards();
        break;
      case 'tx':
        result = await musicSdk.tx.leaderboard.getBoards();
        break;
      case 'wy':
        result = await musicSdk.wy.leaderboard.getBoards();
        break;
      case 'mg':
        result = await musicSdk.mg.leaderboard.getBoards();
        break;
      default:
        result = null;
    }
    if (result && result.list) {
      // 统一为「源__榜单业务 id」，供详情页 split 与 SDK getList(bangid) 使用；勿与各源自带的 tx__ / kg__ 前缀再拼一次
      const boardItems: BoardItem[] = result.list.map((item: LeaderboardItem): BoardItem => ({
        id: `${source}__${item.bangid}`,
        name: item.name,
        description: '',
        pic: item.pic || '',
        source: source as BoardSource,
        playCount: null,
      }));
      const board: Board = {
        id: source,
        name: source,
        description: null,
        pic: null,
        playCount: null,
        list: boardItems,
      };
      setBoard(board, source);
      return boardItems;
    }
    return [];
  } catch {
    return [];
  }
}

// 获取排行榜列表（兼容性别名）
export { getBoardsList as getLeaderboard };

// 获取排行榜内单页歌曲
export async function getListDetail(
  id: string,
  page: number,
  isRefresh: boolean = false
): Promise<ListDetailInfo> {
  const parts = id.split('__');
  const source = parts[0];
  const bangId = parts[1];
  const listKey = `${source}__${bangId}`;
  const pageKey = `${listKey}__${page}`;

  // 缓存逻辑（暂时禁用）
  // let listCache = cache.get(listKey);
  // if (!listCache || isRefresh) {
  //   cache.set(listKey, listCache = new Map());
  // }
  // let pageCache = listCache.get(pageKey);
  // if (pageCache) return pageCache.data;

  // 调用对应音乐源的API
  try {
    const activePlugin = pluginManager.getActivePlugin();
    if (source !== 'local' && activePlugin && activePlugin.onGetBoardList) {
      try {
        const pluginResult = await activePlugin.onGetBoardList(bangId, page);
        if (pluginResult && pluginResult.list && pluginResult.list.length > 0) {
          const musicItems: BoardMusicItem[] = pluginResult.list.map((item): BoardMusicItem => ({
            id: item.songmid || '',
            name: item.name || '',
            singer: item.singer || '',
            album: item.albumName || '',
            duration: 0,
            pic: '',
            source: (item.source || source) as BoardSource,
          }));
          const detailInfo: ListDetailInfo = {
            id,
            name: pluginResult.name || bangId,
            list: musicItems,
            total: pluginResult.total || musicItems.length,
            page: pluginResult.page || page,
            limit: LIST_LOAD_LIMIT,
          };
          setListDetail(detailInfo, id, page);
          return detailInfo;
        }
      } catch {
        // fallback to builtin source
      }
    }

    let result: LeaderboardListResult | null = null;
    switch (source) {
      case 'kw':
        result = await musicSdk.kw.leaderboard.getList(bangId, page);
        break;
      case 'kg':
        result = await musicSdk.kg.leaderboard.getList(bangId, page);
        break;
      case 'tx':
        result = await musicSdk.tx.leaderboard.getList(bangId, page);
        break;
      case 'wy':
        result = await musicSdk.wy.leaderboard.getList(bangId, page);
        break;
      case 'mg':
        result = await musicSdk.mg.leaderboard.getList(bangId, page);
        break;
      default:
        result = null;
    }
    if (result && result.list) {
      const musicItems: BoardMusicItem[] = result.list.map((item: MusicInfo): BoardMusicItem => ({
        id: item.songmid || item.id || '',
        name: item.name,
        singer: item.singer,
        album: item.albumName || item.album || '',
        duration: 0,
        pic: item.img || item.pic || '',
        source: item.source as BoardSource,
      }));
      const detailInfo: ListDetailInfo = {
        id,
        name: bangId,
        list: musicItems,
        total: result.total || result.list.length,
        page: result.page || page,
        limit: result.limit || LIST_LOAD_LIMIT,
      };
      // 更新存储状态
      setListDetail(detailInfo, id, page);
      return detailInfo;
    }
  } catch {
    // 忽略错误
  }

  return {
    id,
    name: '',
    list: [],
    total: 0,
    page: 1,
    limit: 30,
  };
}

// 获取排行榜详情
export async function getLeaderboardDetail(source: string, id: string, page: number = 1): Promise<ListDetailInfo | null> {
  try {
    const fullId = `${source}__${id}`;
    return await getListDetail(fullId, page);
  } catch (e) {
    return null;
  }
}

// 获取排行榜内全部歌曲（分页获取所有歌曲）
export async function getListDetailAll(
  id: string,
  isRefresh: boolean = false
): Promise<BoardMusicItem[]> {
  const parts = id.split('__');
  const source = parts[0];
  const bangId = parts[1];
  const allMusicList: BoardMusicItem[] = [];
  let currentPage = 1;
  let hasMore = true;

  while (hasMore) {
    try {
      const activePlugin = pluginManager.getActivePlugin();
      if (source !== 'local' && activePlugin && activePlugin.onGetBoardList) {
        const pluginResult = await activePlugin.onGetBoardList(bangId, currentPage);
        if (pluginResult && pluginResult.list && pluginResult.list.length > 0) {
          const musicItems: BoardMusicItem[] = pluginResult.list.map((item): BoardMusicItem => ({
            id: item.songmid || '',
            name: item.name || '',
            singer: item.singer || '',
            album: item.albumName || '',
            duration: 0,
            pic: '',
            source: (item.source || source) as BoardSource,
          }));
          allMusicList.push(...musicItems);
          const total = pluginResult.total || allMusicList.length;
          hasMore = allMusicList.length < total && musicItems.length >= LIST_LOAD_LIMIT;
          currentPage++;
          continue;
        }
      }

      let result: LeaderboardListResult | null = null;
      switch (source) {
        case 'kw':
          result = await musicSdk.kw.leaderboard.getList(bangId, currentPage);
          break;
        case 'kg':
          result = await musicSdk.kg.leaderboard.getList(bangId, currentPage);
          break;
        case 'tx':
          result = await musicSdk.tx.leaderboard.getList(bangId, currentPage);
          break;
        case 'wy':
          result = await musicSdk.wy.leaderboard.getList(bangId, currentPage);
          break;
        case 'mg':
          result = await musicSdk.mg.leaderboard.getList(bangId, currentPage);
          break;
        default:
          result = null;
      }

      if (result && result.list && result.list.length > 0) {
        const musicItems: BoardMusicItem[] = result.list.map((item: MusicInfo): BoardMusicItem => ({
          id: item.songmid || item.id || '',
          name: item.name,
          singer: item.singer,
          album: item.albumName || item.album || '',
          duration: 0,
          pic: item.img || item.pic || '',
          source: item.source as BoardSource,
        }));
        allMusicList.push(...musicItems);
        hasMore = musicItems.length >= LIST_LOAD_LIMIT;
        currentPage++;
      } else {
        hasMore = false;
      }
    } catch {
      hasMore = false;
    }
  }

  return allMusicList;
}
