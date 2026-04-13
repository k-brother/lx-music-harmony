/**
 * 网易云 — 播放地址，由 {@link NeteaseMusicSource} 调用。
 */

import type { MusicInfo } from '../../../../types/MusicTypes';
import { httpRequest } from '../../../../core/network/http';
import type { MusicUrlResult } from '../MusicSdkContracts';

interface WYUrlData {
  url: string;
}

interface WYUrlResponse {
  data: WYUrlData[];
}

export function getWyMusicUrl(songInfo: MusicInfo, quality: string): Promise<MusicUrlResult> {
  const songmid: string = songInfo.songmid || '';
  if (!songmid) {
    const result: MusicUrlResult = { url: '', type: quality };
    return Promise.resolve(result);
  }

  const qualityMap: Map<string, number> = new Map([
    ['flac', 999000],
    ['320k', 320000],
    ['128k', 128000],
  ]);
  const br: number = qualityMap.get(quality) || 128000;

  const url: string = `https://music.163.com/api/song/enhance/player/url?id=${songmid}&ids=[${songmid}]&br=${br}`;

  const headers: Map<string, string> = new Map();
  headers.set('Referer', 'https://music.163.com/');
  headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');

  return httpRequest(url, { header: headers }).promise.then((response) => {
    const resultData = response.data as string | ArrayBuffer;
    if (typeof resultData === 'string') {
      const body = JSON.parse(resultData) as WYUrlResponse;
      if (body.data && body.data[0] && body.data[0].url) {
        const playUrl: string = body.data[0].url;
        const result: MusicUrlResult = { url: playUrl, type: quality };
        return result;
      }
    }
    const result: MusicUrlResult = { url: '', type: quality };
    return result;
  }).catch(() => {
    const result: MusicUrlResult = { url: '', type: quality };
    return result;
  });
}
