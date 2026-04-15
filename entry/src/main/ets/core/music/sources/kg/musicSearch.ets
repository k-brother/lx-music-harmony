/**
 * 酷狗音乐 - 歌曲搜索
 */
import { httpRequest, parseHttpBodyJson } from '../../../../core/network/http';
import { decodeName, formatPlayTime, sizeFormate } from '../../../../utils/CommonUtils';
import { formatSingerName } from './util';
import type { MusicInfo, SearchResult, Quality, QualityDetail } from '../../../../types/MusicTypes';

const LIMIT = 30;
const MAX_RETRY = 2;

interface KGMusicItem {
  FileSize: number;
  FileHash: string;
  HQFileSize: number;
  HQFileHash: string;
  SQFileSize: number;
  SQFileHash: string;
  ResFileSize: number;
  ResFileHash: string;
  SongName: string;
  AlbumName: string;
  AlbumID: string;
  Audioid: string;
  Duration: number;
  Singers: string[];
  Grp?: KGMusicItem[];
}

// 搜索结果数据
interface KGSearchData {
  total: number;
  lists: KGMusicItem[];
}

interface KGSearchResponse {
  error_code: number;
  data: KGSearchData;
}

// 酷狗音质类型
interface QualityType {
  type: Quality;
  size: string;
  hash: string;
}

// 音乐搜索接口
interface MusicSearchInterface {
  search: (keyword: string, page: number, limit: number) => Promise<SearchResult>;
  handleResult: (rawData: KGMusicItem[]) => MusicInfo[];
  filterData: (rawData: KGMusicItem) => MusicInfo;
}

export const musicSearch: MusicSearchInterface = {
  /**
   * 搜索歌曲
   */
  async search(keyword: string, page: number = 1, limit: number = LIMIT): Promise<SearchResult> {
    const url = `https://songsearch.kugou.com/song_search_v2?keyword=${encodeURIComponent(keyword)}&page=${page}&pagesize=${limit}&userid=0&clientver=&platform=WebFilter&filter=2&iscorrection=1&privilege_filter=0&area_code=1`;
    const emptyResult = (): SearchResult => ({
      list: [],
      allPage: 0,
      total: 0,
      limit,
      source: 'kg',
    });
    const handleFn = musicSearch.handleResult;
    const requestOnce = async (retry: number): Promise<SearchResult> => {
      try {
        const response = await httpRequest(url).promise;
        const resultData: string | Object | ArrayBuffer = response.result as string | Object | ArrayBuffer;
        const body = parseHttpBodyJson<KGSearchResponse>(resultData);
        if (!body || body.error_code !== 0 || !body.data) {
          if (retry < MAX_RETRY) {
            return requestOnce(retry + 1);
          }
          return emptyResult();
        }
        const list = handleFn(body.data.lists ?? []);
        const total = body.data.total ?? 0;
        const allPage = Math.ceil(total / limit);
        const result: SearchResult = {
          list,
          allPage,
          total,
          limit,
          source: 'kg',
        };
        return result;
      } catch {
        if (retry < MAX_RETRY) {
          return requestOnce(retry + 1);
        }
        return emptyResult();
      }
    };
    return requestOnce(0);
  },

  /**
   * 处理搜索结果
   */
  handleResult(rawData: KGMusicItem[]): MusicInfo[] {
    const ids = new Set<string>();
    const list: MusicInfo[] = [];
    const filterFn = musicSearch.filterData;

    for (const item of rawData) {
      const key = item.Audioid + item.FileHash;
      if (ids.has(key)) continue;
      ids.add(key);
      list.push(filterFn(item));

      // 处理关联歌曲
      if (item.Grp) {
        for (const childItem of item.Grp) {
          const childKey = childItem.Audioid + childItem.FileHash;
          if (ids.has(childKey)) continue;
          ids.add(childKey);
          list.push(filterFn(childItem));
        }
      }
    }

    return list;
  },

  /**
   * 过滤数据
   */
  filterData(rawData: KGMusicItem): MusicInfo {
    const types: QualityType[] = [];
    const _types = new Map<Quality, QualityDetail>();

    if (rawData.FileSize !== 0) {
      const size = sizeFormate(rawData.FileSize);
      types.push({ type: '128k', size, hash: rawData.FileHash });
      _types.set('128k', { size });
    }

    if (rawData.HQFileSize !== 0) {
      const size = sizeFormate(rawData.HQFileSize);
      types.push({ type: '320k', size, hash: rawData.HQFileHash });
      _types.set('320k', { size });
    }

    if (rawData.SQFileSize !== 0) {
      const size = sizeFormate(rawData.SQFileSize);
      types.push({ type: 'flac', size, hash: rawData.SQFileHash });
      _types.set('flac', { size });
    }

    if (rawData.ResFileSize !== 0) {
      const size = sizeFormate(rawData.ResFileSize);
      types.push({ type: 'flac24bit', size, hash: rawData.ResFileHash });
      _types.set('flac24bit', { size });
    }

    return {
      name: decodeName(rawData.SongName),
      singer: decodeName(formatSingerName(rawData.Singers, 'name')),
      source: 'kg',
      songmid: rawData.Audioid,
      hash: rawData.FileHash,
      albumId: rawData.AlbumID,
      albumName: decodeName(rawData.AlbumName),
      interval: formatPlayTime(rawData.Duration),
      img: '',
      lrc: '',
      otherSource: null,
      types,
      _types,
      typeUrl: new Map<string, string>(),
    };
  },
};

