/**
 * 咪咕音乐 - 排行榜（对齐 src/utils/musicSdk/mg/leaderboard.js）
 * 榜单列表走静态表；详情走 app.c.nf.migu.cn MIGUM2.0 querycontentbyId（旧 m.music remoting 已返回 HTML，不可用）
 */
import type { MusicInfo, Quality, QualityDetail, MusicQualityType } from '../../../../types/MusicTypes';
import { httpRequest, parseHttpBodyJson, type HttpRequestConfig } from '../../../../core/network/http';
import { formatPlayTime, sizeFormate } from '../../../../utils/CommonUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';
// 榜单条目/结果/分页结果形状各音源一致，统一在 MusicSdkContracts 声明
import type {
  LeaderboardItem,
  LeaderboardResult,
  LeaderboardListResult,
} from '../MusicSdkContracts';

export type { LeaderboardItem, LeaderboardResult, LeaderboardListResult } from '../MusicSdkContracts';


// 排行榜接口
export interface LeaderboardInterface {
  getBoards: () => Promise<LeaderboardResult>;
  getList: (bangid: string, page: number) => Promise<LeaderboardListResult>;
}

const SUCCESS_CODE = '000000';
const LIST_LIMIT = 200;

/** 与安卓 leaderboard.js boardList 一致 */
const MG_STATIC_BOARDS: LeaderboardItem[] = [
  { id: 'mg__27553319', name: '新歌榜', bangid: '27553319' },
  { id: 'mg__27186466', name: '热歌榜', bangid: '27186466' },
  { id: 'mg__27553408', name: '原创榜', bangid: '27553408' },
  { id: 'mg__75959118', name: '音乐风向榜', bangid: '75959118' },
  { id: 'mg__76557036', name: '彩铃分贝榜', bangid: '76557036' },
  { id: 'mg__76557745', name: '会员臻爱榜', bangid: '76557745' },
  { id: 'mg__23189800', name: '港台榜', bangid: '23189800' },
  { id: 'mg__23189399', name: '内地榜', bangid: '23189399' },
  /** 原「欧美榜」columnId 19190036：querycontentbyId 长期 302001（columnInfo 空），已从静态表移除 */
  { id: 'mg__83176390', name: '国风金曲榜', bangid: '83176390' },
];

function buildEmptyLeaderboardListResult(page: number): LeaderboardListResult {
  return { list: [], total: 0, page, limit: LIST_LIMIT, source: 'mg' };
}

interface MgRateFmt {
  formatType?: string;
  size?: number;
  androidSize?: number;
}

interface MgRankArtist {
  name?: string;
}

interface MgAlbumImgEntry {
  img?: string;
}

interface MgRankSongInfo {
  songId?: string;
  songName?: string;
  singer?: string;
  artists?: MgRankArtist[];
  album?: string;
  albumId?: string;
  copyrightId?: string;
  length?: string;
  albumImgs?: MgAlbumImgEntry[];
  newRateFormats?: MgRateFmt[];
  lrcUrl?: string;
  mrcUrl?: string;
  trcUrl?: string;
}

interface MgColumnContent {
  objectInfo?: MgRankSongInfo;
}

interface MgColumnInfo {
  contents?: MgColumnContent[];
}

interface MgQueryColumnBody {
  code?: string;
  info?: string;
  columnInfo?: MgColumnInfo;
}

function formatRankSingers(info: MgRankSongInfo): string {
  const ar = info.artists;
  if (ar && ar.length > 0) {
    const parts: string[] = [];
    for (let i = 0; i < ar.length; i++) {
      const n = ar[i].name;
      if (n) {
        parts.push(n);
      }
    }
    if (parts.length > 0) {
      return parts.join('、');
    }
  }
  return info.singer || '';
}

