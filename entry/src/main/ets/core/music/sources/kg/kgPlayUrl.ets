/**
 * 酷狗 — 播放地址，由 {@link KugouMusicSource} 调用。
 * wwwapi play/getdata 的 key 为 Web 常量时，signature 必须用 web 规则（与 util.signatureParams 的 platform 一致），否则易 err_code 20010。
 */

import type { MusicInfo } from '../../../../types/MusicTypes';
import { httpRequest } from '../../../../core/network/http';
import { signatureParams } from './util';
import type { MusicUrlResult } from '../MusicSdkContracts';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'KgPlayUrl';
const DOMAIN = 0x0001;

const KG_WEB_KEY = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
/** 与常见 H5 请求一致的设备 mid（32 位 hex） */
const KG_DEFAULT_MID = '233207ed64cadbb7a8fcc40b4fff185a';

/** httpRequest 响应上可能挂在 data / result / rawText 的字段（ArkTS 禁止内联对象作类型） */
interface KgHttpResponseLike {
  data?: Object;
  result?: Object;
  rawText?: string;
}

function responseText(r: KgHttpResponseLike): string {
  // 优先用 rawText：responseType='json' 时 data/result 已经是解析后的对象
  const raw = r.rawText;
  if (typeof raw === 'string' && raw.length > 0) {
    return raw;
  }
  const d = r.data;
  if (typeof d === 'string') {
    return d;
  }
  const res = r.result;
  if (typeof res === 'string') {
    return res;
  }
  // 兜底：对象形态时重新序列化，避免"看起来是空 body"的误判
  if (d !== undefined && d !== null) {
    try {
      return JSON.stringify(d);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'responseText stringify failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
    }
  }
  return '';
}

function extractPlayUrl(text: string): string | null {
  if (!text || text.trim().length === 0) {
    return null;
  }
  try {
    const body = JSON.parse(text) as Record<string, Object>;
    const st = body['status'] as number | undefined;
    const data = body['data'];
    if (st === 1 && data && typeof data === 'object' && !Array.isArray(data)) {
      const playUrl = (data as Record<string, string>)['play_url'];
      if (playUrl && playUrl.length > 0) {
        return playUrl;
      }
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'extractPlayUrl failed: %{public}s', (e as Error)?.message);
    return null;
  }
  return null;
}

async function fetchPlayUrlByParamString(paramStr: string): Promise<string | null> {
  const sign = signatureParams(paramStr, 'web');
  const url = `https://wwwapi.kugou.com/yy/index.php?r=play/getdata&${paramStr}&signature=${sign}`;
  const headers: Map<string, string> = new Map([
    [
      'User-Agent',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    ],
    ['Referer', 'https://www.kugou.com/'],
  ]);
  try {
    // 自行解析文本，避免 HTTP 层对纯文本响应做无意义的 JSON.parse 告警
    const response = await httpRequest(url, { header: headers, responseType: 'text' }).promise;
    const text = responseText(response as KgHttpResponseLike);
    const play = extractPlayUrl(text);
    if (!play) {
      hilog.info(0x0001, 'KG_URL', 'no play_url, body head: %{public}s', text.length > 200 ? text.substring(0, 200) : text);
    }
    return play;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'fetchPlayUrlByParamString failed: %{public}s', (e as Error)?.message);
    return null;
  }
}

export function getKgMusicUrl(songInfo: MusicInfo, quality: string): Promise<MusicUrlResult> {
  const hashRaw = songInfo.hash || '';
  const hash = hashRaw.toUpperCase();
  if (!hash) {
    const empty: MusicUrlResult = { url: '', type: quality };
    return Promise.resolve(empty);
  }

  const albumId = (songInfo.albumId && songInfo.albumId.length > 0) ? songInfo.albumId : '0';
  const songmid = songInfo.songmid ? String(songInfo.songmid) : '';

  const attempts: string[] = [
    `album_id=${albumId}&hash=${hash}&key=${KG_WEB_KEY}&mid=1&module=kg&appid=1005&pid=2&cmd=25&behavior=play&version=8575&area_code=1`,
    `album_id=0&hash=${hash}&key=${KG_WEB_KEY}&mid=1&module=kg&appid=1005&pid=2&cmd=25&behavior=play&version=8575&area_code=1`,
    `hash=${hash}&album_id=0&appid=1014&mid=${KG_DEFAULT_MID}&platid=4&dfid=-&key=${KG_WEB_KEY}&version=8990&behavior=play&area_code=1`,
  ];

  if (songmid.length > 0) {
    attempts.push(
      `encode_album_audio_id=${encodeURIComponent(songmid)}&hash=${hash}&appid=1014&mid=${KG_DEFAULT_MID}&platid=4&dfid=-&key=${KG_WEB_KEY}&version=8990&behavior=play&area_code=1`,
    );
  }

  return (async (): Promise<MusicUrlResult> => {
    for (let i = 0; i < attempts.length; i++) {
      const u = await fetchPlayUrlByParamString(attempts[i]);
      if (u && u.length > 0) {
        hilog.info(0x0001, 'KG_URL', 'play_url ok (attempt %{public}d)', i + 1);
        const ok: MusicUrlResult = { url: u, type: quality };
        return ok;
      }
    }
    hilog.warn(0x0001, 'KG_URL', 'all getdata attempts failed for hash=%{public}s', hash);
    const fail: MusicUrlResult = { url: '', type: quality };
    return fail;
  })();
}
