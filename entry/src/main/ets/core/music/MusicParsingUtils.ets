// 歌词与时长、音质等解析/格式化工具（原 utils.ets）

import type { MusicInfo, LyricInfo, Quality, MusicQualityType, MusicSource, OtherSourceInfo, QualityDetail } from '../../types/MusicTypes';
import { formatClock, parsePlayTimeText } from '../../utils/FormatTools';

// 尝试获取的音乐品质列表
export const TRY_QUALITYS_LIST: string[] = ['flac24bit', 'flac', '320k', '128k'];

/**
 * 解析时长字符串为秒数
 */
export function parseInterval(interval: string): number {
  // 实现统一在 utils/FormatTools（原来这里另写了一份从后往前解析）
  return parsePlayTimeText(interval);
}

/**
 * 格式化秒数为时长字符串（实现统一在 utils/FormatTools）
 */
export function formatInterval(seconds: number): string {
  return formatClock(seconds);
}

/**
 * 获取播放音质
 */
export function getPlayQuality(highQuality: Quality, musicInfo: MusicInfo): Quality {
  let quality: Quality = '128k';

  const validQualities: Quality[] = ['flac24bit', 'flac', '320k', '128k'];
  const startIndex = validQualities.indexOf(highQuality);
  if (startIndex >= 0) {
    const targetQualities = validQualities.slice(startIndex);
    // 尝试获取目标音质
    const targetQuality = targetQualities.find(q => {
      // 检查音乐是否支持该音质
      if (musicInfo.types) {
        const hasQuality = musicInfo.types.some((t: MusicQualityType) => t.type === q);
        if (hasQuality) {
          return true;
        }
      }
      // 检查 _types Map
      if (musicInfo._types && musicInfo._types.has(q as Quality)) {
        return true;
      }
      return false;
    });

    if (targetQuality) {
      quality = targetQuality as Quality;
    }
  }

  return quality;
}

/**
 * 构建歌词信息
 */
/** 空歌词（"确实没有歌词"时统一用它，避免各处 new 结构） */
export function createEmptyLyricInfo(): LyricInfo {
  return {
    lyric: '',
    tlyric: null,
    lxlyric: null,
    rlyric: null,
  };
}

export function buildLyricInfo(lyricInfo: LyricInfo): LyricInfo {
  if (!lyricInfo) {
    return {
      lyric: '',
      tlyric: null,
      lxlyric: null,
      rlyric: null,
    };
  }

  return {
    lyric: lyricInfo.lyric || '',
    tlyric: lyricInfo.tlyric || null,
    lxlyric: lyricInfo.lxlyric || null,
    rlyric: lyricInfo.rlyric || null,
  };
}

/**
 * 解析LRC格式歌词
 */
export interface LyricLine {
  time: number;
  text: string;
  endTime?: number;
}

export function parseLrc(lrc: string): LyricLine[] {
  if (!lrc) return [];

  const lines = lrc.split('\n');
  const result: LyricLine[] = [];

  for (const line of lines) {
    // 匹配时间标签 [mm:ss.xx] 或 [mm:ss.xxx]
    const match = line.match(/\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)/);
    if (match) {
      const minutes = parseInt(match[1], 10);
      const seconds = parseInt(match[2], 10);
      const milliseconds = parseInt(match[3].padEnd(3, '0'), 10);
      const time = minutes * 60 + seconds + milliseconds / 1000;
      const text = match[4].trim();

      if (text) {
        result.push({ time, text });
      }
    }
  }

  return result.sort((a, b) => a.time - b.time);
}

/**
 * 获取当前歌词索引
 */
export function getCurrentLyricIndex(lines: LyricLine[], currentTime: number): number {
  if (!lines || lines.length === 0) return -1;

  let index = -1;

  for (let i = 0; i < lines.length; i++) {
    if (lines[i].time <= currentTime) {
      index = i;
    } else {
      break;
    }
  }

  return index;
}

