/**
 * QQ 音乐 — 播放地址，由 {@link QQMusicSource} 调用。
 * vkey 请求需带 comm；歌单页须传 strMediaMid（与 song mid 不同）。失败时依次尝试 express 接口。
 */

import hilog from '@ohos.hilog';
import type { MusicInfo } from '../../../../types/MusicTypes';
import { httpRequest, httpPost } from '../../../../core/network/http';
import type { MusicUrlResult } from '../MusicSdkContracts';

const TAG = 'TxPlayUrl';
const DOMAIN = 0x0001;

interface TXUrlData {
  sip: string[];
  midurlinfo: TXMidUrlInfo[];
}

interface TXMidUrlInfo {
  songmid: string;
  purl: string;
}

interface TXUrlReqBody {
  code?: number;
  data?: TXUrlData;
}

interface TXUrlEnvelope {
  req?: TXUrlReqBody;
}

interface PlaySingleRoot {
  code?: number;
  data?: PlaySingleSongRow[] | null;
}

interface PlaySingleSongRow {
  mid?: string;
  url?: string;
  name?: string;
}

interface ExpressRoot {
  code?: number;
  data?: ExpressDataBlock;
}

interface ExpressDataBlock {
  items?: ExpressItem[];
}

interface ExpressItem {
  songmid?: string;
  filename?: string;
  vkey?: string;
}

/** musicu vkey 请求 param */
interface TxVkeyParam {
  guid: string;
  songmid: string[];
  songtype: number[];
  uin: string;
  loginflag: number;
  platform: string;
  h5to: string;
}

interface TxVkeyReq {
  module: string;
  method: string;
  param: TxVkeyParam;
}

interface TxVkeyComm {
  ct: number;
  cv: number;
  uin: string;
  format: string;
}

interface TxVkeyWrap {
  comm: TxVkeyComm;
  req: TxVkeyReq;
}

/** get_song_detail_yqq 请求体 */
interface TxPfSongDetailComm {
  ct: string;
  cv: string;
  uin: string;
}

interface TxPfSongDetailParam {
  song_type: number;
  song_mid: string;
}

interface TxPfSongDetailReq {
  module: string;
  method: string;
  param: TxPfSongDetailParam;
}

interface TxPfSongDetailBody {
  comm: TxPfSongDetailComm;
  req: TxPfSongDetailReq;
}

const TX_HEADERS: Map<string, string> = new Map([
  ['Referer', 'https://y.qq.com/'],
  ['User-Agent',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'],
]);

const VKEY_GUID = '3586840544';

function buildVkeyGetUrl(midForVkeyArray: string, songtype: number): string {
  const vkeyParam: TxVkeyParam = {
    guid: VKEY_GUID,
    songmid: [midForVkeyArray],
    songtype: [songtype],
    uin: '0',
    loginflag: 0,
    platform: '20',
    h5to: 'openstat.html',
  };
  const vkeyReq: TxVkeyReq = {
    module: 'vkey.GetVkeyClickCodeServer',
    method: 'CgiGetVkey',
    param: vkeyParam,
  };
  const comm: TxVkeyComm = { ct: 19, cv: 1859, uin: '0', format: 'json' };
  const wrap: TxVkeyWrap = { comm, req: vkeyReq };
  return `https://u.y.qq.com/cgi-bin/musicu.fcg?data=${encodeURIComponent(JSON.stringify(wrap))}`;
}

function parseVkeyResponseJson(text: string, quality: string): MusicUrlResult | null {
  let body: TXUrlEnvelope;
  try {
    body = JSON.parse(text) as TXUrlEnvelope;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'parseVkeyResponseJson JSON.parse failed: %{public}s', (e as Error)?.message);
    return null;
  }
  const req = body.req;
  if (!req) {
    return null;
  }
  if (req.code !== undefined && req.code !== 0) {
    return null;
  }
  const d = req.data;
  if (!d || !d.sip || !d.midurlinfo || d.midurlinfo.length === 0) {
    return null;
  }
  const midurlinfo = d.midurlinfo[0];
  if (!midurlinfo || !midurlinfo.purl || midurlinfo.purl.length === 0) {
    return null;
  }
  const host = d.sip.length > 0 ? d.sip[0] : '';
  return { url: host + midurlinfo.purl, type: quality };
}

