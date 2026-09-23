// 格式化播放时间 - 对应 src/utils/format.ts
export function formatPlayTime(time: number): string {
  if (isNaN(time) || time < 0) return '00:00';
  const mins = Math.floor(time / 60);
  const secs = Math.floor(time % 60);
  return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
}

// 格式化播放时间（从字符串格式如 "03:55" 转秒数）
export function parsePlayTime(timeStr: string): number {
  if (!timeStr) return 0;
  const parts = timeStr.split(':');
  let seconds = 0;
  let multiplier = 1;
  for (let i = parts.length - 1; i >= 0; i--) {
    seconds += parseInt(parts[i]) * multiplier;
    multiplier *= 60;
  }
  return seconds;
}

// 格式化播放时间（带小时）
export function formatPlayTime2(time: number): string {
  if (isNaN(time) || time < 0) return '00:00:00';
  const hours = Math.floor(time / 3600);
  const mins = Math.floor((time % 3600) / 60);
  const secs = Math.floor(time % 60);
  if (hours > 0) {
    return `${hours.toString().padStart(2, '0')}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }
  return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
}

// 格式化数字（带单位）
export function formatNumber(num: number): string {
  if (num >= 100000000) {
    return (num / 100000000).toFixed(1) + '亿';
  } else if (num >= 10000) {
    return (num / 10000).toFixed(1) + '万';
  }
  return num.toString();
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
export function generateId(): string {
  return Date.now().toString(36) + Math.random().toString(36).substring(2);
}

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

// 格式化播放数量
export function formatPlayCount(num: number): string {
  if (num > 100000000) {
    return (num / 10000000).toFixed(1) + '亿';
  }
  if (num > 10000) {
    return (num / 1000).toFixed(1) + '万';
  }
  return num.toString();
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
