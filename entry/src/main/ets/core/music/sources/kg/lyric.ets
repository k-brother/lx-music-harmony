/**
 * 酷狗音乐 - 歌词获取
 */
import hilog from '@ohos.hilog';
import { httpRequest } from '../../../../core/network/http';
import { decodeName } from '../../../../utils/CommonUtils';
import { decodeKrc } from './util';
import type { MusicInfo, LyricInfo } from '../../../../types/MusicTypes';

const TAG = 'KgLyric';
const DOMAIN = 0x0001;

// 歌词内容接口
interface LyricContent {
  type: number;
  lyricContent: string[][];
}

// JSON 解析结果接口
interface LyricJSON {
  content: LyricContent[];
}

const headExp = /^[^\[]*\[id:\$\w+\]\n/;

/**
 * 解析歌词
 */
function parseLyric(str: string): LyricInfo {
  str = str.replace(/\r/g, '');
  if (headExp.test(str)) {
    str = str.replace(headExp, '');
  }

  // 解析翻译歌词
  let trans = str.match(/\[language:([\w=\\/+]+)\]/);
  let lyric = '';
  let rlyric: string[][] = [];
  let tlyric: string[][] = [];

  if (trans) {
    str = str.replace(/\[language:[\w=\\/+]+\]\n/, '');
    // Base64解码
    const jsonStr = base64DecodeStr(trans[1]);
    try {
      const json: LyricJSON = JSON.parse(jsonStr) as LyricJSON;
      for (const item of json.content) {
        switch (item.type) {
          case 0:
            rlyric = item.lyricContent;
            break;
          case 1:
            tlyric = item.lyricContent;
            break;
        }
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'parseLyric JSON parse failed: %{public}s', (e as Error)?.message);
    }
  }

  // 处理逐字歌词
  let i = 0;
  let lxlyric = str.replace(/\[((\d+),\d+)\].*/g, (match: string): string => {
    const result = /\[((\d+),\d+)\].*/.exec(match);
    if (!result) return match;
  
    let time = parseInt(result[2]);
    let ms = time % 1000;
    time = Math.floor(time / 1000);
    let m = Math.floor(time / 60).toString().padStart(2, '0');
    let s = (time % 60).toString().padStart(2, '0');
    let timeStr = `${m}:${s}.${ms}`;
  
    if (rlyric.length > i && rlyric[i]) {
      const joined = rlyric[i].join('');
      rlyric[i] = [`[${timeStr}]${joined}`];
    }
    if (tlyric.length > i && tlyric[i]) {
      const joined = tlyric[i].join('');
      tlyric[i] = [`[${timeStr}]${joined}`];
    }
    i++;
    return match.replace(result[1], timeStr);
  });

  let rlyricStr: string = rlyric.length > 0 ? rlyric.join('\n') : '';
  let tlyricStr: string = tlyric.length > 0 ? tlyric.join('\n') : '';
  lxlyric = lxlyric.replace(/<(\d+,\d+),\d+>/g, '<$1>');
  lxlyric = decodeName(lxlyric);
  lyric = lxlyric.replace(/<\d+,\d+>/g, '');
  const finalRLyric = decodeName(rlyricStr);
  const finalTLyric = decodeName(tlyricStr);

  const lyricInfo: LyricInfo = {
    lyric,
    tlyric: finalTLyric,
    rlyric: finalRLyric,
    lxlyric,
  };
  return lyricInfo;
}

/**
 * Base64解码字符串
 */
function base64DecodeStr(str: string): string {
  const base64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  let buffer: number = 0;
  let bitsCollected: number = 0;

  for (let i = 0; i < str.length; i++) {
    const c = str.charAt(i);
    if (c === '=') break;
    const idx = base64Chars.indexOf(c);
    if (idx === -1) continue;

    buffer = (buffer << 6) | idx;
    bitsCollected += 6;

    if (bitsCollected >= 8) {
      bitsCollected -= 8;
      result += String.fromCharCode((buffer >> bitsCollected) & 0xFF);
    }
  }

  return result;
}

/**
 * 获取时间长度(秒)
 */
function getIntervalSeconds(interval: string): number {
  if (!interval) return 0;
  const parts = interval.split(':');
  let total = 0;
  let unit = 1;

  while (parts.length > 0) {
    total += parseInt(parts.pop() || '0') * unit;
    unit *= 60;
  }

  return total;
}

// 歌词接口
interface LyricInterface {
  getIntv: (interval: string) => number;
  searchLyric: (name: string, hash: string, time: number) => Promise<LyricSearchResult | null>;
  getLyricDownload: (id: string, accessKey: string, fmt: string) => Promise<LyricInfo>;
  getLyric: (songInfo: MusicInfo) => Promise<LyricInfo>;
}

export const lyric: LyricInterface = {
  /**
   * 获取间隔秒数
   */
  getIntv(interval: string): number {
    return getIntervalSeconds(interval);
  },

  /**
   * 搜索歌词
   */
  searchLyric(name: string, hash: string, time: number): Promise<LyricSearchResult | null> {
    const url = `http://lyrics.kugou.com/search?ver=1&man=yes&client=pc&keyword=${encodeURIComponent(name)}&hash=${hash}&timelength=${time}&lrctxt=1`;

    const headers: Map<string, string> = new Map([
      ['KG-RC', '1'],
      ['KG-THash', 'expand_search_manager.cpp:852736169:451'],
      ['User-Agent', 'KuGou2012-9020-ExpandSearchManager'],
    ]);

    return httpRequest(url, { header: headers }).promise.then((response) => {
      const body = JSON.parse(response.result as string) as KGSearchLyricResponse;

      if (body.candidates && body.candidates.length > 0) {
        const info = body.candidates[0];
        const fmt = (info.krctype == 1 && info.contenttype != 1) ? 'krc' : 'lrc';
        const result: LyricSearchResult = {
          id: info.id,
          accessKey: info.accesskey,
          fmt: fmt,
        };
        return result;
      }
      return null;
    });
  },

  /**
   * 下载歌词
   */
  getLyricDownload(id: string, accessKey: string, fmt: string): Promise<LyricInfo> {
    const url = `http://lyrics.kugou.com/download?ver=1&client=pc&id=${id}&accesskey=${accessKey}&fmt=${fmt}&charset=utf8`;

    const headers: Map<string, string> = new Map([
      ['KG-RC', '1'],
      ['KG-THash', 'expand_search_manager.cpp:852736169:451'],
      ['User-Agent', 'KuGou2012-9020-ExpandSearchManager'],
    ]);

    return httpRequest(url, { header: headers }).promise.then((response) => {
      const body = JSON.parse(response.result as string) as KGLyricDownloadResponse;

      switch (body.fmt) {
        case 'krc':
          const decoded = decodeKrc(body.content);
          return parseLyric(decoded);
        case 'lrc':
          const lrcContent = base64DecodeStr(body.content);
          const lrcInfo: LyricInfo = {
            lyric: lrcContent,
            tlyric: '',
            rlyric: '',
            lxlyric: '',
          };
          return lrcInfo;
        default:
          return Promise.reject(new Error(`未知歌词格式: ${body.fmt}`));
      }
    });
  },

  /**
   * 获取歌词
   */
  getLyric(songInfo: MusicInfo): Promise<LyricInfo> {
    const interval: string | null = songInfo.interval;
    const time: number = interval ? lyric.getIntv(interval) : 0;
    const searchFn = lyric.searchLyric;
    const downloadFn = lyric.getLyricDownload;

    return searchFn(songInfo.name, songInfo.hash || '', time).then((result: LyricSearchResult | null): Promise<LyricInfo> => {
      if (!result) {
        return Promise.reject(new Error('Get lyric failed'));
      }
      return downloadFn(result.id, result.accessKey, result.fmt);
    });
  },
};

// 类型定义
interface LyricHeaders {
  'KG-RC': string;
  'KG-THash': string;
  'User-Agent': string;
}

interface LyricSearchResult {
  id: string;
  accessKey: string;
  fmt: string;
}

interface KGCandidate {
  id: string;
  accesskey: string;
  krctype: number;
  contenttype: number;
}

interface KGSearchLyricResponse {
  candidates: KGCandidate[];
}

interface KGLyricDownloadResponse {
  fmt: string;
  content: string;
}
