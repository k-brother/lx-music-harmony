/**
 * 网易云音乐 - 热门搜索
 */
import { httpRequest, parseHttpBodyJson, type HttpRequestConfig } from '../../../../core/network/http';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'WyHotSearch';
const DOMAIN = 0x0003;

// 热搜项
export interface HotSearchItem {
  index: number;
  title: string;
  source: string;
  url: string | null;
  hot: number;
}

// 热搜结果
export interface HotSearchResult {
  list: HotSearchItem[];
  source: string;
}

// 热搜接口
export interface HotSearchInterface {
  search: () => Promise<HotSearchResult>;
}

// 网易云热搜API响应项
interface WYHotSearchAPIItem {
  searchWord: string;
  score: number;
  content: string;
  iconUrl: string | null;
  url: string | null;
}

// 网易云热搜API响应数据
interface WYHotSearchAPIData {
  itemList: WYHotSearchAPIItem[];
}

// 网易云热搜API响应接口
interface WYHotSearchAPIResponse {
  code: number;
  data: WYHotSearchAPIData;
}

interface WyHotDetailItem {
  first?: string;
  score?: number;
}

interface WyHotDetailResult {
  hots?: WyHotDetailItem[];
}

interface WyHotDetailResponse {
  code?: number;
  result?: WyHotDetailResult;
}

// 网易云请求参数接口
interface WYRequestItem {
  id: string;
}

interface WYRequestData {
  '/api/search/chart/detail': WYRequestItem;
}

// 构建空热搜结果
function buildEmptyHotSearchResult(): HotSearchResult {
  const result: HotSearchResult = {
    list: [],
    source: 'wy',
  };
  return result;
}

function mapToHotSearchResult(sourceList: WYHotSearchAPIItem[]): HotSearchResult {
  const hotSearchList: HotSearchItem[] = [];
  for (let i = 0; i < sourceList.length; i++) {
    const item = sourceList[i];
    const hotItem: HotSearchItem = {
      index: i + 1,
      title: item.searchWord,
      source: 'wy',
      url: item.url,
      hot: item.score || 0,
    };
    hotSearchList.push(hotItem);
  }
  return {
    list: hotSearchList,
    source: 'wy',
  };
}

function mapLegacyToHotSearchResult(sourceList: WyHotDetailItem[]): HotSearchResult {
  const hotSearchList: HotSearchItem[] = [];
  for (let i = 0; i < sourceList.length; i++) {
    const item = sourceList[i];
    const title = item.first ?? '';
    if (!title) {
      continue;
    }
    hotSearchList.push({
      index: hotSearchList.length + 1,
      title,
      source: 'wy',
      url: null,
      hot: item.score ?? 0,
    });
  }
  return {
    list: hotSearchList,
    source: 'wy',
  };
}

// 网易云音乐热搜榜实现
export const hotSearch: HotSearchInterface = {
  /**
   * 获取热门搜索
   */
  async search(): Promise<HotSearchResult> {
    try {
      // 网易云音乐热搜榜API
      const url = 'http://interface.music.163.com/eapi/batch';

      const headers: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36',
        'origin': 'https://music.163.com'
      };

      // 构建请求数据
      const requestData: WYRequestData = {
        '/api/search/chart/detail': {
          id: 'HOT_SEARCH_SONG#@#',
        }
      };

      const options: HttpRequestConfig = {
        method: 'POST',
        header: headers,
        extraData: JSON.stringify(requestData),
      };

      const response = await httpRequest(url, options).promise;

      const resultData: string | Object | ArrayBuffer = response.result as string | Object | ArrayBuffer;
      const body = parseHttpBodyJson<WYHotSearchAPIResponse>(resultData);
      if (body && body.code === 200 && body.data?.itemList && body.data.itemList.length > 0) {
        return mapToHotSearchResult(body.data.itemList);
      }

      const legacyUrl = 'https://music.163.com/api/search/hot/detail';
      const legacyHeaders: Record<string, string> = {
        'User-Agent': headers['User-Agent'],
        'Referer': 'https://music.163.com/',
      };
      const legacyOptions: HttpRequestConfig = {
        method: 'GET',
        header: legacyHeaders,
      };
      const legacyResponse = await httpRequest(legacyUrl, legacyOptions).promise;
      const legacyBody = parseHttpBodyJson<WyHotDetailResponse>(legacyResponse.result as string | Object | ArrayBuffer);
      if (legacyBody && legacyBody.code === 200 && legacyBody.result?.hots && legacyBody.result.hots.length > 0) {
        return mapLegacyToHotSearchResult(legacyBody.result.hots);
      }
      return buildEmptyHotSearchResult();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'getHotSearch failed: %{public}s',
        error instanceof Error ? error.message : JSON.stringify(error));
      return buildEmptyHotSearchResult();
    }
  },
};

export default hotSearch;
