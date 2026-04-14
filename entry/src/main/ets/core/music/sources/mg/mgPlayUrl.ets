/**
 * 咪咕 — 播放地址，由 {@link MiguMusicSource} 调用。
 */

import type { MusicInfo } from '../../../../types/MusicTypes';
import { httpRequest } from '../../../../core/network/http';
import type { MusicUrlResult } from '../MusicSdkContracts';

interface MGRateFormat {
  formatType: string;
  androidUrl: string;
}

interface MGResource {
  newRateFormats?: MGRateFormat[];
}

interface MGUrlResponse {
  resource: MGResource[];
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

export function getMgMusicUrl(songInfo: MusicInfo, quality: string): Promise<MusicUrlResult> {
  const copyrightId: string = songInfo.copyrightId || '';
  if (!copyrightId) {
    const result: MusicUrlResult = { url: '', type: quality };
    return Promise.resolve(result);
  }

  const qualityMap: Map<string, number> = new Map([
    ['flac', 3],
    ['320k', 2],
    ['128k', 1],
  ]);
  const toneFlag: number = qualityMap.get(quality) || 1;

  const url: string =
    `https://app.c.nf.migu.cn/MIGUM2.0/v1.0/content/resourceinfo.do?needSimple=01&resourceId=${copyrightId}&resourceType=2`;

  const headers: Map<string, string> = new Map();
  headers.set('Referer', 'https://m.music.migu.cn/');
  headers.set(
    'User-Agent',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1'
  );

  return httpRequest(url, { header: headers }).promise.then((response) => {
    const resultData = response.data as string | Object | ArrayBuffer;
    const body = parseMgJson<MGUrlResponse>(resultData);
    if (body) {
      if (body.resource && body.resource.length > 0) {
        const resource = body.resource[0];
        if (resource.newRateFormats && resource.newRateFormats.length > 0) {
          const rateFormat =
            resource.newRateFormats.find((item: MGRateFormat) => item.formatType === toneFlag.toString()) ||
            resource.newRateFormats[0];
          if (rateFormat && rateFormat.androidUrl) {
            const playUrl: string = rateFormat.androidUrl;
            const result: MusicUrlResult = { url: playUrl, type: quality };
            return result;
          }
        }
      }
    }
    const result: MusicUrlResult = { url: '', type: quality };
    return result;
  }).catch(() => {
    const result: MusicUrlResult = { url: '', type: quality };
    return result;
  });
}
