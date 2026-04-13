/**
 * 酷我音乐 - 歌曲搜索模块
 * 对应安卓源码: src/utils/musicSdk/kw/musicSearch.js
 */

import { httpGet } from '../../../../core/network/http';
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
    const songId = info.MUSICRID.replace('MUSIC_', '');

    // 检查 N_MINFO 是否存在
    if (!info.N_MINFO) {
      console.warn('N_MINFO is undefined');
      continue;
    }

    const parseResult: ParseTypesResult = parseTypes(info.N_MINFO);
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
      name: decodeHtmlEntities(info.SONGNAME || ''),
      singer: formatSinger(decodeHtmlEntities(info.ARTIST || '')),
      source: 'kw',
      songmid: songId,
      albumId: decodeHtmlEntities(info.ALBUMID || ''),
      interval: interval,
      albumName: info.ALBUM ? decodeHtmlEntities(info.ALBUM) : '',
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
  SONGNAME: string;
  ARTIST: string;
  ALBUMID?: string;
  ALBUM?: string;
  DURATION?: string;
  N_MINFO?: string;
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
  tip: (keyword: string) => Promise<string[]>;
}

export const musicSearch: MusicSearchInterface = {
  /**
   * 执行搜索请求
   */
  search(keyword: string, page: number = 1, limit: number = SEARCH_CONFIG.limit): Promise<SearchResult> {
    const encodedKeyword = encodeURIComponent(keyword);
    const pn = page - 1;
    const url = `${SEARCH_CONFIG.url}?client=kt&all=${encodedKeyword}&pn=${pn}&rn=${limit}&uid=794762570&ver=kwplayer_ar_9.2.2.1&vipver=1&show_copyright_off=1&newver=1&ft=music&cluster=0&strategy=2012&encoding=utf8&rformat=json&vermerge=1&mobi=1&issubtitle=1`;

    return new Promise((resolve, reject) => {
      const task = httpGet(url);

      task.promise.then((response) => {
        try {
          const searchResult: KwSearchResponse = JSON.parse(response.data as string) as KwSearchResponse;

          // 检查结果是否有效
          if (!searchResult || (searchResult.TOTAL !== '0' && searchResult.SHOW === '0')) {
            // 重新尝试
            musicSearch.search(keyword, page, limit).then((r: SearchResult) => resolve(r)).catch((e: Error) => reject(e));
            return;
          }

          const list: MusicInfo[] = handleResult(searchResult.abslist);

          if (list.length === 0) {
            // 重新尝试
            musicSearch.search(keyword, page, limit).then((r: SearchResult) => resolve(r)).catch((e: Error) => reject(e));
            return;
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
          resolve(searchResultObj);
        } catch (err) {
          reject(new Error('解析搜索结果失败'));
        }
      }).catch(() => {
        reject(new Error('搜索请求失败'));
      });
    });
  },

  /**
   * 获取搜索建议
   */
  tip(keyword: string): Promise<string[]> {
    const url = `http://search.kuwo.cn/r.s?client=kt&all=${encodeURIComponent(keyword)}&pn=0&rn=10&uid=794762570&ver=kwplayer_ar_9.2.2.1&vipver=1&show_copyright_off=1&newver=1&ft=music&cluster=0&strategy=2012&encoding=utf8&rformat=json&vermerge=1&mobi=1&issubtitle=1`;

    return new Promise((resolve, reject) => {
      const task = httpGet(url);

      task.promise.then((response) => {
        try {
          const result: KwSearchResponse = JSON.parse(response.data as string);
          const tips = result.abslist?.map((item: KwSearchItem) => item.SONGNAME).filter(Boolean) || [];
          resolve(tips);
        } catch (err) {
          reject(new Error('解析搜索建议失败'));
        }
      }).catch(() => {
        reject(new Error('搜索建议请求失败'));
      });
    });
  },
};

export default musicSearch;
