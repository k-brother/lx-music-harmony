import { httpRequest, parseHttpBodyJson } from '../../../../core/network/http';
import type { MusicInfo, Quality, QualityDetail } from '../../../../types/MusicTypes';
import { formatPlayTime, decodeHtmlEntities, formatSinger, formatPlayCount } from '../../../../utils/CommonUtils';
import hilog from '@ohos.hilog';

// 排行榜项
interface BoardItem {
  id: string;
  name: string;
  bangid: string;
  pic?: string;  // 添加封面图字段
}

// 排行榜分类项（用于获取分类下的榜单列表）
interface BoardCategoryItem {
  name: string;
  id: string;
}

// 酷我排行榜分类数据
interface KwCategoryResponse {
  errcode: number;
  category: BoardCategoryItem[];
}

// 酷我榜单项
interface KwBoardItem {
  name: string;
  pic: string;
  playcnt: number;
  id: string;
  source: string;
}

// 酷我榜单列表数据
interface KwBoardListResponse {
  errcode?: number;
  list?: KwBoardItem[];
}

// 排行榜 ID 列表
const BOARD_LIST: BoardItem[] = [
  { id: 'kw__93', name: '飙升榜', bangid: '93' },
  { id: 'kw__17', name: '新歌榜', bangid: '17' },
  { id: 'kw__16', name: '热歌榜', bangid: '16' },
  { id: 'kw__158', name: '抖音热歌榜', bangid: '158' },
  { id: 'kw__292', name: '铃声榜', bangid: '292' },
  { id: 'kw__284', name: '热评榜', bangid: '284' },
  { id: 'kw__286', name: '台湾KKBOX榜', bangid: '286' },
  { id: 'kw__279', name: '冬日暖心榜', bangid: '279' },
  { id: 'kw__278', name: '古风音乐榜', bangid: '278' },
  { id: 'kw__26', name: '经典怀旧榜', bangid: '26' },
  { id: 'kw__104', name: '华语榜', bangid: '104' },
  { id: 'kw__182', name: '粤语榜', bangid: '182' },
  { id: 'kw__22', name: '欧美榜', bangid: '22' },
  { id: 'kw__184', name: '韩语榜', bangid: '184' },
  { id: 'kw__183', name: '日语榜', bangid: '183' },
  { id: 'kw__145', name: '会员畅听榜', bangid: '145' },
  { id: 'kw__153', name: '网红新歌榜', bangid: '153' },
  { id: 'kw__12', name: 'Billboard榜', bangid: '12' },
];

// 质量类型项
interface QualityTypeItem {
  type: Quality;
  size: string | null;
}

// 质量排序结果项
interface QualitySortItem {
  type: Quality;
  size: string | null;
  sortKey: number;
  index: number;
}

// 质量排序
function sortQualityArray(types: QualityTypeItem[]): QualityTypeItem[] {
  const qualityMap: Map<Quality, number> = new Map([
    ['flac24bit', 4],
    ['flac', 3],
    ['320k', 2],
    ['128k', 1],
  ]);

  const indexedTypes: QualitySortItem[] = types.map((item: QualityTypeItem, index: number): QualitySortItem => {
    const sortItem: QualitySortItem = {
      type: item.type,
      size: item.size,
      sortKey: qualityMap.get(item.type) || 0,
      index: index,
    };
    return sortItem;
  });

  indexedTypes.sort((a: QualitySortItem, b: QualitySortItem) => b.sortKey - a.sortKey);

  return indexedTypes.map((item: QualitySortItem): QualityTypeItem => {
    const result: QualityTypeItem = {
      type: item.type,
      size: item.size,
    };
    return result;
  });
}

// 解析音质结果
interface ParseTypesResult {
  types: QualityTypeItem[];
  _types: Map<Quality, QualityDetail>;
}

// 解析音质信息
function parseTypes(nMinfo: string): ParseTypesResult {
  const types: QualityTypeItem[] = [];
  const _types: Map<Quality, QualityDetail> = new Map();

  const infoArr = nMinfo.split(';');
  const qualitySet = new Set<string>();

  for (const info of infoArr) {
    const match = info.match(/level:(\w+),bitrate:(\d+),format:(\w+),size:([\w.]+)/);
    if (match) {
      const quality = match[2];
      const size = match[4].toUpperCase();

      // 避免重复添加相同音质
      if (qualitySet.has(quality)) continue;
      qualitySet.add(quality);

      switch (quality) {
        case '4000': {
          const typeItem: QualityTypeItem = { type: 'flac24bit', size: size };
          types.push(typeItem);
          const qualityDetail: QualityDetail = { size: size };
          _types.set('flac24bit', qualityDetail);
          break;
        }
        case '2000': {
          const typeItem: QualityTypeItem = { type: 'flac', size: size };
          types.push(typeItem);
          const qualityDetail: QualityDetail = { size: size };
          _types.set('flac', qualityDetail);
          break;
        }
        case '320': {
          const typeItem: QualityTypeItem = { type: '320k', size: size };
          types.push(typeItem);
          const qualityDetail: QualityDetail = { size: size };
          _types.set('320k', qualityDetail);
          break;
        }
        case '128': {
          const typeItem: QualityTypeItem = { type: '128k', size: size };
          types.push(typeItem);
          const qualityDetail: QualityDetail = { size: size };
          _types.set('128k', qualityDetail);
          break;
        }
      }
    }
  }

  const result: ParseTypesResult = { types: sortQualityArray(types), _types };
  return result;
}

