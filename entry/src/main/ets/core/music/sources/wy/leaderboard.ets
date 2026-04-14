/**
 * 网易云音乐 - 排行榜
 * 基于网易云音乐真实 API 实现
 */
import type { MusicInfo, Quality, QualityDetail, MusicQualityType } from '../../../../types/MusicTypes';
import { httpRequest, type HttpRequestConfig } from '../../../../core/network/http';
import { formatPlayTime } from '../../../../utils/CommonUtils';
import { neteaseWeapi, buildWeapiFormBody, type WeapiJsonObject } from './NeteaseCrypto';
import hilog from '@ohos.hilog';

// 排行榜项
export interface LeaderboardItem {
  id: string;
  name: string;
  bangid: string;
  pic?: string;
}

// 排行榜结果
export interface LeaderboardResult {
  list: LeaderboardItem[];
  source: string;
}

// 排行榜列表结果
export interface LeaderboardListResult {
  list: MusicInfo[];
  total: number;
  page: number;
  limit: number;
  source: string;
}

// 排行榜接口
export interface LeaderboardInterface {
  getBoards: () => Promise<LeaderboardResult>;
  getList: (bangid: string, page: number) => Promise<LeaderboardListResult>;
}

// 网易云歌单项
interface WYBoardCreator {
  nickname?: string;
}

// 网易云排行榜列表项
interface WYBoardListDataItem {
  id: number;
  name: string;
  coverImgUrl?: string;
}

// 网易云排行榜列表响应
interface WYBoardListResponse {
  code: number;
  list?: WYBoardListDataItem[];
}

const WY_TOP_LIST: LeaderboardItem[] = [
  { id: 'wy__19723756', name: '飙升榜', bangid: '19723756' },
  { id: 'wy__3779629', name: '新歌榜', bangid: '3779629' },
  { id: 'wy__2884035', name: '原创榜', bangid: '2884035' },
  { id: 'wy__3778678', name: '热歌榜', bangid: '3778678' },
  { id: 'wy__991319590', name: '说唱榜', bangid: '991319590' },
  { id: 'wy__71384707', name: '古典榜', bangid: '71384707' },
  { id: 'wy__1978921795', name: '电音榜', bangid: '1978921795' },
  { id: 'wy__745956260', name: '韩语榜', bangid: '745956260' },
  { id: 'wy__10520166', name: '国电榜', bangid: '10520166' },
  { id: 'wy__60198', name: '美国Billboard榜', bangid: '60198' },
];

// 网易云榜单详情响应
interface WYBoardDetailPlaylist {
  id: number;
  name: string;
  coverImgUrl?: string;
  description?: string;
  playCount?: number;
  trackCount?: number;
  creator?: WYBoardCreator;
  tracks?: WYTrackItem[];
}

// 网易云歌曲信息
interface WYTrackItem {
  id: number;
  name: string;
  dt: number;
  al?: WYBoardAlbum;
  ar?: WYBoardArtist[];
}

// 网易云专辑信息
interface WYBoardAlbum {
  id: number;
  name: string;
  picUrl: string;
}

// 网易云艺术家信息
interface WYBoardArtist {
  name: string;
}

// 网易云排行榜详情响应
interface WYBoardDetailResponse {
  code: number;
  playlist?: WYBoardDetailPlaylist;
}

// 构建空排行榜列表结果
function buildEmptyLeaderboardListResult(page: number): LeaderboardListResult {
  const result: LeaderboardListResult = {
    list: [],
    total: 0,
    page,
    limit: 30,
    source: 'wy',
  };
  return result;
}

// 解析歌曲信息
function parseTrackItem(item: WYTrackItem): MusicInfo {
  const types: MusicQualityType[] = [];
  const _types: Map<Quality, QualityDetail> = new Map();

  const sid = item.id?.toString() || '';
  const musicInfo: MusicInfo = {
    id: sid,
    name: item.name || '',
    singer: item.ar ? item.ar.map(a => a.name).join('、') : '',
    source: 'wy',
    songmid: sid,
    albumId: item.al?.id?.toString() || '',
    interval: formatPlayTime((item.dt || 0) / 1000),
    albumName: item.al?.name || '',
    img: item.al?.picUrl || null,
    lrc: null,
    types,
    _types,
    typeUrl: new Map(),
    otherSource: null,
  };
  return musicInfo;
}

function parseWyLeaderboardJson<T>(raw: string | Object | undefined): T | null {
  if (raw === null || raw === undefined) {
    return null;
  }
  if (typeof raw === 'string') {
    const t = raw.trim();
    if (t.length === 0) {
      return null;
    }
    return JSON.parse(t) as T;
  }
  return raw as T;
}

