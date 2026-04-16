/**
 * QQ音乐 - 歌词获取
 */
import { httpRequest, parseHttpBodyJson } from '../../../../core/network/http';
import type { LyricInfo } from '../../../../types/MusicTypes';

// QQ音乐歌词响应数据
interface QQMusicLyricData {
  lyric?: string;
  trans?: string;
}

interface QQMusicLyricResponse {
  code: number;
  lyric?: string;
  trans?: string;
}

// 空歌词
const EMPTY_LYRIC: LyricInfo = {
  lyric: '',
  tlyric: null,
  lxlyric: null,
  rlyric: null,
};
const LRC_TIME_TAG = /\[\d{1,2}:\d{1,2}(?:\.\d{1,3})?\]/;

function decodeBase64Text(value: string | undefined): string {
  if (!value) {
    return '';
  }
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  let i = 0;
  const paddedStr = value.replace(/[^A-Za-z0-9+/=]/g, '');
  while (i < paddedStr.length) {
    const a = chars.indexOf(paddedStr.charAt(i++));
    const b = chars.indexOf(paddedStr.charAt(i++));
    const c = chars.indexOf(paddedStr.charAt(i++));
    const d = chars.indexOf(paddedStr.charAt(i++));
    if (a < 0 || b < 0) break;
    const triplet = (a << 18) | (b << 12) | ((c < 0 ? 0 : c) << 6) | (d < 0 ? 0 : d);
    result += String.fromCharCode((triplet >> 16) & 0xFF);
    if (c >= 0) result += String.fromCharCode((triplet >> 8) & 0xFF);
    if (d >= 0) result += String.fromCharCode(triplet & 0xFF);
  }
  return result;
}

// 歌词模块接口
export interface LyricInterface {
  getLyric: (songmid: string) => Promise<LyricInfo>;
}

/**
 * 歌词模块
 */
export const lyric: LyricInterface = {
  /**
   * 获取歌词
   */
  getLyric(songmid: string): Promise<LyricInfo> {
    if (!songmid) {
      return Promise.resolve(EMPTY_LYRIC);
    }

    const url: string = `https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=${songmid}&g_tk=5381&format=json&inCharset=utf-8&outCharset=utf-8&nobase64=1`;

    const headers: Map<string, string> = new Map();
    headers.set('Referer', 'https://y.qq.com/');
    headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');

    return httpRequest(url, { header: headers }).promise.then((response) => {
      const resultData: string | Object | ArrayBuffer = response.result as string | Object | ArrayBuffer;
      const body = parseHttpBodyJson<QQMusicLyricResponse>(resultData);

      if (body && body.code === 0 && body.lyric) {
        let lyricText = body.lyric || '';
        let transText = body.trans || null;
        if (!LRC_TIME_TAG.test(lyricText)) {
          const decodedLyric = decodeBase64Text(lyricText);
          if (LRC_TIME_TAG.test(decodedLyric)) {
            lyricText = decodedLyric;
            const decodedTrans = decodeBase64Text(body.trans);
            transText = decodedTrans.length > 0 ? decodedTrans : null;
          }
        }
        const lyricInfo: LyricInfo = {
          lyric: lyricText,
          tlyric: transText,
          lxlyric: null,
          rlyric: null,
        };
        return lyricInfo;
      }
      return EMPTY_LYRIC;
    }).catch(() => {
      return EMPTY_LYRIC;
    });
  },
};

export default lyric;
