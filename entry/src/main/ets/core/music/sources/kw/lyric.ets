/**
 * 酷我音乐 - 歌词模块
 * 对应安卓源码: src/utils/musicSdk/kw/lyric.js
 *
 * 两条通道，按实测可靠性排序：
 *  1. newlyric：响应体是 zlib 压缩包，解压后是 GB18030 文本（实测 6/6 稳定）；
 *  2. 移动端 songinfoandlrc：UTF-8 JSON、字段干净，但服务端约 1/3 概率返回空列表，必须重试。
 * 两条都拿不到时返回空歌词，由 ResolvePlayback 跨源兜底。
 *
 * 请求头注意：m.kuwo.cn 只要带上 Referer 就会返回「音乐查询失败」（实测），
 * 因此这里只带移动端 UA，绝不带 Referer。
 */

import hilog from '@ohos.hilog';
import { util } from '@kit.ArkTS';
import { httpRequest, httpRequestBinary, parseHttpBodyJson, type HttpRequestConfig, type HttpResponse } from '../../../../core/network/http';
import { zlibInflate } from '../../../../core/napi/napi_inflate';
import { utf8Decode, utf8Encode } from '../../../../utils/TextCodec';
import type { MusicInfo, LyricInfo } from '../../../../types/MusicTypes';
import { decodeHtmlEntities } from '../../../../utils/CommonUtils';

const TAG = 'KwLyric';
const DOMAIN = 0x0001;

/** 与安卓版一致的异或密钥 */
const BUF_KEY = 'yeelion';
/** 移动端 UA：酷我接口按 UA 返回移动端数据 */
const MOBILE_UA = 'Mozilla/5.0 (Linux; Android 12; SM-G991B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
/** 移动端歌词接口实测不稳定，重试可以显著提高命中率 */
const MOBILE_LYRIC_ATTEMPTS = 3;
const RETRY_DELAY_MS = 200;
/** 压缩体前导头部（tp=content\r\n...\r\n\r\n）长度上限，超过就认为不是压缩体 */
const MAX_HEADER_SCAN = 512;

const REQUEST_TIMEOUT_MS = 10000;

const EMPTY_LYRIC: LyricInfo = {
  lyric: '[00:00.00]暂无歌词',
  tlyric: '',
  lxlyric: '',
};

/** LRC 行：[mm:ss.xx] / [mm:ss.xxx] */
const LRC_TIME_EXP = /^\[([\d:.]*)\]/;
/** 酷我逐字标记：<起始, 时长>（时长可能为负数） */
const WORD_TAG_EXP = /<\d+,-?\d+>/g;
/** 判断某一行是否带逐字标记（不带 /g，避免 lastIndex 副作用） */
const WORD_TAG_TEST_EXP = /<\d+,-?\d+>/;
/** 标签行：[ti:] / [ar:] / [by:] 等 */
const TAG_LINE_EXP = /^\[[a-z]+:/i;
/** 是否含有效时间轴 */
const TIME_TAG_TEST_EXP = /\[\d{1,2}:\d{1,2}/;

interface LyricLine {
  time: string;
  text: string;
}

interface SplitLyric {
  main: LyricLine[];
  trans: LyricLine[];
}

/** 移动端歌词接口数据项 */
interface KwLyricListItem {
  /** 秒数（服务端实际返回字符串，这里兼容两种） */
  time: number | string;
  lineLyric?: string;
}

interface KwSongInfo {
  songName?: string;
  artist?: string;
  album?: string;
}

interface KwLyricContainer {
  lrclist?: KwLyricListItem[];
  songinfo?: KwSongInfo;
}

interface KwLyricResponse {
  data?: KwLyricContainer;
  status?: number;
  msg?: string;
}

/**
 * 构建 newlyric 接口参数（异或后 base64）
 */
function buildParams(id: string, isGetLyricx: boolean): string {
  let params = `user=12345,web,web,web&requester=localhost&req=1&rid=MUSIC_${id}`;
  if (isGetLyricx) {
    params += '&lrcx=1';
  }

  let output = '';
  for (let i = 0; i < params.length; i++) {
    const charCode = params.charCodeAt(i) ^ BUF_KEY.charCodeAt(i % BUF_KEY.length);
    output += String.fromCharCode(charCode);
  }
  return base64Encode(output);
}

/**
 * Base64 编码（参数只有 ASCII，标准分组即可）
 */
function base64Encode(str: string): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  let i = 0;

  while (i < str.length) {
    const a = str.charCodeAt(i++);
    const b = i < str.length ? str.charCodeAt(i++) : 0;
    const c = i < str.length ? str.charCodeAt(i++) : 0;

    const triplet = (a << 16) | (b << 8) | c;

    result += chars.charAt((triplet >> 18) & 0x3F);
    result += chars.charAt((triplet >> 12) & 0x3F);
    result += i - 2 < str.length ? chars.charAt((triplet >> 6) & 0x3F) : '=';
    result += i - 1 < str.length ? chars.charAt(triplet & 0x3F) : '=';
  }

  return result;
}

/**
 * 逐字节异或（对应安卓版 Buffer 异或）
 */
function xorDecode(bytes: Uint8Array): Uint8Array {
  const key: Uint8Array = utf8Encode(BUF_KEY);
  const out = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) {
    out[i] = bytes[i] ^ key[i % key.length];
  }
  return out;
}

