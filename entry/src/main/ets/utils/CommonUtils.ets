import {
  formatClockWithHours,
  formatPlayCount as formatPlayCountCore,
  parsePlayTimeText,
} from './FormatTools';
import { playCountUnits } from '../service/LocalizationService';

// 格式化播放时间 - 对应 src/utils/format.ts（实现统一在 FormatTools）
export function formatPlayTime(time: number): string {
  return formatClockWithHours(time);
}

// 时间文本 → 秒（实现统一在 FormatTools）
export function parsePlayTime(timeStr: string): number {
  return parsePlayTimeText(timeStr);
}





// 生成随机ID
export { generateId } from './Utils';




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
  // 单位按语言选择（中文 万/亿，英文 K/M），量级与文案一起换
  return formatPlayCountCore(num, playCountUnits());
}


// 格式化文件大小（紧凑写法，规则统一在 utils/FormatTools）
export { formatBytesCompact as sizeFormate } from './FormatTools';

// 去除字符串空格和特殊字符
export function trimSpecialChars(str: string): string {
  if (!str) return '';
  return str.replace(/\s|'|\.|,|，|&|"|、|\(|\)|（|）|`|~|-|<|>|\||\/|\]|\[|!|！/g, '');
}



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