/** 对齐 mg/musicInfo.js filterMusicInfoList（榜单 objectInfo 字段） */
function filterRankObjectInfoList(rawList: MgRankSongInfo[]): MusicInfo[] {
  const ids = new Set<string>();
  const list: MusicInfo[] = [];
  for (let i = 0; i < rawList.length; i++) {
    const item = rawList[i];
    const sid = item.songId;
    if (!sid || ids.has(sid)) {
      continue;
    }
    ids.add(sid);
    const types: MusicQualityType[] = [];
    const _types = new Map<Quality, QualityDetail>();
    const fmts = item.newRateFormats ?? [];
    for (let f = 0; f < fmts.length; f++) {
      const type = fmts[f];
      const ft = type.formatType;
      let size: string | null = null;
      switch (ft) {
        case 'PQ':
          size = sizeFormate(type.size ?? type.androidSize ?? 0);
          const q128: MusicQualityType = { type: '128k', size };
          types.push(q128);
          const d128: QualityDetail = { size };
          _types.set('128k', d128);
          break;
        case 'HQ':
          size = sizeFormate(type.size ?? type.androidSize ?? 0);
          const q320: MusicQualityType = { type: '320k', size };
          types.push(q320);
          const d320: QualityDetail = { size };
          _types.set('320k', d320);
          break;
        case 'SQ':
          size = sizeFormate(type.size ?? type.androidSize ?? 0);
          const qfl: MusicQualityType = { type: 'flac', size };
          types.push(qfl);
          const dfl: QualityDetail = { size };
          _types.set('flac', dfl);
          break;
        case 'ZQ':
          size = sizeFormate(type.size ?? type.androidSize ?? 0);
          const qhi: MusicQualityType = { type: 'flac24bit', size };
          types.push(qhi);
          const dhi: QualityDetail = { size };
          _types.set('flac24bit', dhi);
          break;
        default:
          break;
      }
    }
    const lenStr = item.length || '';
    const secFromLen = parseLengthToSeconds(lenStr);
    const tailM = /(\d\d:\d\d)$/.exec(lenStr);
    const intervalOut: string | null =
      secFromLen > 0 ? formatPlayTime(secFromLen) : tailM ? tailM[1] : null;

    let img: string | null = null;
    const imgs = item.albumImgs;
    if (imgs && imgs.length > 0 && imgs[0].img) {
      img = imgs[0].img.replace(/^http:/, 'https:');
    }

    const typeUrlMap: Map<string, string> = new Map();
    const mi: MusicInfo = {
      id: sid,
      name: item.songName ?? '',
      singer: formatRankSingers(item),
      albumName: item.album,
      albumId: item.albumId,
      songmid: sid,
      copyrightId: item.copyrightId || '',
      source: 'mg',
      interval: intervalOut,
      img,
      lrc: null,
      otherSource: null,
      types,
      _types,
      typeUrl: typeUrlMap,
    };
    list.push(mi);
  }
  return list;
}

/** 部分 objectInfo 无 albumImgs：用本榜第一条有图的封面填其余，便于卡片与预览展示 */
function applyMgChartCoverFallback(list: MusicInfo[]): void {
  if (list.length === 0) {
    return;
  }
  let fb: string | null = null;
  for (let i = 0; i < list.length; i++) {
    const im = list[i].img;
    if (im !== null && im !== undefined && im.length > 0) {
      fb = im;
      break;
    }
  }
  if (fb === null || fb.length === 0) {
    return;
  }
  for (let j = 0; j < list.length; j++) {
    const cur = list[j].img;
    if (cur === null || cur === undefined || cur.length === 0) {
      list[j].img = fb;
    }
  }
}

/** "00:03:43" / "03:43" → 秒 */
function parseLengthToSeconds(length: string): number {
  const parts = length.split(':').map((p: string) => parseInt(p, 10));
  if (parts.some((n: number) => Number.isNaN(n))) {
    return 0;
  }
  if (parts.length === 3) {
    return parts[0] * 3600 + parts[1] * 60 + parts[2];
  }
  if (parts.length === 2) {
    return parts[0] * 60 + parts[1];
  }
  return 0;
}