// 处理歌曲结果
interface HandleSongResult {
  name: string;
  singer: string;
  source: string;
  songmid: string;
  albumId: string;
  interval: string;
  albumName: string;
  img: string | null;
  lrc: string | null;
  types: QualityTypeItem[];
  _types: Map<Quality, QualityDetail>;
  typeUrl: Map<string, string>;
  otherSource: null;
}

/** 酷我封面常为 http 或 //，鸿蒙 Image 与部分网络栈对 https 更友好 */
function normalizeKwCoverUrl(url: string | null | undefined): string | null {
  if (url === null || url === undefined) {
    return null;
  }
  const s = url.trim();
  if (s.length === 0) {
    return null;
  }
  if (s.startsWith('//')) {
    return `https:${s}`;
  }
  if (s.startsWith('http://')) {
    return `https://${s.substring(7)}`;
  }
  return s;
}

/** 从榜单 content 根节点取可用封面（单曲项常无 pic；根 pic 有时是目录 URL） */
function pickKwChartCoverFromBangData(data: KwBangApiData): string | null {
  const v9 = normalizeKwCoverUrl(data.v9_pic2);
  if (v9 !== null && v9.length > 0) {
    return v9;
  }
  const p = normalizeKwCoverUrl(data.pic);
  if (p !== null && p.length > 0 && !p.endsWith('/BangPic/') && !p.endsWith('/bangpic/')) {
    return p;
  }
  return null;
}

// 处理歌曲数据
function handleSongData(rawList: KwBangMusicItem[], chartCover: string | null): MusicInfo[] {
  return rawList.map((item: KwBangMusicItem): MusicInfo => {
    const parseResult: ParseTypesResult = parseTypes(item.n_minfo || '');
    const types: QualityTypeItem[] = parseResult.types;
    const _types: Map<Quality, QualityDetail> = parseResult._types;
    const typeUrlMap: Map<string, string> = new Map();

    const result: MusicInfo = {
      name: decodeHtmlEntities(item.name || ''),
      singer: formatSinger(decodeHtmlEntities(item.artist || '')),
      source: 'kw',
      songmid: item.id || '',
      albumId: item.albumId || '',
      interval: formatPlayTime(parseInt(item.duration || '0')),
      albumName: decodeHtmlEntities(item.album || ''),
      img: normalizeKwCoverUrl(item.pic) ?? chartCover,
      lrc: null,
      types: types,
      _types: _types,
      typeUrl: typeUrlMap,
      otherSource: null,
    };
    return result;
  });
}

// 酷我排行榜音乐项
interface KwBangMusicItem {
  id?: string;
  name?: string;
  artist?: string;
  album?: string;
  albumId?: string;
  duration?: string;
  pic?: string;
  n_minfo?: string;
}

// 排行榜API数据（data=content 成功响应通常无 errcode，仅有 name、musiclist 等）
interface KwBangApiData {
  errcode?: number;
  musiclist?: KwBangMusicItem[];
  total?: string;
  /** 榜单头图（单曲项常无 pic，用此补封面） */
  v9_pic2?: string;
  pic?: string;
}

/** 仅当 errcode 为数字且非 0 时视为失败（缺省 errcode 表示 content 接口成功形态） */
function isKwBangApiError(data: KwBangApiData): boolean {
  return typeof data.errcode === 'number' && data.errcode !== 0;
}

// 排行榜结果
interface LeaderboardResult {
  list: BoardItem[];
  source: string;
}

// 排行榜列表结果
interface LeaderboardListResult {
  list: MusicInfo[];
  total: number;
  page: number;
  limit: number;
  source: string;
}

// 排行榜模块
export interface LeaderboardInterface {
  list: BoardItem[];
  getBoards: () => Promise<LeaderboardResult>;
  getList: (bangid: string, page?: number) => Promise<LeaderboardListResult>;
  getDetailPageUrl: (bangId: string) => string;
}

// 空排行榜数据
const EMPTY_LEADERBOARD_DATA: LeaderboardListResult = {
  list: [],
  total: 0,
  page: 0,
  limit: 100,
  source: 'kw',
};

// 默认限制
const DEFAULT_LIMIT = 100;