/**
 * 过滤字符串特殊字符
 */
export function filterMusicName(str: string): string {
  if (!str) return '';
  return str.replace(/\s|'|\.|,|，|&|"|、|\(|\)|（|）|`|~|-|<|>|\||\/|\]|\[|!|！/g, '');
}

/**
 * 比较两个音乐信息是否相同
 */
export function isSameMusic(info1: MusicInfo, info2: MusicInfo): boolean {
  if (!info1 || !info2) return false;
  return info1.songmid === info2.songmid && info1.source === info2.source;
}

/**
 * 获取音乐唯一标识
 */
export function getMusicKey(musicInfo: MusicInfo): string {
  if (!musicInfo) return '';
  return `${musicInfo.source}_${musicInfo.songmid}`;
}

/**
 * 排序歌手名称
 */
export function sortSingerName(singer: string): string {
  if (!singer) return '';

  const separators = /、|&|;|；|\/|,|，|\|/;
  if (separators.test(singer)) {
    return singer.split(separators).sort((a, b) => a.localeCompare(b)).join('、');
  }

  return singer;
}

/**
 * 检查歌词是否存在时间标签
 */
export function existTimeExp(lrc: string): boolean {
  return /\[\d{1,2}:.*\d{1,4}\]/.test(lrc);
}

/**
 * 质量字符串比较
 */
export function compareQuality(q1: string, q2: string): number {
  const order: string[] = ['flac24bit', 'flac', '320k', '192k', '128k', '96k', '64k'];
  const i1 = order.indexOf(q1);
  const i2 = order.indexOf(q2);
  return (i1 === -1 ? order.length : i1) - (i2 === -1 ? order.length : i2);
}

/**
 * 获取最高音质
 */
export function getHighestQuality(types: MusicQualityType[]): Quality {
  // Quality 类型只有 '128k', '320k', 'flac', 'flac24bit'
  const order: Quality[] = ['flac24bit', 'flac', '320k', '128k'];

  for (const q of order) {
    // 检查 types 数组中是否有该音质
    const hasQuality = types.some((t: MusicQualityType) => t.type === q);
    if (hasQuality) {
      return q;
    }
  }

  return '128k';
}

/**
 * 检查音乐是否支持指定音质
 */
export function isSupportQuality(musicInfo: MusicInfo, quality: Quality): boolean {
  if (!musicInfo) return false;

  // 检查 types 数组
  if (musicInfo.types) {
    const hasQuality = musicInfo.types.some((t: MusicQualityType) => t.type === quality);
    if (hasQuality) {
      return true;
    }
  }

  // 检查 _types Map
  if (musicInfo._types && musicInfo._types.has(quality)) {
    return true;
  }

  // 如果没有质量信息，默认支持128k
  if ((!musicInfo.types || musicInfo.types.length === 0) && (!musicInfo._types || musicInfo._types.size === 0)) {
    return quality === '128k';
  }

  return false;
}

// 旧版音乐信息类型
interface OldMusicInfo {
  name?: string;
  singer?: string;
  source?: MusicSource;
  songmid?: string;
  id?: string;
  albumId?: string;
  albumName?: string;
  interval?: string;
  img?: string;
  pic?: string;
  lrc?: string;
  otherSource?: OtherSourceInfo[] | null;
  types?: MusicQualityType[];
  _types?: Map<Quality, QualityDetail>;
  typeUrl?: Map<string, string>;
  copyrightId?: string;
}

/**
 * 转换旧版音乐信息为新版
 */
export function toNewMusicInfo(oldInfo: OldMusicInfo): MusicInfo {
  const otherSource: OtherSourceInfo[] | null | undefined = oldInfo.otherSource || null;
  const types: MusicQualityType[] = oldInfo.types || [];
  const _types: Map<Quality, QualityDetail> = oldInfo._types || new Map<Quality, QualityDetail>();
  const typeUrl: Map<string, string> = oldInfo.typeUrl || new Map<string, string>();
  return {
    name: oldInfo.name || '',
    singer: oldInfo.singer || '',
    source: oldInfo.source || 'kw',
    songmid: oldInfo.songmid || oldInfo.id || '',
    albumId: oldInfo.albumId || '',
    albumName: oldInfo.albumName || '',
    interval: oldInfo.interval || null,
    img: oldInfo.img || oldInfo.pic || null,
    lrc: oldInfo.lrc || null,
    otherSource: otherSource,
    types: types,
    _types: _types,
    typeUrl: typeUrl,
    copyrightId: oldInfo.copyrightId || '',
  };
}

/**
 * 转换新版音乐信息为旧版
 */
export function toOldMusicInfo(newInfo: MusicInfo): OldMusicInfo {
  const otherSource: OtherSourceInfo[] | null | undefined = newInfo.otherSource || undefined;
  return {
    name: newInfo.name,
    singer: newInfo.singer,
    source: newInfo.source,
    songmid: newInfo.songmid,
    id: newInfo.songmid,
    albumId: newInfo.albumId || '',
    albumName: newInfo.albumName || '',
    interval: newInfo.interval || undefined,
    img: newInfo.img || undefined,
    pic: newInfo.img || undefined,
    lrc: newInfo.lrc || undefined,
    otherSource: otherSource,
    types: newInfo.types,
    _types: newInfo._types,
    typeUrl: newInfo.typeUrl,
    copyrightId: newInfo.copyrightId || '',
  };
}

/**
 * 判断是否为有效URL
 */
export function isValidUrl(url: string): boolean {
  if (!url) return false;
  return url.startsWith('http://') || url.startsWith('https://');
}

/**
 * 获取文件扩展名
 */
export function getFileExtension(url: string): string {
  if (!url) return '';

  const queryIndex = url.indexOf('?');
  const pathPart = queryIndex > 0 ? url.substring(0, queryIndex) : url;
  const lastDot = pathPart.lastIndexOf('.');
  if (lastDot > 0) {
    return pathPart.substring(lastDot + 1).toLowerCase();
  }

  return '';
}

/**
 * 判断是否为音频文件URL
 */
export function isAudioUrl(url: string): boolean {
  const ext = getFileExtension(url);
  return ['mp3', 'flac', 'm4a', 'aac', 'ogg', 'wav', 'opus'].includes(ext);
}

// 工具模块接口
interface UtilsModule {
  parseInterval: (interval: string) => number;
  formatInterval: (seconds: number) => string;
  parseLrc: (lrc: string) => LyricLine[];
  getCurrentLyricIndex: (lines: LyricLine[], currentTime: number) => number;
  getPlayQuality: (highQuality: Quality, musicInfo: MusicInfo) => Quality;
  buildLyricInfo: (lyricInfo: LyricInfo) => LyricInfo;
  filterMusicName: (str: string) => string;
  isSameMusic: (info1: MusicInfo, info2: MusicInfo) => boolean;
  getMusicKey: (musicInfo: MusicInfo) => string;
  sortSingerName: (singer: string) => string;
  compareQuality: (q1: string, q2: string) => number;
  getHighestQuality: (types: MusicQualityType[]) => Quality;
  isSupportQuality: (musicInfo: MusicInfo, quality: Quality) => boolean;
  isValidUrl: (url: string) => boolean;
  getFileExtension: (url: string) => string;
  isAudioUrl: (url: string) => boolean;
}

// 导出命名对象供高级用法
export const utils: UtilsModule = {
  parseInterval,
  formatInterval,
  parseLrc,
  getCurrentLyricIndex,
  getPlayQuality,
  buildLyricInfo,
  filterMusicName,
  isSameMusic,
  getMusicKey,
  sortSingerName,
  compareQuality,
  getHighestQuality,
  isSupportQuality,
  isValidUrl,
  getFileExtension,
  isAudioUrl,
};
