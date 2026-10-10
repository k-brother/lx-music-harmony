/**
 * 酷狗听歌识曲引擎
 *
 * 移植自 RzdMusic KugouRecognizer（签名/参数/请求头均为实测可用值），适配点：
 * - 网络层统一走 core/network HttpClient（本次为它补了 ArrayBuffer extraData 透传）
 * - MD5 用本仓 CryptoUtils.md5Bytes，不再自带一份 Md5 实现
 * - 空结果返回 []；网络/服务异常抛 RecognitionNetworkError，由页面映射为可恢复的状态
 *
 * 接口契约：POST 原始 s16le mono 8kHz PCM 到酷狗指纹网关，
 * 签名 = MD5(ANDROID_KEY + 排序后的 name=value 串 + 原始二进制 body + ANDROID_KEY)。
 */
import { appLog as hilog } from '../../log/AppLogger';
import { httpClient } from '../../network/http/HttpClient';
import { md5Bytes } from '../../../utils/CryptoUtils';
import { utf8Encode } from '../../../utils/TextCodec';
import { RecognitionNetworkError } from './RecognitionTypes';
import type { RecognizedSong } from './RecognitionTypes';

const TAG = 'KugouRecognizer';
const DOMAIN: number = 0x0001;

const REQUEST_TIMEOUT_MS: number = 10000;
const ANDROID_KEY = 'OIlwieks28dk2k092lksi2UIkp';
const APP_ID: number = 1005;
const CLIENT_VERSION: number = 20489;
const MAX_CANDIDATES: number = 5;
/** 结果按 标题+歌手 去重（同一首歌多个 hash 只保留首个） */
const HASH_PATTERN: string = '^[0-9A-Fa-f]{32}$';

interface KugouAlbum {
  albumname?: string;
  album_name?: string;
  name?: string;
}

const md5Hex = (value: string): string => {
  return md5Bytes(utf8Encode(value));
};

// 采集 PCM 为 s16le mono 16000Hz，酷狗识曲要求 s16le mono 8000Hz，按点对平均降采样
const resampleTo8k = (pcm: Int16Array): Uint8Array => {
  const outSamples: number = Math.floor(pcm.length / 2);
  const out = new Uint8Array(outSamples * 2);
  const view = new DataView(out.buffer);
  for (let i = 0; i < outSamples; i++) {
    const a: number = pcm[i * 2];
    const b: number = i * 2 + 1 < pcm.length ? pcm[i * 2 + 1] : a;
    const value: number = Math.max(-32768, Math.min(32767, Math.round((a + b) / 2)));
    view.setInt16(i * 2, value, true);
  }
  return out;
};

// 酷狗正式版 Android 客户端把 MD5 设备标识解释为无符号大整数，不能用随机 hex MID
const getDeviceIdentity = (): Record<string, string> => {
  const dfid = '-';
  const mid: string = BigInt(`0x${md5Hex(dfid)}`).toString();
  const uuid: string = md5Hex(`${dfid}${mid}`);
  const device: Record<string, string> = {};
  device['dfid'] = dfid;
  device['mid'] = mid;
  device['uuid'] = uuid;
  return device;
};

// 与 KuGou.Net / KuGouMusicApi 一致的 Android 签名：MD5(key + 排序后的 name=value + 原始 body + key)
const signRequest = (params: Record<string, string>, body: Uint8Array): string => {
  const keys: string[] = Object.keys(params).sort();
  let paramsString = '';
  for (const name of keys) {
    paramsString += `${name}=${params[name]}`;
  }
  const head: Uint8Array = utf8Encode(ANDROID_KEY + paramsString);
  const tail: Uint8Array = utf8Encode(ANDROID_KEY);
  const total = new Uint8Array(head.length + body.length + tail.length);
  total.set(head, 0);
  total.set(body, head.length);
  total.set(tail, head.length + body.length);
  return md5Bytes(total);
};

