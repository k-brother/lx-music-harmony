/**
 * 咪咕音乐 - 歌曲搜索
 */
import { httpRequest, parseHttpBodyJson } from '../../../../core/network/http';
import { decodeName, formatPlayTime, normalizeCoverUrl } from '../../../../utils/CommonUtils';
import { BaseMusicSource } from '../BaseMusicSource';
import type { MusicInfo, SearchResult, Quality, QualityDetail, MusicQualityType } from '../../../../types/MusicTypes';

const LIMIT = 30;

// 咪咕音乐项
interface MGMusicItem {
  id: string;
  name: string;
  artists: string;
  albumName: string;
  albumId: string;
  duration: number;
  copyrightId: string;
  picUrl: string;
}

// 咪咕搜索响应数据
interface MGSearchResponseData {
  contentList?: MGMusicItem[];
  total?: number;
}

// 咪咕搜索响应
interface MGSearchResponse {
  returnCode: string;
  data?: MGSearchResponseData;
}

// 音乐搜索接口
export interface MusicSearchInterface {
  search: (keyword: string, page: number, limit: number) => Promise<SearchResult>;
}

/**
 * 构建歌曲信息
 */
function buildMusicInfo(rawData: MGMusicItem): MusicInfo {
  const types: MusicQualityType[] = [];
  const _types: Map<Quality, QualityDetail> = new Map();
  const typeUrl: Map<string, string> = new Map();

  const img: string = normalizeCoverUrl(rawData.picUrl);

  const musicInfo: MusicInfo = {
    name: decodeName(rawData.name),
    singer: decodeName(rawData.artists),
    source: 'mg',
    songmid: rawData.id,
    copyrightId: rawData.copyrightId,
    albumId: rawData.albumId,
    albumName: decodeName(rawData.albumName),
    interval: formatPlayTime(rawData.duration),
    img,
    lrc: null,
    otherSource: null,
    types,
    _types,
    typeUrl,
  };
  return musicInfo;
}

export const musicSearch: MusicSearchInterface = {
  /**
   * 搜索歌曲
   */
  search(keyword: string, page: number = 1, limit: number = LIMIT): Promise<SearchResult> {
    const url: string = `https://m.music.migu.cn/migu/remoting/scr_search_tag?keyword=${encodeURIComponent(keyword)}&type=2&pgc=${page}&rows=${limit}`;

    const headers: Map<string, string> = new Map();
    headers.set('Referer', 'https://m.music.migu.cn/');
    headers.set('User-Agent', 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1');

    return httpRequest(url, { header: headers }).promise.then((response) => {
      const resultData: string | Object | ArrayBuffer = response.result as string | Object | ArrayBuffer;
      const body = parseHttpBodyJson<MGSearchResponse>(resultData);

      if (!body || body.returnCode !== '000000') {
        return BaseMusicSource.buildEmptySearchResult('mg');
      }

      const rawData: MGMusicItem[] = body.data?.contentList || [];
      const list: MusicInfo[] = [];
      for (const item of rawData) {
        list.push(buildMusicInfo(item));
      }
      const total: number = body.data?.total || 0;
      const allPage: number = Math.ceil(total / limit);

      const result: SearchResult = {
        list,
        allPage,
        total,
        limit,
        source: 'mg',
      };
      return result;
    }).catch(() => BaseMusicSource.buildEmptySearchResult('mg'));
  },
};

export default musicSearch;
