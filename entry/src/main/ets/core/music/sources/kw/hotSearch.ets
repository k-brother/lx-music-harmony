import { hilog } from '@kit.PerformanceAnalysisKit';
import { httpRequest, type HttpRequestConfig, type HttpResponse } from '../../../../core/network/http';
import { decodeHtmlEntities } from '../../../../utils/CommonUtils';

const TAG = 'KwHotSearch';
const DOMAIN = 0x0001;

// 热门搜索项
export interface HotSearchItem {
  index: number;
  title: string;
  source: string;
  url: string | null;
  hot: number;
}

// 酷我热门搜索 API 返回项
interface KwHotSearchItem {
  SONGNAME?: string;
  ARTIST?: string;
  DURATION?: string;
}

// 酷我热门搜索 API 返回数据
interface KwHotSearchData {
  abslist?: KwHotSearchItem[];
}

// 热搜搜索结果
interface HotSearchResult {
  list: HotSearchItem[];
  source: string;
}

// 热搜接口
export interface HotSearchInterface {
  search: () => Promise<HotSearchResult>;
  getHotSearchFromNewApi: () => Promise<HotSearchResult>;
}

/** 内置兜底热搜（三个失败分支共用，避免各写一份 4 行字面量） */
function buildDefaultHotSearchResult(): HotSearchResult {
  const result: HotSearchResult = {
    list: getDefaultHotSearch(),
    source: 'kw',
  };
  return result;
}

/**
 * 主接口拿不到热搜时的统一退路：先试备用接口，再退内置默认。
 * 原实现把这段（含 promise 链）复制了三遍。
 */
function resolveWithFallbackApi(resolve: (result: HotSearchResult) => void): void {
  hotSearch.getHotSearchFromNewApi().then((hotResult: HotSearchResult) => {
    resolve(hotResult);
  }).catch(() => {
    resolve(buildDefaultHotSearchResult());
  });
}

// 酷我热门搜索模块
export const hotSearch: HotSearchInterface = {
  /**
   * 获取热门搜索列表
   */
  search(): Promise<HotSearchResult> {
    // 使用酷我热搜API
    const url = 'http://search.kuwo.cn/r.s?client=kt&all=%E7%83%AD%E9%97%A8&pn=0&rn=20&uid=794762570&ver=kwplayer_ar_9.2.2.1&vipver=1&show_copyright_off=1&newver=1&ft=music&cluster=0&strategy=2012&encoding=utf8&rformat=json&vermerge=1&mobi=1&issubtitle=1';

    return new Promise((resolve) => {
      const legacy: HttpRequestConfig = {
        responseType: 'text',
      };
      const task = httpRequest(url, legacy);

      task.promise.then((response: HttpResponse<Object>) => {
        try {
          const responseText: string = response.data as string;
          const parsedData: Record<string, string | number | boolean | object> = JSON.parse(responseText) as Record<string, string | number | boolean | object>;
          const data: KwHotSearchData = parsedData as KwHotSearchData;
          const abslist: KwHotSearchItem[] = data.abslist || [];

          if (abslist.length > 0) {
            const items: HotSearchItem[] = abslist.map((item: KwHotSearchItem, index: number): HotSearchItem => {
              const hotSearchItem: HotSearchItem = {
                index: index + 1,
                title: decodeHtmlEntities(item.SONGNAME || item.ARTIST || ''),
                source: 'kw',
                url: null,
                hot: parseInt(item.DURATION || '0') * 1000,
              };
              return hotSearchItem;
            });

            const result: HotSearchResult = {
              list: items,
              source: 'kw',
            };
            resolve(result);
          } else {
            // 尝试备用热搜API
            resolveWithFallbackApi(resolve);
          }
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'search parse failed: %{public}s', (e as Error)?.message);
          // 尝试备用热搜API
          resolveWithFallbackApi(resolve);
        }
      }).catch(() => {
        // 尝试备用热搜API
        resolveWithFallbackApi(resolve);
      });
    });
  },

  /**
   * 从新API获取热搜
   */
  getHotSearchFromNewApi(): Promise<HotSearchResult> {
    const url = 'https://search.kuwo.cn/r.s?pn=0&rn=20&fields=nm,ns&client=android&version=9.3.3.0&prod=android&enc=UTF-8&all=%E7%83%AD%E9%97%A8&searchType=hotsong';

    return new Promise((resolve, reject) => {
      const legacy: HttpRequestConfig = {
        responseType: 'text',
      };
      const task = httpRequest(url, legacy);

      task.promise.then((response: HttpResponse<Object>) => {
        try {
          const responseText: string = response.data as string;
          const parsedData: KwHotSearchData = JSON.parse(responseText) as KwHotSearchData;
          const abslist: KwHotSearchItem[] = parsedData.abslist || [];

          if (abslist.length > 0) {
            const items: HotSearchItem[] = abslist.map((item: KwHotSearchItem, index: number): HotSearchItem => {
              return {
                index: index + 1,
                title: decodeHtmlEntities(item.SONGNAME || item.ARTIST || ''),
                source: 'kw',
                url: null,
                hot: parseInt(item.DURATION || '0') * 1000,
              };
            });

            const result: HotSearchResult = {
              list: items,
              source: 'kw',
            };
            resolve(result);
          } else {
            reject(new Error('Empty hot search result'));
          }
        } catch (e) {
          hilog.warn(DOMAIN, TAG, 'getHotSearchFromNewApi parse failed: %{public}s', (e as Error)?.message);
          reject(new Error('Parse hot search failed'));
        }
      }).catch((e: Error) => {
        hilog.warn(DOMAIN, TAG, 'getHotSearchFromNewApi request failed: %{public}s', (e as Error)?.message);
        reject(new Error('Hot search request failed'));
      });
    });
  },
};

// 获取默认热门搜索
function getDefaultHotSearch(): HotSearchItem[] {
  return [
    { index: 1, title: '周杰伦', source: 'kw', url: null, hot: 1000000 },
    { index: 2, title: '林俊杰', source: 'kw', url: null, hot: 800000 },
    { index: 3, title: '邓紫棋', source: 'kw', url: null, hot: 700000 },
    { index: 4, title: '薛之谦', source: 'kw', url: null, hot: 600000 },
    { index: 5, title: '陈奕迅', source: 'kw', url: null, hot: 500000 },
    { index: 6, title: 'Taylor Swift', source: 'kw', url: null, hot: 400000 },
    { index: 7, title: '毛不易', source: 'kw', url: null, hot: 300000 },
    { index: 8, title: '李荣浩', source: 'kw', url: null, hot: 200000 },
    { index: 9, title: '张杰', source: 'kw', url: null, hot: 100000 },
    { index: 10, title: '王力宏', source: 'kw', url: null, hot: 90000 },
  ];
}

export default hotSearch;