const mapItem = (item: Record<string, Object>, recognizedAt: number): RecognizedSong | undefined => {
  const nameRaw: Object | undefined = item['songname'] !== undefined ? item['songname'] : item['song_name'];
  const baseName: string = nameRaw !== undefined ? nameRaw as string : '';
  if (baseName === '') {
    return undefined;
  }
  const suffixRaw: Object | undefined = item['songNameSuffix'] !== undefined
    ? item['songNameSuffix']
    : item['song_name_suffix'];
  const nameSuffix: string = suffixRaw !== undefined ? suffixRaw as string : '';
  const suffix: string = nameSuffix === '' ? '' : ` (${nameSuffix})`;

  let artist = '';
  const singerRaw: Object | undefined = item['singername'] !== undefined ? item['singername'] : item['singer_name'];
  const authorsRaw: Object | undefined = item['authors'];
  if (singerRaw !== undefined) {
    artist = singerRaw as string;
  } else if (authorsRaw !== undefined && Array.isArray(authorsRaw)) {
    const names: string[] = [];
    const authors: Array<Object> = authorsRaw as Array<Object>;
    for (const author of authors) {
      const authorRecord: Record<string, Object> = author as Record<string, Object>;
      const name: Object | undefined = authorRecord['name'] !== undefined ? authorRecord['name'] : authorRecord['author_name'];
      if (name !== undefined) {
        names.push(name as string);
      }
    }
    artist = names.join('、');
  }

  let albumRaw: Object | undefined = item['album'];
  if (Array.isArray(albumRaw)) {
    const albumList: Array<Object> = albumRaw as Array<Object>;
    albumRaw = albumList.length > 0 ? albumList[0] as Object : undefined;
  }
  let albumName = '';
  if (typeof albumRaw === 'string') {
    albumName = albumRaw as string;
  } else if (albumRaw !== undefined) {
    const album: KugouAlbum = albumRaw as KugouAlbum;
    if (album.albumname !== undefined) {
      albumName = album.albumname;
    } else if (album.album_name !== undefined) {
      albumName = album.album_name;
    } else if (album.name !== undefined) {
      albumName = album.name;
    }
  }
  if (albumName === '' && item['album_name'] !== undefined) {
    albumName = item['album_name'] as string;
  }

  let hash = '';
  const hashKeys: string[] = ['hash', 'file_hash', 'filehash', 'hash_320', 'hash_128', 'hash320', 'hash128', 'mixsongid'];
  for (const key of hashKeys) {
    const raw: Object | undefined = item[key];
    if (raw !== undefined && raw !== null) {
      const candidate: string = String(raw);
      if (candidate.length > 0 && new RegExp(HASH_PATTERN).test(candidate)) {
        hash = candidate;
        break;
      }
    }
  }
  let fallbackId = '';
  const fallbackRaw: Object | undefined = item['songid'] !== undefined ? item['songid'] : item['song_id'];
  if (fallbackRaw !== undefined && fallbackRaw !== null) {
    fallbackId = String(fallbackRaw);
  }
  const trackKey: string = hash !== '' ? hash : (fallbackId !== '' ? fallbackId : baseName);

  const coverRaw: Object | undefined = item['union_cover'];
  let coverUrl = '';
  if (typeof coverRaw === 'string') {
    coverUrl = (coverRaw as string).replace('{size}', '400');
  }

  return {
    id: `rec_kg_${trackKey}_${recognizedAt}`,
    title: `${baseName}${suffix}`,
    artist,
    album: albumName,
    coverUrl,
    source: 'kg',
    hash,
    trackId: `kg:${trackKey}`,
    recognizedAt,
  };
};

