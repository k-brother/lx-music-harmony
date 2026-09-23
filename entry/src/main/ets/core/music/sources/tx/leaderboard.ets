/**
 * QQ音乐 - 排行榜
 * 详情走 v8 fcg_v8_toplist_cp（与周期无关）；旧版 musicu + PC 页刮周期易失效且 code!=0 时会无限递归。
 */
import { httpGet, parseHttpBodyJson, type HttpRequestConfig } from '../../../../core/network/http';
import { decodeName, formatPlayTime, sizeFormate } from '../../../../utils/CommonUtils';
import { formatSingerName } from './utils/crypto';
import type { MusicInfo, MusicQualityType, Quality, QualityDetail } from '../../../../types/MusicTypes';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'TxLeaderboard';
const DOMAIN = 0x0003;

// 排行榜项
export interface LeaderboardItem {
  id: string;
  name: string;
  bangid: string;
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

// 静态排行榜列表
const boardList: LeaderboardItem[] = [
  { id: 'tx__4', name: '流行指数榜', bangid: '4' },
  { id: 'tx__26', name: '热歌榜', bangid: '26' },
  { id: 'tx__27', name: '新歌榜', bangid: '27' },
  { id: 'tx__62', name: '飙升榜', bangid: '62' },
  { id: 'tx__58', name: '说唱榜', bangid: '58' },
  { id: 'tx__57', name: '喜力电音榜', bangid: '57' },
  { id: 'tx__28', name: '网络歌曲榜', bangid: '28' },
  { id: 'tx__5', name: '内地榜', bangid: '5' },
  { id: 'tx__3', name: '欧美榜', bangid: '3' },
  { id: 'tx__59', name: '香港地区榜', bangid: '59' },
  { id: 'tx__16', name: '韩国榜', bangid: '16' },
  { id: 'tx__60', name: '抖快榜', bangid: '60' },
  { id: 'tx__29', name: '影视金曲榜', bangid: '29' },
  { id: 'tx__17', name: '日本榜', bangid: '17' },
  { id: 'tx__52', name: '腾讯音乐人原创榜', bangid: '52' },
  { id: 'tx__36', name: 'K歌金曲榜', bangid: '36' },
  { id: 'tx__61', name: '台湾地区榜', bangid: '61' },
  { id: 'tx__63', name: 'DJ舞曲榜', bangid: '63' },
  { id: 'tx__64', name: '综艺新歌榜', bangid: '64' },
  { id: 'tx__65', name: '国风热歌榜', bangid: '65' },
  { id: 'tx__67', name: '听歌识曲榜', bangid: '67' },
  { id: 'tx__72', name: '动漫音乐榜', bangid: '72' },
  { id: 'tx__73', name: '游戏音乐榜', bangid: '73' },
  /** v8 toplist_cp 对 75 返回的 songlist 无有效 data 块（仅占位），预览与详情均无法解析，已从静态表移除 */
  { id: 'tx__131', name: '校园音乐人排行榜', bangid: '131' }
];

// 构建空排行榜列表结果
function buildEmptyLeaderboardListResult(page: number): LeaderboardListResult {
  const result: LeaderboardListResult = {
    list: [],
    total: 0,
    page,
    limit: 30,
    source: 'tx',
  };
  return result;
}

// 格式化歌手名称
function formatSinger(singers: SingerInfo[]): string {
  if (!singers || singers.length === 0) return '';
  return formatSingerName(singers, 'name');
}

interface SingerInfo {
  name: string;
  mid?: string;
}

interface AlbumInfo {
  name?: string;
  mid?: string;
}

interface FileInfo {
  /** 与 songmid 可能不同，取播放地址 vkey 必填（对齐 src/utils/musicSdk/tx/leaderboard.js） */
  media_mid?: string;
  size_128mp3?: number;
  size_320mp3?: number;
  size_flac?: number;
  size_hires?: number;
}

interface SongInfo {
  title?: string;
  singer?: SingerInfo[];
  mid?: string;
  id?: number;
  album?: AlbumInfo;
  interval?: number;
  file?: FileInfo;
}

/** v8 榜单接口单页条数（接口稳定，过大易被截断） */
const TX_TOPLIST_PAGE_SIZE = 80;

interface V8SongData {
  songname?: string;
  songmid?: string;
  strMediaMid?: string;
  songid?: number;
  singer?: SingerInfo[];
  albumname?: string;
  albummid?: string;
  interval?: number;
  size128?: number;
  size320?: number;
  sizeflac?: number;
  sizeape?: number;
  size5_1?: number;
}

interface V8SongEntry {
  data?: V8SongData;
}

interface V8ToplistCpResponse {
  code?: number;
  songlist?: V8SongEntry[];
  total_song_num?: number | string;
}

// QQ音乐排行榜实现
class TXLeaderboard implements LeaderboardInterface {

