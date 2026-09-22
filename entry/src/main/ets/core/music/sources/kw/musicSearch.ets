/**
 * 酷我音乐 - 歌曲搜索模块
 * 对应安卓源码: src/utils/musicSdk/kw/musicSearch.js
 */

import { httpGet, parseHttpBodyJson } from '../../../../core/network/http';
import type { MusicInfo, Quality, QualityDetail, SearchResult } from '../../../../types/MusicTypes';
import { formatPlayTime, decodeHtmlEntities, formatSinger } from '../../../../utils/CommonUtils';

// 搜索配置
interface SearchConfig {
  limit: number;
  url: string;
}

const SEARCH_CONFIG: SearchConfig = {
  limit: 30,
  url: 'http://search.kuwo.cn/r.s',
};
const MAX_RETRY = 2;

// 正则表达式
const REGEX_MINFO = /level:(\w+),bitrate:(\d+),format:(\w+),size:([\w.]+)/;

// 解析音质结果
interface ParseTypesResult {
  types: QualityTypeItem[];
  _types: Map<Quality, QualityDetail>;
}

// 质量类型项
interface QualityTypeItem {
  type: Quality;
  size: string | null;
}

/**
 * 解析音质信息
 */
function parseTypes(nMinfo: string): ParseTypesResult {
  const types: QualityTypeItem[] = [];
  const _types: Map<Quality, QualityDetail> = new Map();

  const infoArr = nMinfo.split(';');
  for (const info of infoArr) {
    const match = info.match(REGEX_MINFO);
    if (match) {
      switch (match[2]) {
        case '4000': {
          const typeItem: QualityTypeItem = { type: 'flac24bit', size: match[4] };
          types.push(typeItem);
          const qualityDetail: QualityDetail = { size: match[4].toUpperCase() };
          _types.set('flac24bit', qualityDetail);
          break;
        }
        case '2000': {
          const typeItem: QualityTypeItem = { type: 'flac', size: match[4] };
          types.push(typeItem);
          const qualityDetail: QualityDetail = { size: match[4].toUpperCase() };
          _types.set('flac', qualityDetail);
          break;
        }
        case '320': {
          const typeItem: QualityTypeItem = { type: '320k', size: match[4] };
          types.push(typeItem);
          const qualityDetail: QualityDetail = { size: match[4].toUpperCase() };
          _types.set('320k', qualityDetail);
          break;
        }
        case '128': {
          const typeItem: QualityTypeItem = { type: '128k', size: match[4] };
          types.push(typeItem);
          const qualityDetail: QualityDetail = { size: match[4].toUpperCase() };
          _types.set('128k', qualityDetail);
          break;
        }
      }
    }
  }
  types.reverse();
  const result: ParseTypesResult = { types, _types };
  return result;
}

/**
 * 处理搜索结果
 */
function handleResult(rawData: KwSearchItem[]): MusicInfo[] {
  const result: MusicInfo[] = [];
  if (!rawData) return result;

  for (const info of rawData) {
    const songIdRaw = info.MUSICRID || info.DC_TARGETID || '';
    if (!songIdRaw) {
      continue;
    }
    const songId = songIdRaw.replace('MUSIC_', '');

    const minfo = info.N_MINFO || info.MINFO || '';
    const parseResult: ParseTypesResult = minfo ? parseTypes(minfo) : { types: [], _types: new Map() };
    const types: QualityTypeItem[] = parseResult.types;
    const _types: Map<Quality, QualityDetail> = parseResult._types;
    const typeUrlMap: Map<string, string> = new Map();

    // 解析时长
    const duration: number = parseInt(info.DURATION || '0');
    const interval: string = Number.isNaN(duration) ? '00:00' : formatPlayTime(duration);

    // 构建酷我封面图 URL（标准格式，albumId 为 0 时使用默认封面）
    const albumId = info.ALBUMID || '0';
    const albumImg = albumId !== '0' && albumId !== ''
      ? `https://img2.kuwo.cn/star/albumcover/200/${albumId}.jpg`
      : '';

    const musicItem: MusicInfo = {
      name: decodeHtmlEntities(info.SONGNAME || info.NAME || ''),
      singer: formatSinger(decodeHtmlEntities(info.ARTIST || info.ARTISTNAME || '')),
      source: 'kw',
      songmid: songId,
      albumId: decodeHtmlEntities(info.ALBUMID || ''),
      interval: interval,
      albumName: (info.ALBUM || info.ALBUMNAME) ? decodeHtmlEntities(info.ALBUM || info.ALBUMNAME || '') : '',
      img: albumImg || null,
      lrc: null,
      types: types,
      _types: _types,
      typeUrl: typeUrlMap,
      otherSource: null,
    };
    result.push(musicItem);
  }

  return result;
}

// 酷我搜索项类型
interface KwSearchItem {
  MUSICRID: string;
  DC_TARGETID?: string;
  SONGNAME: string;
  NAME?: string;
  ARTIST: string;
  ARTISTNAME?: string;
  ALBUMID?: string;
  ALBUM?: string;
  ALBUMNAME?: string;
  DURATION?: string;
  N_MINFO?: string;
  MINFO?: string;
}

// 搜索结果类型
interface KwSearchResponse {
  TOTAL: string;
  SHOW: string;
  abslist: KwSearchItem[];
}

// 搜索模块
export interface MusicSearchInterface {
  search: (keyword: string, page?: number, limit?: number) => Promise<SearchResult>;
}

export const musicSearch: MusicSearchInterface = {
  /**
   * 执行搜索请求
   */
  search(keyword: string, page: number = 1, limit: number = SEARCH_CONFIG.limit): Promise<SearchResult> {
    const encodedKeyword = encodeURIComponent(keyword);
    const pn = page - 1;
    const url = `${SEARCH_CONFIG.url}?client=kt&all=${encodedKeyword}&pn=${pn}&rn=${limit}&uid=794762570&ver=kwplayer_ar_9.2.2.1&vipver=1&show_copyright_off=1&newver=1&ft=music&cluster=0&strategy=2012&encoding=utf8&rformat=json&vermerge=1&mobi=1&issubtitle=1`;
    const emptyResult = (): SearchResult => ({
      list: [],
      allPage: 0,
      total: 0,
      limit: limit,
      source: 'kw',
    });
    const requestOnce = (retry: number): Promise<SearchResult> => {
      const task = httpGet(url);
      return task.promise.then((response) => {
        const raw = response.result as string | Object | ArrayBuffer;
        const searchResult = parseHttpBodyJson<KwSearchResponse>(raw);
        if (!searchResult) {
          if (retry < MAX_RETRY) {
            return requestOnce(retry + 1);
          }
          return emptyResult();
        }
        if (!searchResult || (searchResult.TOTAL !== '0' && searchResult.SHOW === '0')) {
          if (retry < MAX_RETRY) {
            return requestOnce(retry + 1);
          }
          return emptyResult();
        }
        const list: MusicInfo[] = handleResult(searchResult.abslist);
        if (list.length === 0) {
          if (retry < MAX_RETRY) {
            return requestOnce(retry + 1);
          }
          return emptyResult();
        }
        const total: number = parseInt(searchResult.TOTAL || '0');
        const allPage: number = Math.ceil(total / limit);
        const searchResultObj: SearchResult = {
          list: list,
          allPage: allPage,
          total: total,
          limit: limit,
          source: 'kw',
        };
        return searchResultObj;
      }).catch(() => {
        if (retry < MAX_RETRY) {
          return requestOnce(retry + 1);
        }
        return emptyResult();
      });
    };
    return requestOnce(0);
  },

};

export default musicSearch;