/** 16kHz Int16 PCM → 酷狗指纹接口 → 按置信度排序的候选列表（最多 5 条，已按标题+歌手去重） */
export async function recognizeKugou(pcm: Int16Array): Promise<RecognizedSong[]> {
  const body: Uint8Array = resampleTo8k(pcm);
  if (body.length === 0) {
    hilog.warn(DOMAIN, TAG, 'empty pcm after resample');
    return [];
  }
  const clienttime: number = Math.floor(Date.now() / 1000);
  const device: Record<string, string> = getDeviceIdentity();
  const params: Record<string, string> = {
    'dfid': device['dfid'],
    'mid': device['mid'],
    'uuid': device['uuid'],
    'appid': String(APP_ID),
    'clientver': String(CLIENT_VERSION),
    'clienttime': String(clienttime),
    'fpid': String(Date.now()),
    'area_code': '1',
    'include_unpublish': '1',
    'useid': '0',
    'multi_result': '1',
  };
  const signature: string = signRequest(params, body);
  // 查询串必须手拼：签名依赖排序后的原始串，HttpClient 的 params 会自行编码破坏顺序约定
  const keys: string[] = Object.keys(params).sort();
  let query = '';
  for (const name of keys) {
    if (query !== '') {
      query += '&';
    }
    query += `${name}=${params[name]}`;
  }
  query += `&signature=${signature}`;
  const url: string = `https://gateway.kugou.com/fingerprint.service/v1/music_trackid_mulit?${query}`;

  const response = await httpClient.request<string>(url, {
    method: 'POST',
    headers: {
      'content-type': 'application/octet-stream',
      'user-agent': 'KuGou/11490 (Android)',
      'dfid': '-',
      'mid': device['mid'],
      'clienttime': String(clienttime),
      'kg-rc': '1',
      'kg-thash': '5d816a0',
      'kg-rec': '1',
      'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
    },
    extraData: body.buffer as ArrayBuffer,
    responseType: 'text',
    timeout: REQUEST_TIMEOUT_MS,
    loggingEnabled: false,
  });

  if (response.status < 200 || response.status >= 300) {
    hilog.error(DOMAIN, TAG, 'kugou fingerprint http %{public}d', response.status);
    throw new RecognitionNetworkError(`fingerprint service http ${response.status}`);
  }
  const resultStr: string = response.rawText;
  let parsed: Record<string, Object>;
  try {
    parsed = JSON.parse(resultStr) as Record<string, Object>;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'fingerprint json parse failed: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    throw new RecognitionNetworkError('fingerprint bad payload');
  }
  const status: Object | undefined = parsed['status'];
  if (status === undefined || (status as number) !== 1) {
    hilog.warn(DOMAIN, TAG, 'status=%{public}s treat as no match', String(status));
    return [];
  }
  const dataRaw: Object | undefined = parsed['data'];
  if (dataRaw === undefined) {
    return [];
  }
  let items: Array<Object> = [];
  if (Array.isArray(dataRaw)) {
    items = dataRaw as Array<Object>;
  } else {
    const dataRecord: Record<string, Object> = dataRaw as Record<string, Object>;
    const listRaw: Object | undefined = dataRecord['list'];
    const songsRaw: Object | undefined = dataRecord['songs'];
    if (listRaw !== undefined && Array.isArray(listRaw)) {
      items = listRaw as Array<Object>;
    } else if (songsRaw !== undefined && Array.isArray(songsRaw)) {
      items = songsRaw as Array<Object>;
    }
  }

  const recognizedAt: number = Date.now();
  const results: RecognizedSong[] = [];
  const seen: Set<string> = new Set<string>();
  for (const item of items) {
    const mapped: RecognizedSong | undefined = mapItem(item as Record<string, Object>, recognizedAt);
    if (mapped === undefined) {
      continue;
    }
    const dedupeKey: string = `${mapped.title}__${mapped.artist}`.toLowerCase();
    if (seen.has(dedupeKey)) {
      continue;
    }
    seen.add(dedupeKey);
    results.push(mapped);
    hilog.info(DOMAIN, TAG, 'candidate %{public}s - %{public}s', mapped.title, mapped.artist);
    if (results.length >= MAX_CANDIDATES) {
      break;
    }
  }
  hilog.info(DOMAIN, TAG, 'recognize done candidates=%{public}d', results.length);
  return results;
}
