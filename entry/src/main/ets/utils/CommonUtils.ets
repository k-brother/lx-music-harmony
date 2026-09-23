import {
  formatClockWithHours,
  formatPlayCount as formatPlayCountCore,
  parsePlayTimeText,
} from './FormatTools';

// 格式化播放时间 - 对应 src/utils/format.ts（实现统一在 FormatTools）
export function formatPlayTime(time: number): string {
  return formatClockWithHours(time);
}

// 时间文本 → 秒（实现统一在 FormatTools）
export function parsePlayTime(timeStr: string): number {
  return parsePlayTimeText(timeStr);
}

// 格式化播放时间（带小时）
export function formatPlayTime2(time: number): string {
  return formatClockWithHours(time);
}

// 判断是否为空
export function isEmpty(value: object | string | null): boolean {
  if (value == null) return true;
  if (Array.isArray(value)) return value.length === 0;
  const keys = Object.keys(value);
  return keys.length === 0;
}

// 生成随机数
export function getRandom(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min)) + min;
}

// 深拷贝 - 使用JSON序列化方式（适用于简单对象）
export function deepClone(obj: object): object {
  if (obj === null) return obj;
  
  // 使用JSON序列化/反序列化实现深拷贝
  // 这种方法避免了类型断言，但只适用于可序列化的对象
  try {
    return JSON.parse(JSON.stringify(obj));
  } catch (e) {
    // 如果JSON方法失败，返回原对象
    return obj;
  }
}

// 生成随机ID
export { generateId } from './Utils';

// 数组操作
export function arrPush<T>(arr: T[], items: T[]): void {
  for (let i = 0; i < items.length; i++) {
    arr.push(items[i]);
  }
}

export function arrUnshift<T>(arr: T[], items: T[]): void {
  for (let i = items.length - 1; i >= 0; i--) {
    arr.unshift(items[i]);
  }
}

export function arrRemove<T>(arr: T[], index: number): T | null {
  if (index < 0 || index >= arr.length) return null;
  const removed = arr.splice(index, 1);
  return removed.length > 0 ? removed[0] : null;
}

// 解码 HTML 实体
export function decodeHtmlEntities(str: string): string {
  if (!str) return '';
  return str
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ');
}

// 解码名称（去除特殊字符和解码 HTML 实体）
export function decodeName(str: string): string {
  if (!str) return '';
  return str
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

// 格式化歌手名称（多个用、分隔）
export function formatSinger(singerStr: string): string {
  if (!singerStr) return '';
  return singerStr.replace(/&/g, '、');
}

/**
 * 播放量格式化：统一走 utils/FormatTools。
 *
 * 原实现把「亿」按 1/10000000、「万」按 1/1000 计算（除数少了一位），
 * 各音源歌单列表里的播放量整整大 10 倍；这里改为委托统一实现。
 */
export function formatPlayCount(num: number): string {
  return formatPlayCountCore(num, '万', '亿');
}

// 字符串转数字（带默认值）
export function parseIntDefault(str: string | null | undefined, defaultValue: number = 0): number {
  if (str == null || str === '') return defaultValue;
  const parsed = parseInt(str);
  return Number.isNaN(parsed) ? defaultValue : parsed;
}

// 格式化文件大小（紧凑写法，规则统一在 utils/FormatTools）
export { formatBytesCompact as sizeFormate } from './FormatTools';

// 去除字符串空格和特殊字符
export function trimSpecialChars(str: string): string {
  if (!str) return '';
  return str.replace(/\s|'|\.|,|，|&|"|、|\(|\)|（|）|`|~|-|<|>|\||\/|\]|\[|!|！/g, '');
}

// 正则表达式接口定义
export interface RegExpsInterface {
  singerSplit: RegExp;
  mInfo: RegExp;
  listDetailLink: RegExp;
  timeTag: RegExp;
  lyricTag: RegExp;
}

// 正则表达式工具
export const RegExps: RegExpsInterface = {
  // 歌手分隔符
  singerSplit: /、|&|;|；|\/|,|，|\|/,
  // 音乐信息
  mInfo: /level:(\w+),bitrate:(\d+),format:(\w+),size:([\w.]+)/,
  // 歌单链接
  listDetailLink: /^.+\/playlist(?:_detail)?\/(\d+)(?:\?.*|&.*$|#.*$|$)/,
  // 时间标签
  timeTag: /^\[(\d{1,2}:.*\d{1,4})\]\s*(\S+(?:\s+\S+)*)?\s*/,
  // 歌词标签
  lyricTag: /\[(ver|ti|ar|al|offset|by|kuwo):\s*(\S+(?:\s+\S+)*)\s*\]/,
};

// 归一化封面 URL
// 处理 // 前缀与协议白名单，避免将可用 http 强制升级为 https 后触发证书错误。
export function normalizeCoverUrl(url: string, fallback?: string): string {
  const value = (url ?? '').trim();
  if (value.length === 0) {
    return fallback ?? '';
  }
  // 咪咕部分接口返回类似 /data/oss/resource/... 的相对路径，这里补全为完整 http URL
  if (value.startsWith('/data/oss/')) {
    return `http://d.musicapp.migu.cn${value}`;
  }
  // 处理 // 前缀（默认走 https，HarmonyOS 默认拦截 HTTP 明文流量）
  if (value.startsWith('//')) {
    return `https:${value}`;
  }
  // http 明文链接在部分 HarmonyOS 设备上可能被拦截，但保留原样避免部分 CDN 无 HTTPS
  if (value.startsWith('https://') || value.startsWith('/')) {
    return value;
  }
  if (value.startsWith('http://')) {
    return value;
  }
  // 其他非法格式
  return fallback ?? '';
}