/**
 * 在字节流中查找子串（找不到返回 -1）
 */
function indexOfBytes(bytes: Uint8Array, pattern: Uint8Array): number {
  if (pattern.length === 0 || bytes.length < pattern.length) {
    return -1;
  }
  const limit = bytes.length - pattern.length;
  for (let i = 0; i <= limit; i++) {
    let matched = true;
    for (let j = 0; j < pattern.length; j++) {
      if (bytes[i + j] !== pattern[j]) {
        matched = false;
        break;
      }
    }
    if (matched) {
      return i;
    }
  }
  return -1;
}

/**
 * 秒 -> [mm:ss.xx]
 */
function toLrcTime(seconds: number): string {
  const safe = isNaN(seconds) || seconds < 0 ? 0 : seconds;
  const minutes = Math.floor(safe / 60);
  const rest = (safe % 60).toFixed(2).padStart(5, '0');
  return `${minutes.toString().padStart(2, '0')}:${rest}`;
}

/**
 * 同一时间戳的第二行在酷我里是「翻译」，拆到 tlyric
 * 与安卓版 sortLrcArr 行为一致：重复行把上一句挪到翻译轨，并改用再上一句的时间
 */
function splitTranslations(entries: LyricLine[]): SplitLyric {
  const main: LyricLine[] = [];
  const trans: LyricLine[] = [];
  const seen: Set<string> = new Set();

  for (const entry of entries) {
    if (seen.has(entry.time)) {
      if (main.length < 2) {
        continue;
      }
      const moved: LyricLine = main.pop() as LyricLine;
      moved.time = main[main.length - 1].time;
      trans.push(moved);
      main.push(entry);
    } else {
      main.push(entry);
      seen.add(entry.time);
    }
  }

  const result: SplitLyric = { main, trans };
  return result;
}

/**
 * 组装 LRC 文本（标签 + 正文）
 */
function joinLrc(tags: string[], lines: LyricLine[]): string {
  const body = lines.map((line: LyricLine): string => `[${line.time}]${line.text}`).join('\n');
  if (tags.length === 0) {
    return body;
  }
  return `${tags.join('\n')}\n${body}`;
}

/**
 * 构建歌词标签
 */
function buildTags(songName: string, artist: string, album: string): string[] {
  const tags: string[] = [];
  if (songName.length > 0) {
    tags.push(`[ti:${songName}]`);
  }
  if (artist.length > 0) {
    tags.push(`[ar:${artist}]`);
  }
  if (album.length > 0) {
    tags.push(`[al:${album}]`);
  }
  return tags;
}

/**
 * 是否含有效时间轴
 */
