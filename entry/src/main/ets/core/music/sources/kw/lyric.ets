/**
 * 酷我音乐 - 歌词模块
 * 对应安卓源码: src/utils/musicSdk/kw/lyric.js
 */

import { httpRequest, type HttpRequestConfig, type HttpResponse } from '../../../../core/network/http';
import type { MusicInfo, LyricInfo } from '../../../../types/MusicTypes';
import { decodeHtmlEntities } from '../../../../utils/CommonUtils';

// 密钥
const BUF_KEY = 'yeelion';

// 歌词 API 数据项
interface KwLyricSongInfo {
  songName?: string;
  artist?: string;
  album?: string;
}

// 歌词 API 数据容器
interface KwLyricDataContainer {
  songinfo?: KwLyricSongInfo;
  lrclist?: KwLyricListItem[];
}

// 酷我歌词API数据
interface KwLyricApiData {
  data?: KwLyricDataContainer;
}

// 酷我歌词列表项
interface KwLyricListItem {
  time: number;
  lineLyric?: string;
}

/**
 * 构建歌词请求参数
 */
function buildParams(id: string, isGetLyricx: boolean): string {
  let params = `user=12345,web,web,web&requester=localhost&req=1&rid=MUSIC_${id}`;
  if (isGetLyricx) {
    params += '&lrcx=1';
  }

  // XOR 加密
  const bufStr = params;
  let output = '';
  for (let i = 0; i < bufStr.length; i++) {
    const charCode = bufStr.charCodeAt(i) ^ BUF_KEY.charCodeAt(i % BUF_KEY.length);
    output += String.fromCharCode(charCode);
  }

  // 转换为 base64
  return base64Encode(output);
}

/**
 * Base64 编码
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
 * 歌词行项
 */
interface LyricLineItem {
  time: string;
  text: string;
}

/**
 * 解析 LRC 歌词结果
 */
interface ParseLrcResult {
  lyric: string;
  tlyric: string;
}

/**
 * 解析 LRC 歌词
 */
function parseLrc(lrc: string): ParseLrcResult {
  const lines = lrc.split(/\r\n|\r|\n/);
  let tags: string[] = [];
  let lrcArr: LyricLineItem[] = [];

  const timeExp = /^\[([\d:.]*)\]{1}/;

  for (const line of lines) {
    const trimmedLine = line.trim();

    // 匹配时间标签
    let match = timeExp.exec(trimmedLine);
    if (match) {
      const text = trimmedLine.replace(timeExp, '').trim();
      // 处理时间格式 .xx -> .xxx
      let time = match[1];
      if (/\.\d\d$/.test(time)) {
        time += '0';
      }
      lrcArr.push({ time, text });
    } else {
      // 检查是否是标签 [ti:xxx] [ar:xxx] 等
      const tagMatch = /^\[([a-z]+):(.+)\]$/i.exec(trimmedLine);
      if (tagMatch) {
        tags.push(trimmedLine);
      }
    }
  }

  // 排序歌词（按时间）
  lrcArr.sort((a: LyricLineItem, b: LyricLineItem): number => {
    const timeA = parseFloat(a.time.replace(':', '.'));
    const timeB = parseFloat(b.time.replace(':', '.'));
    return timeA - timeB;
  });

  // 构建歌词字符串
  const lyricLines: string[] = lrcArr.map((item: LyricLineItem): string => `[${item.time}]${item.text}`);
  const lyric = tags.join('\n') + (tags.length > 0 ? '\n' : '') + lyricLines.join('\n');

  const result: ParseLrcResult = {
    lyric: decodeHtmlEntities(lyric),
    tlyric: '', // 翻译歌词需要额外处理
  };
  return result;
}

/**
 * Base64 解码（ArkTS 兼容）
 */
function base64Decode(str: string): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  let i = 0;
  const paddedStr = str.replace(/=/g, '');

  while (i < paddedStr.length) {
    const a = chars.indexOf(paddedStr.charAt(i++));
    const b = chars.indexOf(paddedStr.charAt(i++));
    const c = chars.indexOf(paddedStr.charAt(i++));
    const d = chars.indexOf(paddedStr.charAt(i++));

    const triplet = (a << 18) | (b << 12) | (c << 6) | d;

    const char1 = (triplet >> 16) & 0xFF;
    const char2 = (triplet >> 8) & 0xFF;
    const char3 = triplet & 0xFF;

    if (char2 !== 0xFF) result += String.fromCharCode(char1);
    if (char3 !== 0xFF) result += String.fromCharCode(char2);
  }

  return result;
}

/**
 * 空歌词
 */
const EMPTY_LYRIC: LyricInfo = {
  lyric: '[00:00.00]暂无歌词',
  tlyric: '',
  lxlyric: '',
};

/**
 * 歌词模块接口
 */
