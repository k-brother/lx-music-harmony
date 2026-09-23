// Leaderboard Core Module - 对应 src/core/leaderboard.ts
// 排行榜核心模块

import { leaderboardState, BoardItem, BoardMusicItem, BoardSource } from '../store/leaderboard/LeaderboardStoreState';
import {
  musicSdk,
  type LeaderboardResult,
  type LeaderboardItem,
  type LeaderboardListResult,
} from './music/MusicFeatureEntry';
import type { MusicInfo } from '../types/MusicTypes';
import { pluginManager } from './plugin/PluginManager';
import hilog from '@ohos.hilog';

const DOMAIN = 0xFF00;
const TAG = 'Leaderboard';

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

function parseBoardSource(id: string): string {
  const ix = id.indexOf('__');
  if (ix < 0) {
    return id;
  }
  return id.substring(0, ix);
}

function parseBoardBangId(id: string): string {
  const ix = id.indexOf('__');
  if (ix < 0) {
    return '';
  }
  return id.substring(ix + 2);
}

/** 防止 `tx__tx__4` 等重复前缀拼进 fullId，预览与详情与 BoardDetail 首段 split 不一致 */
function httpsifyMediaUrl(url: string): string {
  if (!url || url.length === 0) {
    return '';
  }
  if (url.startsWith('//')) {
    return `https:${url}`;
  }
  if (url.startsWith('http://')) {
    return `https://${url.substring(7)}`;
  }
  return url;
}

function stripRepeatedSourcePrefix(source: string, bang: string): string {
  const prefix = `${source}__`;
  let out = bang;
  while (out.startsWith(prefix)) {
    out = out.substring(prefix.length);
  }
  return out;
}

/**
 * 各源 `LeaderboardItem.id` 形态不一：`tx__4`、`kg__8888`、`wy19723756`。
 * 统一成「源__业务 id」，避免拼成 `kg__kg__8888` 导致预览/详情请求参数错误。
 */
function canonicalBoardRowId(source: string, item: LeaderboardItem): string {
  const sid = item.id ? item.id : '';
  if (sid.indexOf('__') >= 0) {
    return sid;
  }
  return `${source}__${item.bangid}`;
}

// 设置排行榜详情信息
export function setListDetailInfo(id: string): void {
  clearListDetail();
  const source = parseBoardSource(id);
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
          const boardItems: BoardItem[] = pluginBoards.map((item, idx): BoardItem => {
            const idStr = item.id != null && item.id !== '' ? String(item.id) : String(idx + 1);
            const row: LeaderboardItem = {
              id: idStr,
              name: item.name || '',
              bangid: idStr,
            };
            return {
              id: canonicalBoardRowId(source, row),
              name: item.name || '',
              description: '',
              pic: httpsifyMediaUrl(item.pic || ''),
              source: source as BoardSource,
              playCount: item.playCount ?? null,
            };
          });
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
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Plugin leaderboard fetch failed, falling back to builtin: %{public}s', e?.message);
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
        id: canonicalBoardRowId(source, item),
        name: item.name,
        description: '',
        pic: httpsifyMediaUrl(item.pic || ''),
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
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'Leaderboard fetch failed: %{public}s', e?.message);
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
  const source = parseBoardSource(id);
  let bangId = parseBoardBangId(id);
  bangId = stripRepeatedSourcePrefix(source, bangId);
  const listKey = `${source}__${bangId}`;
  const pageKey = `${listKey}__${page}`;

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
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'Plugin list detail fetch failed, falling back to builtin: %{public}s', e?.message);
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
        pic: httpsifyMediaUrl(item.img || item.pic || ''),
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
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'Builtin list detail failed: %{public}s', e?.message);
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
    const bang = stripRepeatedSourcePrefix(source, id);
    const fullId = `${source}__${bang}`;
    return await getListDetail(fullId, page);
  } catch (e) {
    return null;
  }
}

/** 榜单详情请求超时（毫秒）：个别源偶发长时间无响应，不能让页面一直转圈 */
const LEADERBOARD_REQUEST_TIMEOUT_MS = 20000;
/** 空包重试前的等待（毫秒）：酷狗等源首包常为空，稍等再拉一次 */
const LEADERBOARD_RETRY_DELAY_MS = 450;

/**
 * 带超时与空包重试的榜单详情拉取
 *
 * 这些源（尤其酷狗）偶发返回空列表或长时间不响应，页面各自写重试策略既重复又容易漏。
 * 统一在这里处理：每次尝试都有超时，空列表则短暂等待后重试，全部失败返回 null。
 *
 * @param attempts 最多尝试次数（默认 3）
 */
export async function getLeaderboardDetailReliable(
  source: string, id: string, page: number = 1, attempts: number = 3
): Promise<ListDetailInfo | null> {
  for (let attempt = 0; attempt < attempts; attempt++) {
    const detail = await Promise.race<ListDetailInfo | null>([
      getLeaderboardDetail(source, id, page),
      new Promise<ListDetailInfo | null>((_resolve, reject) => {
        setTimeout(() => {
          reject(new Error('leaderboard detail timeout'));
        }, LEADERBOARD_REQUEST_TIMEOUT_MS);
      }),
    ]).catch((): ListDetailInfo | null => null);

    if (detail && detail.list && detail.list.length > 0) {
      return detail;
    }
    if (attempt + 1 < attempts) {
      await new Promise<void>((resolve: () => void) => {
        setTimeout((): void => {
          resolve();
        }, LEADERBOARD_RETRY_DELAY_MS);
      });
    }
  }
  return null;
}

// 获取排行榜内全部歌曲（分页获取所有歌曲）
export async function getListDetailAll(
  id: string,
  isRefresh: boolean = false
): Promise<BoardMusicItem[]> {
  const source = parseBoardSource(id);
  let bangId = parseBoardBangId(id);
  bangId = stripRepeatedSourcePrefix(source, bangId);
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
          pic: httpsifyMediaUrl(item.img || item.pic || ''),
          source: item.source as BoardSource,
        }));
        allMusicList.push(...musicItems);
        hasMore = musicItems.length >= LIST_LOAD_LIMIT;
        currentPage++;
      } else {
        hasMore = false;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Board songs pagination failed: %{public}s', e?.message);
      hasMore = false;
    }
  }

  return allMusicList;
}
