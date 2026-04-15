/**
 * 网易云 — 播放地址，由 {@link NeteaseMusicSource} 调用。
 */

import type { MusicInfo } from '../../../../types/MusicTypes';
import { httpRequest, parseHttpBodyJson, httpResponseBody } from '../../../../core/network/http';
import type { MusicUrlResult } from '../MusicSdkContracts';

interface WYUrlData {
  url?: string | null;
}

interface WYUrlResponse {
  data?: WYUrlData[];
}

function wyBrCandidates(quality: string): number[] {
  if (quality === 'flac') {
    return [999000, 320000, 192000, 128000];
  }
  if (quality === '320k') {
    return [320000, 192000, 128000];
  }
  return [128000, 320000, 192000];
}

async function requestWyPlayUrlOnce(songmid: string, br: number): Promise<string | null> {
  try {
    const reqUrl =
      `https://music.163.com/api/song/enhance/player/url?id=${songmid}&ids=[${songmid}]&br=${br}`;
    const headers: Map<string, string> = new Map();
    headers.set('Referer', 'https://music.163.com/');
    headers.set(
      'User-Agent',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36'
    );
    const response = await httpRequest(reqUrl, { header: headers, responseType: 'text' }).promise;
    const body = parseHttpBodyJson<WYUrlResponse>(httpResponseBody(response));
    if (body && body.data && body.data.length > 0) {
      const u = body.data[0].url;
      if (u !== undefined && u !== null && u.length > 0) {
        return u;
      }
    }
  } catch {
    return null;
  }
  return null;
}

export async function getWyMusicUrl(songInfo: MusicInfo, quality: string): Promise<MusicUrlResult> {
  const songmid: string = songInfo.songmid || '';
  if (!songmid) {
    const result: MusicUrlResult = { url: '', type: quality };
    return result;
  }
  const candidates = wyBrCandidates(quality);
  try {
    for (let i = 0; i < candidates.length; i++) {
      const playUrl = await requestWyPlayUrlOnce(songmid, candidates[i]);
      if (playUrl) {
        const ok: MusicUrlResult = { url: playUrl, type: quality };
        return ok;
      }
    }
  } catch {
    // fall through
  }
  const empty: MusicUrlResult = { url: '', type: quality };
  return empty;
}
