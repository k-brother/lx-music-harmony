/**
 * 咪咕音乐 - 歌词获取
 */
import { httpRequest } from '../../../../core/network/http';
import type { LyricInfo, MusicInfo } from '../../../../types/MusicTypes';

// 歌词响应数据
interface MGLyricData {
  lrcUrl?: string;
}

interface MGLyricResponse {
  data?: MGLyricData;
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
  getLyric: (songInfo: MusicInfo) => Promise<LyricInfo>;
  downloadLyric: (url: string) => Promise<LyricInfo>;
}

/**
 * 歌词模块
 */
export const lyric: LyricInterface = {
  /**
   * 获取歌词
   */
  getLyric(songInfo: MusicInfo): Promise<LyricInfo> {
    const copyrightId: string | undefined = songInfo.copyrightId;
    if (!copyrightId) {
      return Promise.resolve(EMPTY_LYRIC);
    }

    const url: string = `https://m.music.migu.cn/migu/remoting/cms_detail_tag?cpid=${copyrightId}`;

    const headers: Map<string, string> = new Map();
    headers.set('Referer', 'https://m.music.migu.cn/');
    headers.set('User-Agent', 'Mozilla/5.0 (iPhone; CPU iPhone OS 14_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/14.0 Mobile/15E148 Safari/604.1');

    return httpRequest(url, { header: headers }).promise.then((response) => {
      const body: MGLyricResponse = response.result as MGLyricResponse;

      if (body && body.data && body.data.lrcUrl) {
        return lyric.downloadLyric(body.data.lrcUrl);
      }
      const result: LyricInfo = { lyric: '', tlyric: null, lxlyric: null, rlyric: null };
      return result;
    }).catch(() => {
      const result: LyricInfo = { lyric: '', tlyric: null, lxlyric: null, rlyric: null };
      return result;
    });
  },

  /**
   * 下载歌词
   */
  downloadLyric(url: string): Promise<LyricInfo> {
    return httpRequest(url).promise.then((response) => {
      const lrc: string = response.data as string;
      const lyricInfo: LyricInfo = {
        lyric: lrc || '',
        tlyric: null,
        lxlyric: null,
        rlyric: null,
      };
      return lyricInfo;
    }).catch(() => EMPTY_LYRIC);
  },
};

export default lyric;
