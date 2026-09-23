/**
 * 酷狗音乐 - 热门搜索
 */
import { httpRequest, type HttpRequestConfig, type HttpResponse } from '../../../../core/network/http';
import { decodeHtmlEntities } from '../../../../utils/CommonUtils';
// 热搜项/结果的形状五个音源完全一致，统一在 MusicSdkContracts 声明
import type { HotSearchItem, HotSearchResult } from '../MusicSdkContracts';

const HOT_SEARCH_URL = 'http://gateway.kugou.com/api/v3/search/hot_tab?signature=ee44edb9d7155821412d220bcaf509dd&appid=1005&clientver=10026&plat=0';
const KG_HOT_SEARCH_FALLBACK: string[] = ['周杰伦', '林俊杰', '陈奕迅', 'Taylor Swift', 'Adele', 'Coldplay'];

// 热搜头部
const HOT_SEARCH_HEADERS: Map<string, string> = new Map([
  ['dfid', '1ssiv93oVqMp27cirf2CvoF1'],
  ['mid', '156798703528610303473757548878786007104'],
  ['clienttime', '1584257267'],
  ['x-router', 'msearch.kugou.com'],
  ['user-agent', 'Android9-AndroidPhone-10020-130-0-searchrecommendprotocol-wifi'],
  ['kg-rc', '1'],
]);

// 热搜列表结果
interface HotSearchListResult {
  source: string;
  list: string[];
}

// 热搜接口
interface HotSearchInterface {
  getList: () => Promise<HotSearchListResult>;
  search: () => Promise<HotSearchResult>;
  filterList: (rawList: KGHotSearchGroup[]) => string[];
}

/**
 * 过滤列表
 */
function filterList(rawList: KGHotSearchGroup[]): string[] {
  const list: string[] = [];

  for (const item of rawList) {
    for (const k of item.keywords) {
      list.push(decodeHtmlEntities(k.keyword));
    }
  }

  return list;
}

function buildFallbackListResult(): HotSearchListResult {
  return {
    source: 'kg',
    list: KG_HOT_SEARCH_FALLBACK,
  };
}

export const hotSearch: HotSearchInterface = {
  /**
   * 获取热搜列表
   */
  getList(): Promise<HotSearchListResult> {
    const headersRecord: Record<string, string> = {};
    HOT_SEARCH_HEADERS.forEach((v: string, k: string) => {
      headersRecord[k] = v;
    });
    const cfg: HttpRequestConfig = {
      url: HOT_SEARCH_URL,
      method: 'GET',
      headers: headersRecord,
      responseType: 'json',
    };
    const task = httpRequest(HOT_SEARCH_URL, cfg);
    return task.promise.then((response: HttpResponse<Object>) => {
      const body = response.data as KGHotSearchResponse;

      if (!body || body.errcode !== 0 || !body.data?.list) {
        return buildFallbackListResult();
      }

      const result: HotSearchListResult = {
        source: 'kg',
        list: filterList(body.data.list),
      };
      return result;
    }).catch(() => {
      return buildFallbackListResult();
    });
  },

  /**
   * 获取热搜列表（适配统一接口）
   */
  search(): Promise<HotSearchResult> {
    return this.getList().then((result: HotSearchListResult): Promise<HotSearchResult> => {
      const list: HotSearchItem[] = [];
      for (let i = 0; i < result.list.length; i++) {
        const title: string = result.list[i];
        const row: HotSearchItem = {
          index: i + 1,
          title: title,
          source: 'kg',
          url: null,
          hot: 0,
        };
        list.push(row);
      }
      const out: HotSearchResult = { source: result.source, list: list };
      return Promise.resolve(out);
    });
  },

  /**
   * 过滤列表
   */
  filterList,
};

interface KGHotSearchData {
  list: KGHotSearchGroup[];
}

interface KGHotSearchResponse {
  errcode: number;
  data: KGHotSearchData;
}

interface KGHotSearchGroup {
  keywords: KGHotSearchKeyword[];
}

interface KGHotSearchKeyword {
  keyword: string;
}
