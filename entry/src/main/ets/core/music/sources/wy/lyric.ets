/**
 * 网易云音乐 - 歌词获取
 */
import { httpRequest, parseHttpBodyJson } from '../../../../core/network/http';
import type { LyricInfo } from '../../../../types/MusicTypes';

// 网易云歌词响应数据
interface WYLyricInfo {
  lyric?: string;
}

interface WYLyricResponse {
  lrc?: WYLyricInfo;
  tlyric?: WYLyricInfo | null;
  /** 逐字歌词（yrc），请求时带 yv=1 才会返回 */
  yrc?: WYLyricInfo | null;
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

    // yv=1 拿逐字歌词（yrc）；拿不到也不影响普通歌词
    const url: string = `http://music.163.com/api/song/lyric?id=${songmid}&lv=1&kv=1&tv=-1&yv=1`;

    const headers: Map<string, string> = new Map();
    headers.set('Referer', 'https://music.163.com/');
    headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');

    return httpRequest(url, { header: headers }).promise.then((response) => {
      const resultData: string | Object | ArrayBuffer = response.result as string | Object | ArrayBuffer;
      const body = parseHttpBodyJson<WYLyricResponse>(resultData);

      if (body && body.lrc && body.lrc.lyric) {
        const yrcText: string = body.yrc && body.yrc.lyric ? body.yrc.lyric : '';
        const lyricInfo: LyricInfo = {
          lyric: body.lrc.lyric || '',
          tlyric: body.tlyric && body.tlyric.lyric ? body.tlyric.lyric : null,
          lxlyric: yrcText.length > 0 ? yrcText : null,
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
