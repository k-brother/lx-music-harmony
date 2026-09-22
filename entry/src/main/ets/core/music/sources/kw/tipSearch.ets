/**
 * 酷我 - 搜索联想
 * 对应安卓源码: src/utils/musicSdk/kw/tipSearch.js
 *
 * 注意：这里用的是酷我专门的联想服务 tips.kuwo.cn（返回 RELWORD 关键词），
 * 不是拿搜索接口的结果凑数——后者返回的是歌名，做搜索建议会显得莫名其妙。
 */
import hilog from '@ohos.hilog';
import { httpRequest, parseHttpBodyJson, type HttpRequestConfig, type HttpResponse } from '../../../../core/network/http';

const TAG = 'KwTipSearch';
const DOMAIN = 0x0001;

interface KwTipWordItem {
  RELWORD?: string;
}

interface KwTipResponse {
  STATUS?: string;
  WORDITEMS?: KwTipWordItem[];
}

export function searchTips(keyword: string): Promise<string[]> {
  const url = 'https://tips.kuwo.cn/t.s?corp=kuwo&newver=3&p2p=1&notrace=0&c=mbox'
    + `&w=${encodeURIComponent(keyword)}&encoding=utf8&rformat=json`;
  const reqOpts: HttpRequestConfig = {
    responseType: 'text',
    readTimeout: 8000,
    headers: {
      'Referer': 'http://www.kuwo.cn/',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  };

  return httpRequest(url, reqOpts).promise.then((response: HttpResponse<Object>) => {
    const data = parseHttpBodyJson<KwTipResponse>(
      response.data as string | Object | ArrayBuffer | undefined | null
    );
    const items = data?.WORDITEMS;
    if (!items || items.length === 0) {
      return [];
    }
    const tips: string[] = [];
    for (const item of items) {
      const word = (item.RELWORD ?? '').trim();
      if (word.length > 0) {
        tips.push(word);
      }
    }
    return tips;
  }).catch((err: Error) => {
    hilog.warn(DOMAIN, TAG, 'searchTips failed: %{public}s', err?.message);
    return [];
  });
}
