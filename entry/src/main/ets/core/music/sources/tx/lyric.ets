/**
 * QQ音乐 - 歌词获取
 */
import { httpRequest } from '../../../../core/network/http';
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

function parseTxJson<T>(raw: string | Object | ArrayBuffer): T | null {
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

// 空歌词
const EMPTY_LYRIC: LyricInfo = {
  lyric: '',
  tlyric: null,
  lxlyric: null,
  rlyric: null,
};

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
      const body = parseTxJson<QQMusicLyricResponse>(resultData);

      if (body && body.code === 0 && body.lyric) {
        const lyricInfo: LyricInfo = {
          lyric: body.lyric || '',
          tlyric: body.trans || null,
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
