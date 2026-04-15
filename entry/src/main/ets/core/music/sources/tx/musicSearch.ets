/**
 * QQ音乐 - 歌曲搜索
 */
import { httpRequest, parseHttpBodyJson } from '../../../../core/network/http';
import { decodeName } from '../../../../utils/CommonUtils';
import type { MusicInfo, SearchResult, Quality, QualityDetail, MusicQualityType } from '../../../../types/MusicTypes';

const LIMIT = 30;

// QQ音乐歌手信息
interface TXSingerInfo {
  name: string;
}

// QQ音乐专辑信息
interface TXAlbumInfo {
  name: string;
  mid: string;
}

// QQ音乐项
interface TXMusicItem {
  songmid: string;
  name: string;
  singer: TXSingerInfo[];
  album: TXAlbumInfo;
  interval: number;
  strMediaMid: string;
  songId: number;
}

// QQ音乐搜索响应数据
interface TXSearchSongData {
  list?: TXMusicItem[];
  total?: number;
}

interface TXSearchResponseData {
  song?: TXSearchSongData;
}
interface TXSearchResponse {
  code: number;
  data?: TXSearchResponseData;
}

// 音乐搜索接口
export interface MusicSearchInterface {
  search: (keyword: string, page: number, limit: number) => Promise<SearchResult>;
}

// 构建空搜索结果
function buildEmptySearchResult(): SearchResult {
  const result: SearchResult = {
    list: [],
    allPage: 0,
    total: 0,
    limit: 0,
    source: 'tx',
  };
  return result;
}

/**
 * 格式化时长
 */
function formatInterval(seconds: number): string {
  if (!seconds) return '';
  const m: number = Math.floor(seconds / 60);
  const s: number = seconds % 60;
  return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
}

/**
 * 构建歌曲信息
 */
function buildMusicInfo(rawData: TXMusicItem): MusicInfo {
  const types: MusicQualityType[] = [];
  const _types: Map<Quality, QualityDetail> = new Map();
  const typeUrl: Map<string, string> = new Map();

  const img: string = `https://y.gtimg.cn/music/photo_new/T002R500x500M000${rawData.album.mid}.jpg`;

  const musicInfo: MusicInfo = {
    name: decodeName(rawData.name),
    singer: decodeName(rawData.singer.map((s: TXSingerInfo): string => s.name).join('、')),
    source: 'tx',
    songmid: rawData.songmid,
    strMediaMid: rawData.strMediaMid,
    songId: rawData.songId,
    albumId: rawData.album.mid,
    albumName: decodeName(rawData.album.name),
    interval: formatInterval(rawData.interval),
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
    const url: string = 'https://u.y.qq.com/cgi-bin/musicu.fcg?data=%7B%22req%22%3A%7B%22method%22%3A%22DoSearchForQQMusicDesktop%22%2C%22module%22%3A%22music.search.SearchCgiService%22%2C%22param%22%3A%7B%22num_per_page%22%3A' + limit + '%2C%22page_num%22%3A' + page + '%2C%22query%22%3A%22' + encodeURIComponent(keyword) + '%22%2C%22search_type%22%3A0%7D%7D%7D';

    const headers: Map<string, string> = new Map();
    headers.set('Referer', 'https://y.qq.com/');
    headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');

    return httpRequest(url, { header: headers }).promise.then((response) => {
      const resultData: string | Object | ArrayBuffer = response.result as string | Object | ArrayBuffer;
      const body = parseHttpBodyJson<TXSearchResponse>(resultData);

      if (!body || body.code !== 0) {
        return buildEmptySearchResult();
      }

      const songData: TXSearchSongData | undefined = body.data?.song;
      const rawData: TXMusicItem[] = songData?.list || [];
      const list: MusicInfo[] = [];
      for (const item of rawData) {
        list.push(buildMusicInfo(item));
      }
      const total: number = songData?.total || 0;
      const allPage: number = Math.ceil(total / limit);

      const result: SearchResult = {
        list,
        allPage,
        total,
        limit,
        source: 'tx',
      };
      return result;
    }).catch(() => buildEmptySearchResult());
  },
};

export default musicSearch;