function buildMgPcHeaders(): Map<string, string> {
  const headers: Map<string, string> = new Map();
  headers.set('Referer', 'https://app.c.nf.migu.cn/');
  headers.set('User-Agent', 'Mozilla/5.0 (Linux; Android 5.1.1; Nexus 6 Build/LYZ28E) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/59.0.3071.115 Mobile Safari/537.36');
  headers.set('channel', '0146921');
  return headers;
}

/** 拉取专栏内容；needAll=0 失败时（如 302001）可再试 needAll=1 */
async function fetchMgQueryColumn(bangid: string, needAll: number): Promise<MgQueryColumnBody | null> {
  const url =
    `https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content/querycontentbyId.do?columnId=${encodeURIComponent(bangid)}&needAll=${needAll}`;
  const headers = buildMgPcHeaders();
  const req: HttpRequestConfig = {
    method: 'GET',
    header: headers,
    responseType: 'text',
  };
  const response = await httpRequest(url, req).promise;
  const raw = (response.result !== undefined ? response.result : response.data) as string | Object;
  return parseHttpBodyJson<MgQueryColumnBody>(raw);
}

class MgLeaderboardImpl implements LeaderboardInterface {
  /**
   * 获取排行榜列表（与安卓一致：静态表，避免失效 remoting 接口）
   */
  async getBoards(): Promise<LeaderboardResult> {
    const result: LeaderboardResult = {
      list: MG_STATIC_BOARDS,
      source: 'mg',
    };
    hilog.info(0x0001, 'MGLeaderboard', 'Loaded %{public}d static boards', MG_STATIC_BOARDS.length);
    return result;
  }

  /**
   * 获取排行榜歌曲（对齐 leaderboard.js getUrl + filterMusicInfoList）
   */
  async getList(bangid: string, page: number = 1): Promise<LeaderboardListResult> {
    try {
      let root = await fetchMgQueryColumn(bangid, 0);
      if (root === null) {
        hilog.warn(0x0001, 'MGLeaderboard', 'getList empty body bangid=%{public}s', bangid);
        return buildEmptyLeaderboardListResult(page);
      }
      if (root.code !== SUCCESS_CODE) {
        const c0 = String(root.code ?? '');
        // 302001：服务端 column 无内容，needAll=1 亦同，避免多余请求
        if (c0 !== '302001') {
          hilog.warn(
            0x0001,
            'MGLeaderboard',
            'getList code=%{public}s bangid=%{public}s needAll=0, retry needAll=1',
            c0,
            bangid,
          );
          root = await fetchMgQueryColumn(bangid, 1);
          if (root === null) {
            return buildEmptyLeaderboardListResult(page);
          }
        }
      }
      if (root.code !== SUCCESS_CODE) {
        const info = root.info ? String(root.info) : '';
        hilog.warn(
          0x0001,
          'MGLeaderboard',
          'getList code=%{public}s bangid=%{public}s %{public}s',
          String(root.code ?? ''),
          bangid,
          info,
        );
        return buildEmptyLeaderboardListResult(page);
      }
      const contents = root.columnInfo?.contents ?? [];
      const rows: MgRankSongInfo[] = [];
      for (let i = 0; i < contents.length; i++) {
        const oi = contents[i].objectInfo;
        if (oi) {
          rows.push(oi);
        }
      }
      const musicList = filterRankObjectInfoList(rows);
      applyMgChartCoverFallback(musicList);
      const result: LeaderboardListResult = {
        list: musicList,
        total: musicList.length,
        page,
        limit: LIST_LIMIT,
        source: 'mg',
      };
      hilog.info(0x0001, 'MGLeaderboard', 'Loaded %{public}d tracks from board %{public}s', musicList.length, bangid);
      return result;
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      hilog.error(0x0001, 'MGLeaderboard', 'Failed to get board list: %{public}s', errMsg);
    }
    return buildEmptyLeaderboardListResult(page);
  }
}

export const leaderboard: LeaderboardInterface = new MgLeaderboardImpl();

export default leaderboard;
