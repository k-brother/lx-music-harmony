/**
 * 网易云音乐 - 歌曲搜索
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { httpRequest, parseHttpBodyJson } from '../../../../core/network/http';
import { decodeName, formatPlayTime, normalizeCoverUrl } from '../../../../utils/CommonUtils';
import { BaseMusicSource } from '../BaseMusicSource';
import type { MusicInfo, SearchResult, Quality, QualityDetail, MusicQualityType } from '../../../../types/MusicTypes';
import { neteaseWeapi, buildWeapiFormBody, type WeapiJsonObject } from './NeteaseCrypto';

const TAG = 'WYMUSIC';
const DOMAIN = 0x0001;
const LIMIT = 30;

// 网易云歌手信息
interface WYArtistInfo {
  name: string;
}

// 网易云专辑信息
interface WYAlbumInfo {
  name: string;
  picUrl: string;
  id: number;
}

// 网易云音乐项
interface WYMusicItem {
  id: number;
  name: string;
  ar: WYArtistInfo[];
  al: WYAlbumInfo;
  dt: number;
  alias: string[];
}

// 网易云搜索响应数据
interface WYSearchResultData {
  songs?: WYMusicItem[];
  songCount?: number;
}

// 网易云搜索响应
interface WYSearchResponse {
  code: number;
  result?: WYSearchResultData;
}

// 音乐搜索接口
export interface MusicSearchInterface {
  search: (keyword: string, page: number, limit: number) => Promise<SearchResult>;
  searchByLegacyApi?: (keyword: string, page: number, limit: number) => Promise<SearchResult>;
}

// 构建空搜索结果
// 使用 BaseMusicSource.buildEmptySearchResult('wy')

/**
 * 格式化时长
 */
// 使用 CommonUtils.formatPlayTime(Math.floor(dt / 1000))

/**
 * 构建歌曲信息
 */
function buildMusicInfo(rawData: WYMusicItem): MusicInfo {
  const types: MusicQualityType[] = [];
  const _types: Map<Quality, QualityDetail> = new Map();
  const typeUrl: Map<string, string> = new Map();

  const picUrl: string = normalizeCoverUrl(rawData.al.picUrl || '');

  const musicInfo: MusicInfo = {
    name: decodeName(rawData.name),
    singer: decodeName(rawData.ar.map((a: WYArtistInfo): string => a.name).join('、')),
    source: 'wy',
    songmid: rawData.id.toString(),
    albumId: rawData.al.id.toString(),
    albumName: decodeName(rawData.al.name),
    interval: formatPlayTime(Math.floor(rawData.dt / 1000)),
    img: picUrl,
    lrc: null,
    otherSource: null,
    types,
    _types,
    typeUrl,
  };
  return musicInfo;
}

/**
 * 把网易云搜索响应的歌曲列表统一转换成搜索结果
 * （新老两个接口的响应结构一致，收尾逻辑收敛到这一处）
 */
function buildSearchResultFromBody(body: WYSearchResponse, keyword: string, limit: number): SearchResult {
  if (body.code !== 200) {
    hilog.warn(DOMAIN, TAG, 'wy search 返回异常 code: %{public}d, keyword: %{public}s', body.code, keyword);
    return BaseMusicSource.buildEmptySearchResult('wy');
  }
  const rawData: WYMusicItem[] = body.result?.songs || [];
  const list: MusicInfo[] = [];
  for (const item of rawData) {
    list.push(buildMusicInfo(item));
  }
  const total: number = body.result?.songCount || 0;
  return {
    list,
    allPage: Math.ceil(total / limit),
    total,
    limit,
    source: 'wy',
  };
}

export const musicSearch: MusicSearchInterface = {
  /**
   * 搜索歌曲
   */
  async search(keyword: string, page: number = 1, limit: number = LIMIT): Promise<SearchResult> {
    try {
      const url = 'https://music.163.com/weapi/cloudsearch/get/web';
      const payload: WeapiJsonObject = {};
      payload['s'] = keyword;
      payload['type'] = 1;
      payload['limit'] = limit;
      payload['total'] = page === 1;
      payload['offset'] = limit * (page - 1);
      const form = await neteaseWeapi(payload);
      const bodyText = buildWeapiFormBody(form);
      const headers: Map<string, string> = new Map();
      headers.set('Content-Type', 'application/x-www-form-urlencoded');
      headers.set('Referer', 'https://music.163.com/');
      headers.set('Origin', 'https://music.163.com');
      headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');

      const response = await httpRequest(url, {
        method: 'POST',
        header: headers,
        extraData: bodyText,
        responseType: 'text',
      }).promise;
      const resultData: string | Object | ArrayBuffer = response.result as string | Object | ArrayBuffer;
      const body = parseHttpBodyJson<WYSearchResponse>(resultData);
      if (!body) {
        return BaseMusicSource.buildEmptySearchResult('wy');
      }
      return buildSearchResultFromBody(body, keyword, limit);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'wy search failed, falling back to legacy: %{public}s', (e as Error)?.message);
      return this.searchByLegacyApi(keyword, page, limit);
    }
  },

  async searchByLegacyApi(keyword: string, page: number, limit: number): Promise<SearchResult> {
    try {
      const url = `https://music.163.com/api/search/pc?s=${encodeURIComponent(keyword)}&offset=${(page - 1) * limit}&limit=${limit}&type=1`;
      const headers: Map<string, string> = new Map();
      headers.set('Referer', 'https://music.163.com/');
      headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');
      const response = await httpRequest(url, { header: headers, responseType: 'text' }).promise;
      const resultData: string | Object | ArrayBuffer = response.result as string | Object | ArrayBuffer;
      const body = parseHttpBodyJson<WYSearchResponse>(resultData);
      if (!body) {
        return BaseMusicSource.buildEmptySearchResult('wy');
      }
      return buildSearchResultFromBody(body, keyword, limit);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'wy searchByLegacyApi failed: %{public}s', (e as Error)?.message);
      return BaseMusicSource.buildEmptySearchResult('wy');
    }
  },
};

export default musicSearch;