function hasTimeTag(lyric: string): boolean {
  return TIME_TAG_TEST_EXP.test(lyric);
}

/**
 * 解析 LRC 文本（兼容逐字标记），翻译行自动拆到 tlyric
 */
function parseLrcText(lrc: string): LyricInfo {
  const lines = lrc.split(/\r\n|\r|\n/);
  const tags: string[] = [];
  const entries: LyricLine[] = [];
  // 逐字歌词原样留一份：主歌词要抹掉标记，逐字渲染需要标记
  const wordLines: string[] = [];

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (line.length === 0) {
      continue;
    }
    const match = LRC_TIME_EXP.exec(line);
    if (match) {
      let time = match[1];
      // .xx -> .xxx，统一到毫秒
      if (/\.\d\d$/.test(time)) {
        time += '0';
      }
      if (WORD_TAG_TEST_EXP.test(line)) {
        wordLines.push(line);
      }
      const text = line.replace(LRC_TIME_EXP, '').replace(WORD_TAG_EXP, '').trim();
      entries.push({ time, text });
      continue;
    }
    if (TAG_LINE_EXP.test(line)) {
      tags.push(line);
    }
  }

  const split = splitTranslations(entries);
  const mainText = decodeHtmlEntities(joinLrc(tags, split.main));
  const info: LyricInfo = {
    lyric: hasTimeTag(mainText) ? mainText : EMPTY_LYRIC.lyric,
    tlyric: split.trans.length > 0 ? decodeHtmlEntities(joinLrc([], split.trans)) : '',
    lxlyric: wordLines.length > 0 ? decodeHtmlEntities(wordLines.join('\n')) : '',
  };
  return info;
}

/**
 * 解压 newlyric 响应体并解码出 LRC 文本
 */
function decodeNewlyricPayload(raw: ArrayBuffer, isGetLyricx: boolean): string {
  const bytes = new Uint8Array(raw);
  const head = utf8Decode(bytes.subarray(0, Math.min(bytes.length, 10)));
  if (!head.startsWith('tp=content')) {
    // 不是压缩体（例如直接返回错误信息），交给下一条通道
    return '';
  }

  const separator = indexOfBytes(bytes, new Uint8Array([13, 10, 13, 10]));
  if (separator < 0 || separator > MAX_HEADER_SCAN) {
    return '';
  }
  const payload = raw.slice(separator + 4);
  const inflated = zlibInflate(payload);
  if (!inflated) {
    hilog.warn(DOMAIN, TAG, 'newlyric inflate failed');
    return '';
  }

  let content = new Uint8Array(inflated);
  if (isGetLyricx) {
    // lrcx=1：内容先 base64，再异或，才是 GB18030 字节
    const base64Text = utf8Decode(content).replace(/\s/g, '');
    if (base64Text.length === 0) {
      return '';
    }
    content = xorDecode(new util.Base64Helper().decodeSync(base64Text));
  }

  return util.TextDecoder.create('gb18030').decodeToString(content);
}

/**
 * newlyric 通道（实测最稳）
 */
function requestNewlyric(songmid: string, isGetLyricx: boolean): Promise<string> {
  const params = buildParams(songmid, isGetLyricx);
  const url = `http://newlyric.kuwo.cn/newlyric.lrc?${params}`;
  const reqOpts: HttpRequestConfig = {
    readTimeout: REQUEST_TIMEOUT_MS,
    headers: { 'User-Agent': MOBILE_UA },
  };

  return httpRequestBinary(url, reqOpts).then((body: ArrayBuffer | null) => {
    if (!body) {
      return '';
    }
    try {
      return decodeNewlyricPayload(body, isGetLyricx);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'decode newlyric failed: %{public}s', (err as Error)?.message);
      return '';
    }
  }).catch((err: Error) => {
    hilog.warn(DOMAIN, TAG, 'request newlyric failed: %{public}s', err?.message);
    return '';
  });
}

/**
 * 解析移动端 songinfoandlrc 响应
 */
