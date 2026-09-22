/**
 * QQ 音乐 - 搜索联想
 * 对应安卓源码: src/utils/musicSdk/tx/tipSearch.js（smartbox，返回 歌名 - 歌手）
 */
import hilog from '@ohos.hilog';
import { httpRequest, parseHttpBodyJson, type HttpRequestConfig, type HttpResponse } from '../../../../core/network/http';

const TAG = 'TxTipSearch';
const DOMAIN = 0x0001;

interface TxTipSong {
  name?: string;
  singer?: string;
}

interface TxTipSongList {
  itemlist?: TxTipSong[];
}

interface TxTipData {
  song?: TxTipSongList;
}

interface TxTipResponse {
  code?: number;
  data?: TxTipData;
}

export function searchTips(keyword: string): Promise<string[]> {
  const url = 'https://c.y.qq.com/splcloud/fcgi-bin/smartbox_new.fcg?is_xml=0&format=json'
    + `&key=${encodeURIComponent(keyword)}&loginUin=0&hostUin=0&inCharset=utf8`
    + '&outCharset=utf-8&notice=0&platform=yqq&needNewCode=0';
  const reqOpts: HttpRequestConfig = {
    responseType: 'text',
    readTimeout: 8000,
    headers: {
      'Referer': 'https://y.qq.com/portal/player.html',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  };

  return httpRequest(url, reqOpts).promise.then((response: HttpResponse<Object>) => {
    const data = parseHttpBodyJson<TxTipResponse>(
      response.data as string | Object | ArrayBuffer | undefined | null
    );
    const items = data?.data?.song?.itemlist;
    if (!items || items.length === 0) {
      return [];
    }
    const tips: string[] = [];
    for (const item of items) {
      const name = (item.name ?? '').trim();
      const singer = (item.singer ?? '').trim();
      if (name.length === 0) {
        continue;
      }
      tips.push(singer.length > 0 ? `${name} - ${singer}` : name);
    }
    return tips;
  }).catch((err: Error) => {
    hilog.warn(DOMAIN, TAG, 'searchTips failed: %{public}s', err?.message);
    return [];
  });
}