export const leaderboard: LeaderboardInterface = {
  // 排行榜列表
  list: BOARD_LIST.slice(0, 8).map((item: BoardItem): BoardItem => {
    const boardItem: BoardItem = {
      id: `kw${item.bangid}`,
      name: item.name,
      bangid: item.bangid,
    };
    return boardItem;
  }),

  /**
   * 获取排行榜列表 - 调用真实 API
   */
  getBoards(): Promise<LeaderboardResult> {
    // 调用真实 API 获取排行榜列表
    const url = 'https://kbangserver.kuwo.cn/ksong.s?from=pc&fmt=json&pn=0&rn=100&type=bang&data=all&isbang=1';

    return new Promise((resolve) => {
      const task = httpRequest(url, {
        responseType: 'text',
      });

      task.promise.then((response) => {
        try {
          const rawBoard = (response.result !== undefined ? response.result : response.data) as string | Object;
          const data = parseHttpBodyJson<KwBoardListResponse>(rawBoard);

          if (data === null || (typeof data.errcode === 'number' && data.errcode !== 0) || !data.list) {
            // API 失败时使用预定义列表
            const boardList = leaderboard.list;
            const result: LeaderboardResult = {
              list: boardList,
              source: 'kw',
            };
            resolve(result);
            return;
          }

          // 转换数据
          const boardList: BoardItem[] = data.list.map((item: KwBoardItem): BoardItem => {
            const boardItem: BoardItem = {
              id: `kw${item.id}`,
              name: item.name || '未知榜单',
              bangid: item.id,
              pic: item.pic || '',
            };
            return boardItem;
          });

          hilog.info(0x0001, 'KWLeaderboard', 'Loaded %{public}d boards from API', boardList.length);

          const result: LeaderboardResult = {
            list: boardList,
            source: 'kw',
          };
          resolve(result);
        } catch (err) {
          hilog.error(0x0001, 'KWLeaderboard', 'Failed to parse board list: %{public}s', JSON.stringify(err));
          // 解析失败时使用预定义列表
          const boardList = leaderboard.list;
          const result: LeaderboardResult = {
            list: boardList,
            source: 'kw',
          };
          resolve(result);
        }
      }).catch((err: Error) => {
        hilog.error(0x0001, 'KWLeaderboard', 'Failed to load board list: %{public}s', JSON.stringify(err));
        // 请求失败时使用预定义列表
        const boardList = leaderboard.list;
        const result: LeaderboardResult = {
          list: boardList,
          source: 'kw',
        };
        resolve(result);
      });
    });
  },

  /**
   * 获取排行榜歌曲列表
   */
  getList(bangid: string, page: number = 1): Promise<LeaderboardListResult> {
    const limit = DEFAULT_LIMIT;
    const url = `https://kbangserver.kuwo.cn/ksong.s?from=pc&fmt=json&pn=${page - 1}&rn=${limit}&type=bang&data=content&id=${bangid}&show_copyright_off=0&pcmp4=1&isbang=1`;

    return new Promise((resolve) => {
      const task = httpRequest(url, {
        responseType: 'text',
      });

      task.promise.then((response) => {
        try {
          const raw = (response.result !== undefined ? response.result : response.data) as string | Object;
          const data = parseHttpBodyJson<KwBangApiData>(raw);

          if (data === null || isKwBangApiError(data) || !data.musiclist) {
            if (data !== null && !data.musiclist) {
              hilog.warn(0x0001, 'KWLeaderboard', 'getList no musiclist bangid=%{public}s', bangid);
            }
            const emptyResult: LeaderboardListResult = {
              list: [],
              total: 0,
              page: page,
              limit: limit,
              source: 'kw',
            };
            resolve(emptyResult);
            return;
          }

          const chartCover = pickKwChartCoverFromBangData(data);
          const list: MusicInfo[] = handleSongData(data.musiclist || [], chartCover);
          const totalNum = parseInt(data.total || '0', 10);
          const total: number = Number.isNaN(totalNum) ? list.length : (totalNum > 0 ? totalNum : list.length);

          const result: LeaderboardListResult = {
            list: list,
            total: total,
            page: page,
            limit: limit,
            source: 'kw',
          };
          resolve(result);
        } catch (err) {
          hilog.error(0x0001, 'KWLeaderboard', 'Failed to parse getList response bangid=%{public}s', bangid);
          const emptyResult: LeaderboardListResult = {
            list: [],
            total: 0,
            page: page,
            limit: limit,
            source: 'kw',
          };
          resolve(emptyResult);
        }
      }).catch(() => {
        hilog.error(0x0001, 'KWLeaderboard', 'Failed to request getList bangid=%{public}s', bangid);
        const emptyResult: LeaderboardListResult = {
          list: [],
          total: 0,
          page: page,
          limit: limit,
          source: 'kw',
        };
        resolve(emptyResult);
      });
    });
  },

  /**
   * 获取排行榜详情页 URL
   */
  getDetailPageUrl(bangid: string): string {
    return `http://www.kuwo.cn/rankList/${bangid}`;
  },
};

export default leaderboard;