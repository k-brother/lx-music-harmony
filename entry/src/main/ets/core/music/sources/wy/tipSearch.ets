/**
 * 网易云音乐 - 搜索联想
 * 对应安卓源码: src/utils/musicSdk/wy/tipSearch.js
 *
 * 用的是建议接口的明文形态（/api/search/suggest/web），不必走 weapi 加密：
 * 加密版与明文版返回结构一致，少一层 RSA/AES 也就少一处出错可能。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { httpRequest, parseHttpBodyJson, type HttpRequestConfig, type HttpResponse } from '../../../../core/network/http';

const TAG = 'WyTipSearch';
const DOMAIN = 0x0001;

interface WyTipArtist {
  name?: string;
}

interface WyTipSong {
  name?: string;
  artists?: WyTipArtist[];
}

interface WyTipResult {
  songs?: WyTipSong[];
}

interface WyTipResponse {
  code?: number;
  result?: WyTipResult;
}

export function searchTips(keyword: string): Promise<string[]> {
  const url = `https://music.163.com/api/search/suggest/web?s=${encodeURIComponent(keyword)}`;
  const reqOpts: HttpRequestConfig = {
    responseType: 'text',
    readTimeout: 8000,
    headers: {
      'Referer': 'https://music.163.com/',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  };

  return httpRequest(url, reqOpts).promise.then((response: HttpResponse<Object>) => {
    const data = parseHttpBodyJson<WyTipResponse>(
      response.data as string | Object | ArrayBuffer | undefined | null
    );
    const songs = data?.result?.songs;
    if (!songs || songs.length === 0) {
      return [];
    }
    const tips: string[] = [];
    for (const song of songs) {
      const name = (song.name ?? '').trim();
      if (name.length === 0) {
        continue;
      }
      const artists = song.artists ?? [];
      const names: string[] = [];
      for (const artist of artists) {
        const artistName = (artist.name ?? '').trim();
        if (artistName.length > 0) {
          names.push(artistName);
        }
      }
      tips.push(names.length > 0 ? `${name} - ${names.join('、')}` : name);
    }
    return tips;
  }).catch((err: Error) => {
    hilog.warn(DOMAIN, TAG, 'searchTips failed: %{public}s', err?.message);
    return [];
  });
}
