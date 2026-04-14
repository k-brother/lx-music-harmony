/**
 * 网易云音乐 - 热门搜索
 */
import type { MusicInfo } from '../../../../types/MusicTypes';
import { httpRequest, type HttpRequestConfig } from '../../../../core/network/http';

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

function parseWyJson<T>(raw: string | Object | ArrayBuffer): T | null {
  if (typeof raw === 'string') {
    const text = raw.trim();
    if (text.length === 0) {
      return null;
    }
    try {
      return JSON.parse(text) as T;
    } catch {
      return null;
    }
  }
  if (typeof raw === 'object' && raw !== null) {
    return raw as T;
  }
  return null;
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
      const body = parseWyJson<WYHotSearchAPIResponse>(resultData);
      if (body) {
        if (body.code === 200 && body.data && body.data.itemList) {
          const hotSearchList: HotSearchItem[] = [];

          for (let i = 0; i < body.data.itemList.length; i++) {
            const item = body.data.itemList[i];
            const hotItem: HotSearchItem = {
              index: i + 1,
              title: item.searchWord,
              source: 'wy',
              url: item.url,
              hot: item.score || 0,
            };
            hotSearchList.push(hotItem);
          }

          const result: HotSearchResult = {
            list: hotSearchList,
            source: 'wy',
          };
          return result;
        }
      }

      // 如果API调用失败，返回空结果
      return buildEmptyHotSearchResult();
    } catch (error) {
      console.error('网易云音乐热搜榜获取失败:', error);
      return buildEmptyHotSearchResult();
    }
  },
};

export default hotSearch;
