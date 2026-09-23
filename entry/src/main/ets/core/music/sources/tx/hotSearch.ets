/**
 * QQ音乐 - 热搜
 */
import { httpRequest, parseHttpBodyJson, type HttpRequestConfig } from '../../../../core/network/http';
import { hilog } from '@kit.PerformanceAnalysisKit';
// 热搜项/结果形状五个音源一致，统一在 MusicSdkContracts 声明
import type { HotSearchItem, HotSearchResult } from '../MusicSdkContracts';

export type { HotSearchItem, HotSearchResult } from '../MusicSdkContracts';


const TAG = 'TxHotSearch';
const DOMAIN = 0x0003;

// 热搜接口
export interface HotSearchInterface {
  search: () => Promise<HotSearchResult>;
}

interface HotkeyItem {
  query: string;
  score: number;
}

interface HotkeyData {
  vec_hotkey: Array<HotkeyItem>;
}

interface HotkeyInfo {
  data: HotkeyData;
}

// QQ音乐热搜API响应接口
interface TXHotSearchAPIResponse {
  code: number;
  hotkey: HotkeyInfo;
}

// QQ音乐请求参数接口
interface TXRequestComm {
  ct: string;
  cv: string;
  guid: string;
  patch: string;
  psrf_access_token_expiresAt: number;
  psrf_qqaccess_token: string;
  psrf_qqopenid: string;
  psrf_qqunionid: string;
  tmeAppID: string;
  tmeLoginType: number;
  uin: string;
  wid: string;
}

interface TXRequestHotKeyParam {
  search_id: string;
  uin: number;
}

interface TXRequestHotKey {
  method: string;
  module: string;
  param: TXRequestHotKeyParam;
}

interface TXRequestData {
  comm: TXRequestComm;
  hotkey: TXRequestHotKey;
}

// 构建空热搜结果
function buildEmptyHotSearchResult(): HotSearchResult {
  const result: HotSearchResult = {
    list: [],
    source: 'tx',
  };
  return result;
}

/** 热搜接口的公共请求头（Referer 必带，否则 QQ 音乐侧会拒绝） */
function buildHotkeyHeaders(): Map<string, string> {
  const headers: Map<string, string> = new Map();
  headers.set('Referer', 'https://y.qq.com/portal/player.html');
  headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');
  return headers;
}

/** 热搜榜请求体（模块名/方法名写死，参数为空即可拿全量热词） */
function buildHotkeyRequestData(): TXRequestData {
  const requestData: TXRequestData = {
    comm: {
      ct: '19',
      cv: '1803',
      guid: '0',
      patch: '118',
      psrf_access_token_expiresAt: 0,
      psrf_qqaccess_token: '',
      psrf_qqopenid: '',
      psrf_qqunionid: '',
      tmeAppID: 'qqmusic',
      tmeLoginType: 0,
      uin: '0',
      wid: '0',
    },
    hotkey: {
      method: 'GetHotkeyForQQMusicPC',
      module: 'tencent_musicsoso_hotkey.HotkeyService',
      param: {
        search_id: '',
        uin: 0,
      },
    },
  };
  return requestData;
}

/** 热词列表 → 统一热搜项（index 从 1 开始，热度取接口 score） */
function toHotSearchItems(vecHotkey: HotkeyItem[]): HotSearchItem[] {
  const list: HotSearchItem[] = [];
  for (let i = 0; i < vecHotkey.length; i++) {
    const item = vecHotkey[i];
    const hotItem: HotSearchItem = {
      index: i + 1,
      title: item.query,
      source: 'tx',
      url: null,
      hot: item.score || 0,
    };
    list.push(hotItem);
  }
  return list;
}

// QQ音乐热搜榜实现
export const hotSearch: HotSearchInterface = {
  /**
   * 获取热门搜索
   */
  async search(): Promise<HotSearchResult> {
    try {
      // QQ音乐热搜榜API
      const url = 'https://u.y.qq.com/cgi-bin/musicu.fcg';

      const options: HttpRequestConfig = {
        method: 'POST',
        header: buildHotkeyHeaders(),
        extraData: JSON.stringify(buildHotkeyRequestData()),
      };

      const response = await httpRequest(url, options).promise;

      const resultData: string | Object | ArrayBuffer = response.result as string | Object | ArrayBuffer;
      const body = parseHttpBodyJson<TXHotSearchAPIResponse>(resultData);
      if (body && body.code === 0 && body.hotkey && body.hotkey.data && body.hotkey.data.vec_hotkey) {
        const result: HotSearchResult = {
          list: toHotSearchItems(body.hotkey.data.vec_hotkey),
          source: 'tx',
        };
        return result;
      }

      // 如果API调用失败，返回空结果
      return buildEmptyHotSearchResult();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'getHotSearch failed: %{public}s',
        error instanceof Error ? error.message : JSON.stringify(error));
      return buildEmptyHotSearchResult();
    }
  },
};

export default hotSearch;