interface LyricModuleInterface {
  getLyric: (songInfo: MusicInfo, isGetLyricx?: boolean) => Promise<LyricInfo>;
  getLyricFromApi: (songmid: string, isGetLyricx?: boolean) => Promise<LyricInfo>;
  getLyricFromMobileApi: (songmid: string) => Promise<LyricInfo>;
}

/**
 * 歌词模块
 */
export const lyric: LyricModuleInterface = {
  /**
   * 获取歌词
   */
  getLyric(songInfo: MusicInfo, isGetLyricx: boolean = true): Promise<LyricInfo> {
    const songmid = songInfo.songmid || songInfo.id || '';
    if (!songmid || songmid.length === 0) {
      return Promise.resolve(EMPTY_LYRIC);
    }

    // 方式1：通过 API 获取歌词
    return lyric.getLyricFromApi(songmid, isGetLyricx);
  },

  /**
   * 从 API 获取歌词
   */
  getLyricFromApi(songmid: string, isGetLyricx: boolean = true): Promise<LyricInfo> {
    if (!songmid || songmid.length === 0) {
      return Promise.resolve(EMPTY_LYRIC);
    }
    // 使用加密参数请求歌词
    const encryptedParams = buildParams(songmid, isGetLyricx);
    const url = `https://newlyric.kuwo.cn/newlyric.lrc?${encryptedParams}`;

    return new Promise((resolve, reject) => {
      const reqOpts: HttpRequestConfig = {
        responseType: 'text',
        readTimeout: 10000,
      };
      const task = httpRequest(url, reqOpts);

      task.promise.then((response: HttpResponse<Object>) => {
        try {
          // 歌词可能是 base64 编码的
          let lrcText: string = response.data as string;

          // 尝试解码 base64
          try {
            lrcText = base64Decode(lrcText);
          } catch {
            // 如果不是 base64，保持原样
          }

          // 解析歌词
          const parsed: ParseLrcResult = parseLrc(lrcText);

          if (!parsed.lyric || parsed.lyric.length < 10) {
            // 歌词太短，尝试备用方式
            lyric.getLyricFromMobileApi(songmid).then((lyricInfo: LyricInfo) => {
              resolve(lyricInfo);
            }).catch(() => {
              resolve(EMPTY_LYRIC);
            });
          } else {
            resolve(parsed);
          }
        } catch {
          // 解析失败，尝试备用方式
          lyric.getLyricFromMobileApi(songmid).then((lyricInfo: LyricInfo) => {
            resolve(lyricInfo);
          }).catch(() => {
            resolve(EMPTY_LYRIC);
          });
        }
      }).catch(() => {
        // 请求失败，尝试备用方式
        lyric.getLyricFromMobileApi(songmid).then((lyricInfo: LyricInfo) => {
          resolve(lyricInfo);
        }).catch(() => {
          resolve(EMPTY_LYRIC);
        });
      });
      // 避免reject未使用的警告
      void reject;
    });
  },

  /**
   * 备用方式：通过移动端 API 获取歌词
   */
  getLyricFromMobileApi(songmid: string): Promise<LyricInfo> {
    if (!songmid || songmid.length === 0) {
      return Promise.resolve(EMPTY_LYRIC);
    }
    const url = `https://m.kuwo.cn/newh5/singles/songinfoandlrc?musicId=${songmid}`;

    return new Promise((resolve) => {
      const reqOpts2: HttpRequestConfig = {
        responseType: 'text',
        readTimeout: 10000,
      };
      const task = httpRequest(url, reqOpts2);

      task.promise.then((response: HttpResponse<Object>) => {
        try {
          const data: KwLyricApiData = JSON.parse(response.data as string) as KwLyricApiData;

          if (data.data && data.data.lrclist && data.data.lrclist.length > 0) {
            const songInfo: KwLyricSongInfo | undefined = data.data.songinfo;
            // 构建歌词
            const tags: string[] = [
              `[ti:${songInfo?.songName || ''}]`,
              `[ar:${songInfo?.artist || ''}]`,
              `[al:${songInfo?.album || ''}]`,
            ].filter((tag: string): boolean => tag.length > 5);

            const lrcLines: string[] = data.data.lrclist.map((item: KwLyricListItem): string => {
              const mins = Math.floor(item.time / 60);
              const secs = (item.time % 60).toFixed(2);
              return `[${mins.toString().padStart(2, '0')}:${secs}]${item.lineLyric || ''}`;
            });

            const lyricText: string = decodeHtmlEntities(tags.join('\n') + '\n' + lrcLines.join('\n'));

            const lyricInfo: LyricInfo = {
              lyric: lyricText,
              tlyric: '',
              lxlyric: '',
            };
            resolve(lyricInfo);
          } else {
            const lyricInfo: LyricInfo = {
              lyric: '[00:00.00]暂无歌词',
              tlyric: '',
              lxlyric: '',
            };
            resolve(lyricInfo);
          }
        } catch {
          resolve(EMPTY_LYRIC);
        }
      }).catch(() => {
        resolve(EMPTY_LYRIC);
      });
    });
  }
};
