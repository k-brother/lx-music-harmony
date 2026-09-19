/**
 * QQ音乐 - 热搜
 */
import { httpRequest, parseHttpBodyJson, type HttpRequestConfig } from '../../../../core/network/http';
import hilog from '@ohos.hilog';

const TAG = 'TxHotSearch';
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

// QQ音乐热搜榜实现
export const hotSearch: HotSearchInterface = {
  /**
   * 获取热门搜索
   */
  async search(): Promise<HotSearchResult> {
    try {
      // QQ音乐热搜榜API
      const url = 'https://u.y.qq.com/cgi-bin/musicu.fcg';

      const headers: Map<string, string> = new Map();
      headers.set('Referer', 'https://y.qq.com/portal/player.html');
      headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');

      // 构建请求数据
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

      const options: HttpRequestConfig = {
        method: 'POST',
        header: headers,
        extraData: JSON.stringify(requestData),
      };

      const response = await httpRequest(url, options).promise;

      const resultData: string | Object | ArrayBuffer = response.result as string | Object | ArrayBuffer;
      const body = parseHttpBodyJson<TXHotSearchAPIResponse>(resultData);
      if (body) {
        if (body.code === 0 && body.hotkey && body.hotkey.data && body.hotkey.data.vec_hotkey) {
          const hotSearchList: HotSearchItem[] = [];

          for (let i = 0; i < body.hotkey.data.vec_hotkey.length; i++) {
            const item = body.hotkey.data.vec_hotkey[i];
            const hotItem: HotSearchItem = {
              index: i + 1,
              title: item.query,
              source: 'tx',
              url: null,
              hot: item.score || 0,
            };
            hotSearchList.push(hotItem);
          }

          const result: HotSearchResult = {
            list: hotSearchList,
            source: 'tx',
          };
          return result;
        }
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