async function fetchTxStrMediaMid(songMid: string): Promise<string | null> {
  const comm: TxPfSongDetailComm = { ct: '19', cv: '1859', uin: '0' };
  const param: TxPfSongDetailParam = { song_type: 0, song_mid: songMid };
  const req: TxPfSongDetailReq = {
    module: 'music.pf_song_detail_svr',
    method: 'get_song_detail_yqq',
    param,
  };
  const bodyObj: TxPfSongDetailBody = { comm, req };
  const hdr = new Map(TX_HEADERS);
  hdr.set('Content-Type', 'application/json');
  try {
    const response = await httpPost('https://u.y.qq.com/cgi-bin/musicu.fcg', JSON.stringify(bodyObj), { header: hdr })
      .promise;
    // responseType='json' 时 data 已是对象，解析文本要用 rawText
    const raw = response.rawText;
    if (!raw || raw.length === 0) {
      hilog.warn(DOMAIN, TAG, 'fetchTxStrMediaMid empty body');
      return null;
    }
    const parsed = JSON.parse(raw) as Record<string, Object>;
    const req = parsed['req'] as Record<string, Object> | undefined;
    if (!req || (req['code'] as number) !== 0) {
      return null;
    }
    const data = req['data'] as Record<string, Object> | undefined;
    const track = data?.['track_info'] as Record<string, Object> | undefined;
    const file = track?.['file'] as Record<string, Object> | undefined;
    const mm = file?.['media_mid'] as string | undefined;
    if (mm && mm.length > 0) {
      return mm;
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'fetchTxStrMediaMid failed: %{public}s', (e as Error)?.message);
    return null;
  }
  return null;
}

function parsePlaySingleSong(text: string, quality: string): MusicUrlResult | null {
  let root: PlaySingleRoot;
  try {
    root = JSON.parse(text) as PlaySingleRoot;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'parsePlaySingleSong JSON.parse failed: %{public}s', (e as Error)?.message);
    return null;
  }
  const arr = root.data;
  if (!arr || !Array.isArray(arr) || arr.length === 0) {
    return null;
  }
  const row = arr[0];
  if (row.url && row.url.length > 0) {
    return { url: row.url, type: quality };
  }
  return null;
}

async function tryExpressMobile(trackMid: string, mediaMid: string, quality: string): Promise<MusicUrlResult> {
  const fname = quality === '320k' ? `M800${mediaMid}.mp3` : `M500${mediaMid}.mp3`;
  const q =
    `format=json&cid=205361747&uin=0&songmid=${encodeURIComponent(trackMid)}` +
    `&filename=${encodeURIComponent(fname)}&guid=${encodeURIComponent(VKEY_GUID)}` +
    `&platform=yqq&needNewCode=0`;
  const u = `https://c.y.qq.com/base/fcgi-bin/fcg_music_express_mobile3.fcg?${q}`;
  try {
    const resp = await httpRequest(u, { header: TX_HEADERS }).promise;
    const root = JSON.parse(resp.data as string) as ExpressRoot;
    const item = root.data?.items?.[0];
    if (item && item.vkey && item.filename && item.vkey.length > 0) {
      const url =
        `http://dl.stream.qqmusic.qq.com/${item.filename}?vkey=${encodeURIComponent(item.vkey)}` +
        `&guid=${VKEY_GUID}&uin=0&fromtag=66`;
      return { url, type: quality };
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'tryExpressMobile failed: %{public}s', (e as Error)?.message);
  }
  return { url: '', type: quality };
}

async function tryVkeyMatrix(
  mids: string[],
  quality: string
): Promise<MusicUrlResult | null> {
  const types = [0, 1];
  for (let mi = 0; mi < mids.length; mi++) {
    const mid = mids[mi];
    if (!mid || mid.length === 0) {
      continue;
    }
    for (let ti = 0; ti < types.length; ti++) {
      const st = types[ti];
      const u = buildVkeyGetUrl(mid, st);
      try {
        const response = await httpRequest(u, { header: TX_HEADERS }).promise;
        const hit = parseVkeyResponseJson(response.data as string, quality);
        if (hit && hit.url.length > 0) {
          return hit;
        }
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'tryVkeyMatrix request failed: %{public}s', (e as Error)?.message);
      }
    }
  }
  return null;
}

export async function getTxMusicUrl(songInfo: MusicInfo, quality: string): Promise<MusicUrlResult> {
  const songmid: string = songInfo.songmid || songInfo.id || '';
  if (!songmid) {
    return { url: '', type: quality };
  }

  let strMediaMid: string = (songInfo.strMediaMid && songInfo.strMediaMid.length > 0) ? songInfo.strMediaMid : '';
  if (!strMediaMid) {
    strMediaMid = (await fetchTxStrMediaMid(songmid)) || '';
  }
  const mediaMid = strMediaMid.length > 0 ? strMediaMid : songmid;

  const midsUnique: string[] = [];
  const pushMid = (m: string) => {
    if (m && m.length > 0 && midsUnique.indexOf(m) < 0) {
      midsUnique.push(m);
    }
  };
  pushMid(songmid);
  pushMid(mediaMid);

  const vkeyHit = await tryVkeyMatrix(midsUnique, quality);
  if (vkeyHit) {
    return vkeyHit;
  }

  try {
    const url2 =
      `https://c.y.qq.com/v8/fcg-bin/fcg_play_single_song.fcg?songmid=${encodeURIComponent(songmid)}` +
      `&songtype=1&guid=${VKEY_GUID}&platform=yqq&format=json&nickname=10000`;
    const resp = await httpRequest(url2, { header: TX_HEADERS }).promise;
    const single = parsePlaySingleSong(resp.data as string, quality);
    if (single && single.url.length > 0) {
      return single;
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'getTxMusicUrl single song request failed: %{public}s', (e as Error)?.message);
  }

  return tryExpressMobile(songmid, mediaMid, quality);
}