  /**
   * 获取排行榜列表
   */
  async getBoards(): Promise<LeaderboardResult> {
    // 使用静态列表，避免网络请求失败
    const result: LeaderboardResult = {
      list: boardList,
      source: 'tx',
    };
    return result;
  }

  /**
   * 获取排行榜歌曲列表
   */
  async getList(bangid: string, page: number = 1): Promise<LeaderboardListResult> {
    const bangidNum = parseInt(bangid, 10);
    if (Number.isNaN(bangidNum)) {
      return buildEmptyLeaderboardListResult(page);
    }
    const begin = (page - 1) * TX_TOPLIST_PAGE_SIZE;
    const url =
      'https://c.y.qq.com/v8/fcg-bin/fcg_v8_toplist_cp.fcg?g_tk=5381&uin=0&format=json' +
      '&inCharset=utf-8&outCharset=utf-8&notice=0&platform=h5&needNewCode=1&tpl=3&page=detail&type=top' +
      `&topid=${bangidNum}&song_begin=${begin}&song_num=${TX_TOPLIST_PAGE_SIZE}`;
    try {
      const qqHeaders: Record<string, string> = {};
      qqHeaders['User-Agent'] =
        'Mozilla/5.0 (Linux; Android 12; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Mobile Safari/537.36';
      qqHeaders['Referer'] = 'https://y.qq.com/';
      const qqReq: HttpRequestConfig = {};
      qqReq.responseType = 'text';
      qqReq.header = qqHeaders;
      const response = await httpGet(url, qqReq).promise;
      const raw = (response.result !== undefined ? response.result : response.data) as string | Object;
      const body = parseHttpBodyJson<V8ToplistCpResponse>(raw);
      if (!body || body.code !== 0 || !body.songlist) {
        return buildEmptyLeaderboardListResult(page);
      }
      const songList: SongInfo[] = [];
      for (let i = 0; i < body.songlist.length; i++) {
        const raw = body.songlist[i].data;
        // 部分榜（如有声榜历史 topid）data 为 null/字符串，仅跳过；避免把非对象当歌曲解析
        if (raw !== null && raw !== undefined && typeof raw === 'object') {
          songList.push(this.mapV8SongDataToSongInfo(raw as V8SongData));
        }
      }
      const totalRaw = body.total_song_num;
      let total: number;
      if (typeof totalRaw === 'string') {
        total = parseInt(totalRaw, 10);
      } else if (typeof totalRaw === 'number') {
        total = totalRaw;
      } else {
        total = songList.length;
      }
      if (Number.isNaN(total)) {
        total = songList.length;
      }
      const listResult: LeaderboardListResult = {
        total,
        list: this.filterData(songList),
        limit: TX_TOPLIST_PAGE_SIZE,
        page,
        source: 'tx',
      };
      return listResult;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'getLeaderboard failed: %{public}s',
        error instanceof Error ? error.message : JSON.stringify(error));
      return buildEmptyLeaderboardListResult(page);
    }
  }