function buildWyLeaderboardHeaders(): Map<string, string> {
  const headers: Map<string, string> = new Map();
  headers.set('Referer', 'https://music.163.com/');
  headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');
  return headers;
}

class WyLeaderboardImpl implements LeaderboardInterface {
  /**
   * 获取排行榜列表
   */
  async getBoards(): Promise<LeaderboardResult> {
    try {
      const url = 'https://music.163.com/weapi/toplist';
      const headers: Map<string, string> = buildWyLeaderboardHeaders();
      headers.set('Content-Type', 'application/x-www-form-urlencoded');
      const boardsReq: HttpRequestConfig = {
        method: 'POST',
        header: headers,
        extraData: buildWeapiFormBody(await neteaseWeapi({})),
        responseType: 'text',
      };
      const response = await httpRequest(url, boardsReq).promise;

      const resultData: string | Object | ArrayBuffer = response.result as string | Object | ArrayBuffer;
      let body: WYBoardListResponse | null = null;
      if (typeof resultData === 'string') {
        body = parseWyLeaderboardJson<WYBoardListResponse>(resultData);
      } else if (resultData !== null && typeof resultData === 'object' && !(resultData instanceof ArrayBuffer)) {
        body = parseWyLeaderboardJson<WYBoardListResponse>(resultData as Object);
      }
      if (body !== null) {

        if (body.code === 200 && body.list) {
          const boardList: LeaderboardItem[] = body.list.map((item: WYBoardListDataItem) => {
            const cover = item.coverImgUrl || '';
            const pic = cover.length > 0 ? cover.replace(/^http:/, 'https:') : undefined;
            const boardItem: LeaderboardItem = {
              id: `wy${item.id}`,
              name: item.name || '',
              bangid: item.id.toString(),
              pic,
            };
            return boardItem;
          });

          const result: LeaderboardResult = {
            list: boardList,
            source: 'wy',
          };

          hilog.info(0x0001, 'WYLeaderboard', 'Loaded %{public}d boards', boardList.length);
          return result;
        }
      }
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      hilog.error(0x0001, 'WYLeaderboard', 'Failed to get boards: %{public}s', errMsg);
    }

    return {
      list: WY_TOP_LIST,
      source: 'wy',
    };
  }

  /**
   * 获取排行榜歌曲列表
   */
  async getList(bangid: string, page: number = 1): Promise<LeaderboardListResult> {
    try {
      const url = 'https://music.163.com/weapi/v3/playlist/detail';
      const headers: Map<string, string> = buildWyLeaderboardHeaders();
      headers.set('Content-Type', 'application/x-www-form-urlencoded');
      const payload: WeapiJsonObject = {};
      payload['id'] = bangid;
      payload['n'] = 100000;
      payload['s'] = 8;
      const listReq: HttpRequestConfig = {
        method: 'POST',
        header: headers,
        extraData: buildWeapiFormBody(await neteaseWeapi(payload)),
        responseType: 'text',
      };
      const response = await httpRequest(url, listReq).promise;

      const resultData: string | Object | ArrayBuffer = response.result as string | Object | ArrayBuffer;
      let body: WYBoardDetailResponse | null = null;
      if (typeof resultData === 'string') {
        body = parseWyLeaderboardJson<WYBoardDetailResponse>(resultData);
      } else if (resultData !== null && typeof resultData === 'object' && !(resultData instanceof ArrayBuffer)) {
        body = parseWyLeaderboardJson<WYBoardDetailResponse>(resultData as Object);
      }
      if (body !== null) {

        if (body.code === 200 && body.playlist) {
          const tracks = body.playlist.tracks || [];
          const musicList: MusicInfo[] = [];

          for (const track of tracks) {
            musicList.push(parseTrackItem(track));
          }

          const result: LeaderboardListResult = {
            list: musicList,
            total: musicList.length,
            page: 1,
            limit: musicList.length,
            source: 'wy',
          };

          hilog.info(0x0001, 'WYLeaderboard', 'Loaded %{public}d tracks from board %{public}s', musicList.length, bangid);
          return result;
        }
      }
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      hilog.error(0x0001, 'WYLeaderboard', 'Failed to get board list: %{public}s', errMsg);
    }

    return buildEmptyLeaderboardListResult(page);
  }
}

export const leaderboard: LeaderboardInterface = new WyLeaderboardImpl();

export default leaderboard;