function parseMobileLyric(data: KwLyricResponse): LyricInfo {
  const container = data.data;
  const list = container?.lrclist;
  if (!container || !list || list.length === 0) {
    return EMPTY_LYRIC;
  }

  const entries: LyricLine[] = [];
  for (const item of list) {
    const seconds = typeof item.time === 'number' ? item.time : parseFloat(item.time);
    entries.push({
      time: toLrcTime(seconds),
      text: (item.lineLyric ?? '').trim(),
    });
  }

  const split = splitTranslations(entries);
  const songInfo = container.songinfo;
  const tags = buildTags(songInfo?.songName ?? '', songInfo?.artist ?? '', songInfo?.album ?? '');
  const mainText = decodeHtmlEntities(joinLrc(tags, split.main));
  const info: LyricInfo = {
    lyric: hasTimeTag(mainText) ? mainText : EMPTY_LYRIC.lyric,
    tlyric: split.trans.length > 0 ? decodeHtmlEntities(joinLrc([], split.trans)) : '',
    lxlyric: '',
  };
  return info;
}

/**
 * 移动端接口单次请求：拿到有效歌词返回结果，否则返回 null（交给重试）
 */
function requestMobileLyricOnce(songmid: string): Promise<LyricInfo | null> {
  const url = `https://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=${songmid}`;
  const reqOpts: HttpRequestConfig = {
    responseType: 'text',
    readTimeout: REQUEST_TIMEOUT_MS,
    // 千万不要加 Referer：带上后接口固定返回「音乐查询失败」
    headers: { 'User-Agent': MOBILE_UA },
  };

  return httpRequest(url, reqOpts).promise.then((response: HttpResponse<Object>) => {
    const data = parseHttpBodyJson<KwLyricResponse>(
      response.data as string | Object | ArrayBuffer | undefined | null
    );
    if (!data) {
      return null;
    }
    const info = parseMobileLyric(data);
    return hasTimeTag(info.lyric) ? info : null;
  }).catch(() => {
    return null;
  });
}

/**
 * 延时（重试间隔）
 */
function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

/**
 * 移动端通道：接口不稳定，失败后重试
 */
function requestMobileLyric(songmid: string, attempt: number = 0): Promise<LyricInfo> {
  return requestMobileLyricOnce(songmid).then((info: LyricInfo | null) => {
    if (info) {
      if (attempt > 0) {
        hilog.info(DOMAIN, TAG, 'mobile lyric ok after %{public}d retry', attempt);
      }
      return info;
    }
    if (attempt + 1 >= MOBILE_LYRIC_ATTEMPTS) {
      hilog.warn(DOMAIN, TAG, 'mobile lyric empty after %{public}d attempts', MOBILE_LYRIC_ATTEMPTS);
      return EMPTY_LYRIC;
    }
    return delay(RETRY_DELAY_MS).then(() => requestMobileLyric(songmid, attempt + 1));
  });
}

/**
 * 歌词模块接口
 */
interface LyricModuleInterface {
  getLyric: (songInfo: MusicInfo, isGetLyricx?: boolean) => Promise<LyricInfo>;
}

export const lyric: LyricModuleInterface = {
  /**
   * 获取歌词：先走稳定的压缩体接口，失败再走移动端接口（带重试）
   */
  getLyric(songInfo: MusicInfo, isGetLyricx: boolean = true): Promise<LyricInfo> {
    const songmid = songInfo.songmid || songInfo.id || '';
    if (!songmid || songmid.length === 0) {
      return Promise.resolve(EMPTY_LYRIC);
    }

    return requestNewlyric(songmid, isGetLyricx).then((text: string) => {
      if (text.length === 0) {
        return requestMobileLyric(songmid);
      }
      const parsed = parseLrcText(text);
      if (hasTimeTag(parsed.lyric)) {
        return parsed;
      }
      return requestMobileLyric(songmid);
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'getLyric failed: %{public}s', err?.message);
      return requestMobileLyric(songmid);
    });
  },
};
