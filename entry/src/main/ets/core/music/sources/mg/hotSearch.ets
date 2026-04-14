/**
 * 咪咕音乐 - 热搜
 */
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

// 咪咕音乐热搜API响应项
interface MGHotSearchAPIItem {
  word: string;
  resourceType: string;
  hot: number;
}

// 咪咕音乐热搜API响应组
interface MGHotSearchAPIGroup {
  hotwordList: MGHotSearchAPIItem[];
}

// 咪咕音乐热搜API响应数据
interface MGHotSearchAPIData {
  hotwords: MGHotSearchAPIGroup[];
}

// 咪咕音乐热搜API响应接口
interface MGHotSearchAPIResponse {
  code: string;
  data: MGHotSearchAPIData;
}

function parseMgJson<T>(raw: string | Object | ArrayBuffer): T | null {
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

// 构建空热搜结果
function buildEmptyHotSearchResult(): HotSearchResult {
  const result: HotSearchResult = {
    list: [],
    source: 'mg',
  };
  return result;
}

// 咪咕音乐热搜榜实现
export const hotSearch: HotSearchInterface = {
  /**
   * 获取热门搜索
   */
  async search(): Promise<HotSearchResult> {
    try {
      // 咪咕音乐热搜榜API
      const url = 'http://jadeite.migu.cn:7090/music_search/v3/search/hotword';

      const headers: Map<string, string> = new Map();
      headers.set('User-Agent', 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1');
      headers.set('Referer', 'https://m.music.migu.cn/');

      const options: HttpRequestConfig = {
        method: 'GET',
        header: headers,
      };

      const response = await httpRequest(url, options).promise;

      const resultData: string | Object | ArrayBuffer = response.result as string | Object | ArrayBuffer;
      const body = parseMgJson<MGHotSearchAPIResponse>(resultData);
      if (body) {
        if (body.code === '000000' && body.data && body.data.hotwords && body.data.hotwords.length > 0) {
          const hotwordList = body.data.hotwords[0].hotwordList;

          // 过滤出歌曲类型的热搜词
          const songHotwords = hotwordList.filter(item => item.resourceType === 'song');

          const hotSearchList: HotSearchItem[] = [];

          for (let i = 0; i < songHotwords.length; i++) {
            const item = songHotwords[i];
            const hotItem: HotSearchItem = {
              index: i + 1,
              title: item.word,
              source: 'mg',
              url: null, // 咪咕音乐热搜没有单独的URL
              hot: item.hot || 0,
            };
            hotSearchList.push(hotItem);
          }

          const result: HotSearchResult = {
            list: hotSearchList,
            source: 'mg',
          };
          return result;
        }
      }

      // 如果API调用失败，返回空结果
      return buildEmptyHotSearchResult();
    } catch (error) {
      console.error('咪咕音乐热搜榜获取失败:', error);
      return buildEmptyHotSearchResult();
    }
  },
};

export default hotSearch;