  private mapV8SongDataToSongInfo(d: V8SongData): SongInfo {
    const file: FileInfo = {
      media_mid: d.strMediaMid || d.songmid || '',
      size_128mp3: d.size128,
      size_320mp3: d.size320,
      size_flac: d.sizeflac,
    };
    let albumPart: AlbumInfo | undefined = undefined;
    if (d.albumname) {
      const al: AlbumInfo = {
        name: d.albumname,
        mid: d.albummid,
      };
      albumPart = al;
    }
    const song: SongInfo = {
      title: d.songname,
      singer: d.singer,
      mid: d.songmid,
      id: d.songid,
      album: albumPart,
      interval: d.interval,
      file,
    };
    return song;
  }

  /**
   * 过滤数据
   */
  private filterData(rawList: SongInfo[]): MusicInfo[] {
    return rawList.map((item): MusicInfo => {
      const types: MusicQualityType[] = [];
      const _types: Map<Quality, QualityDetail> = new Map();

      if (item.file?.size_128mp3 && item.file.size_128mp3 !== 0) {
        const size = sizeFormate(item.file.size_128mp3);
        const qualityType: MusicQualityType = { type: '128k', size };
        types.push(qualityType);
        const qualityDetail: QualityDetail = { size };
        _types.set('128k', qualityDetail);
      }

      if (item.file?.size_320mp3 && item.file.size_320mp3 !== 0) {
        const size = sizeFormate(item.file.size_320mp3);
        const qualityType: MusicQualityType = { type: '320k', size };
        types.push(qualityType);
        const qualityDetail: QualityDetail = { size };
        _types.set('320k', qualityDetail);
      }

      if (item.file?.size_flac && item.file.size_flac !== 0) {
        const size = sizeFormate(item.file.size_flac);
        const qualityType: MusicQualityType = { type: 'flac', size };
        types.push(qualityType);
        const qualityDetail: QualityDetail = { size };
        _types.set('flac', qualityDetail);
      }

      if (item.file?.size_hires && item.file.size_hires !== 0) {
        const size = sizeFormate(item.file.size_hires);
        const qualityType: MusicQualityType = { type: 'flac24bit', size };
        types.push(qualityType);
        const qualityDetail: QualityDetail = { size };
        _types.set('flac24bit', qualityDetail);
      }

      // 构建图片 URL：优先专辑 mid；仅有专辑名无 mid 时用歌手头像兜底
      let imgUrl: string | null = null;
      if (item.album?.mid) {
        imgUrl = `https://y.gtimg.cn/music/photo_new/T002R500x500M000${item.album.mid}.jpg`;
      } else if (item.singer && item.singer.length > 0 && item.singer[0].mid) {
        imgUrl = `https://y.gtimg.cn/music/photo_new/T001R500x500M000${item.singer[0].mid}.jpg`;
      }

      const songmid = item.mid || '';
      const strMediaMid = item.file?.media_mid || songmid;
      const musicInfo: MusicInfo = {
        id: songmid,
        name: decodeName(item.title || ''),
        singer: formatSinger(item.singer || []),
        source: 'tx',
        songmid,
        strMediaMid,
        songId: item.id,
        albumMid: item.album?.mid,
        albumId: item.album?.mid || '',
        interval: formatPlayTime(item.interval || 0),
        albumName: decodeName(item.album?.name || ''),
        img: imgUrl,
        lrc: null,
        otherSource: null,
        types,
        _types,
        typeUrl: new Map(),
      };
      return musicInfo;
    });
  }

  /**
   * 获取详情页URL
   */
  getDetailPageUrl(id: string): string {
    let sid = id;
    if (typeof sid === 'string') {
      while (sid.startsWith('tx__')) {
        sid = sid.substring(4);
      }
    }
    return `https://y.qq.com/n/ryqq/toplist/${sid}`;
  }
}

// 创建排行榜实例
export const leaderboard: LeaderboardInterface = new TXLeaderboard();

export default leaderboard;
