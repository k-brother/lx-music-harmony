/**
 * QQ音乐 - 排行榜
 */
import { httpRequest, type HttpRequestConfig } from '../../../../core/network/http';
import { decodeName, formatPlayTime, sizeFormate } from '../../../../utils/CommonUtils';
import { formatSingerName } from './utils/crypto';
import type { MusicInfo, MusicQualityType, Quality, QualityDetail } from '../../../../types/MusicTypes';

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
  { id: 'tx__75', name: '有声榜', bangid: '75' },
  { id: 'tx__131', name: '校园音乐人排行榜', bangid: '131' }
];

// 构建空排行榜结果
function buildEmptyLeaderboardResult(): LeaderboardResult {
  const result: LeaderboardResult = {
    list: [],
    source: 'tx',
  };
  return result;
}

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

interface ToplistData {
  songInfoList?: SongInfo[];
}

interface ToplistInfo {
  data?: ToplistData;
}

interface ToplistResponse {
  code: number;
  toplist?: ToplistInfo;
}

interface PeriodInfo {
  name: string;
  bangid: string;
  period: string;
}

interface ToplistParam {
  topid: number;
  num: number;
  period: string;
}

interface CommParam {
  uin: number;
  format: string;
  ct: number;
  cv: number;
}

interface ToplistModule {
  module: string;
  method: string;
  param: ToplistParam;
}

interface RequestBody {
  toplist: ToplistModule;
  comm: CommParam;
}

// QQ音乐排行榜实现
class TXLeaderboard implements LeaderboardInterface {
  private readonly limit: number = 300;
  private readonly periodUrl: string = 'https://c.y.qq.com/node/pc/wk_v15/top.html';
  private periods: Map<string, PeriodInfo> = new Map();

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
    const bangidNum = parseInt(bangid);
    let period: string | null = null;

    try {
      // 尝试获取周期信息
      const info = this.periods.get(bangid);
      period = info ? info.period : await this.getPeriods(bangid);

      const response = await this.listDetailRequest(bangidNum, period || '', this.limit);
      const body: ToplistResponse = JSON.parse(response);

      if (body.code !== 0) {
        return this.getList(bangid, page);
      }

      const songList = body.toplist?.data?.songInfoList || [];

      const listResult: LeaderboardListResult = {
        total: songList.length,
        list: this.filterData(songList),
        limit: this.limit,
        page: 1,
        source: 'tx',
      };
      return listResult;
    } catch (error) {
      // 如果获取失败，返回空结果
      console.error('QQ音乐排行榜获取失败:', error);
      return buildEmptyLeaderboardListResult(page);
    }
  }

  /**
   * 排行榜详情请求
   */
  private async listDetailRequest(id: number, period: string, limit: number): Promise<string> {
    const toplistParam: ToplistParam = {
      topid: id,
      num: limit,
      period: period,
    };

    const commParam: CommParam = {
      uin: 0,
      format: 'json',
      ct: 20,
      cv: 1859,
    };

    const requestBody: RequestBody = {
      toplist: {
        module: 'musicToplist.ToplistInfoServer',
        method: 'GetDetail',
        param: toplistParam,
      },
      comm: commParam,
    };

    const headers: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)',
    };

    const musicuReq: HttpRequestConfig = {
      method: 'POST',
      header: headers,
      extraData: requestBody,
    };
    const response = await httpRequest('https://u.y.qq.com/cgi-bin/musicu.fcg', musicuReq).promise;

    return response.data as string;
  }

  /**
   * 获取数据
   */
  private async getData(url: string): Promise<string> {
    const requestDataObj = httpRequest(url);
    const response = await requestDataObj.promise;

    return response.data as string;
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

      // 构建图片URL
      let imgUrl: string | null = null;
      if (!item.album?.name || item.album.name === '空') {
        if (item.singer && item.singer.length > 0 && item.singer[0].mid) {
          imgUrl = `https://y.gtimg.cn/music/photo_new/T001R500x500M000${item.singer[0].mid}.jpg`;
        }
      } else if (item.album?.mid) {
        imgUrl = `https://y.gtimg.cn/music/photo_new/T002R500x500M000${item.album.mid}.jpg`;
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
   * 获取周期信息
   */
  private async getPeriods(bangid: string): Promise<string | null> {
    try {
      const html = await this.getData(this.periodUrl);
      const periodListRegExp = /<i class="play_cover__btn c_tx_link js_icon_play" data-listkey=".+?" data-listname=".+?" data-tid=".+?" data-date=".+?" .+?<\/i>/g;
      const periodRegExp = /data-listname="(.+?)" data-tid=".*?\/(.+?)" data-date="(.+?)" .+?<\/i>/;

      const result = html.match(periodListRegExp);

      if (!result) {
        throw new Error('get data failed');
      }

      for (const item of result) {
        const match = item.match(periodRegExp);
        if (!match) continue;

        const periodInfo: PeriodInfo = {
          name: match[1],
          bangid: match[2],
          period: match[3],
        };
        this.periods.set(match[2], periodInfo);
      }

      const info = this.periods.get(bangid);
      return info ? info.period : null;
    } catch (error) {
      throw new Error(`Failed to get periods: ${error}`);
    }
  }

  /**
   * 获取详情页URL
   */
  getDetailPageUrl(id: string): string {
    if (typeof id === 'string') {
      id = id.replace('tx__', '');
    }
    return `https://y.qq.com/n/ryqq/toplist/${id}`;
  }
}

// 创建排行榜实例
export const leaderboard: LeaderboardInterface = new TXLeaderboard();

export default leaderboard;
