/**
 * QQ音乐 SDK - 工具函数
 */
import { sha1 as computeSHA1 } from '../../../../../utils/CryptoUtils';

// SHA1哈希
export function sha1(input: string): string {
  return computeSHA1(input);
}

// 签名常量
const PART_1_INDEXES = [23, 14, 6, 36, 16, 40, 7, 19];
const PART_2_INDEXES = [16, 1, 32, 12, 19, 27, 8, 5];
const SCRAMBLE_VALUES = [89, 39, 179, 150, 218, 82, 58, 252, 177, 52, 186, 123, 120, 64, 242, 133, 143, 161, 121, 179];

/**
 * ZZC签名
 */
export async function zzcSign(text: string): Promise<string> {
  const hash = sha1(text);
  const part1 = PART_1_INDEXES.map(idx => hash[idx]).join('');
  const part2 = PART_2_INDEXES.map(idx => hash[idx]).join('');

  const part3 = SCRAMBLE_VALUES.map((value, i) => {
    const hexPair = hash.slice(i * 2, i * 2 + 2);
    return value ^ parseInt(hexPair, 16);
  });

  const b64Part = base64EncodeChars(part3).replace(/[\\/+=]/g, '');
  return `zzc${part1}${b64Part}${part2}`.toLowerCase();
}

/**
 * Base64编码
 */
function base64EncodeChars(chars: number[]): string {
  let str = '';
  const chars6bit = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  let i = 0;
  while (i < chars.length) {
    const c1 = chars[i++];
    let c2: number = 0;
    let c3: number = 0;

    if (i < chars.length) {
      c2 = chars[i++];
    } else {
      str += chars6bit.charAt(c1 >> 2);
      str += chars6bit.charAt((c1 & 3) << 4);
      break;
    }

    if (i < chars.length) {
      c3 = chars[i++];
    } else {
      str += chars6bit.charAt(c1 >> 2);
      str += chars6bit.charAt(((c1 & 3) << 4) | ((c2 & 240) >> 4));
      str += chars6bit.charAt((c2 & 15) << 2);
      break;
    }

    str += chars6bit.charAt(c1 >> 2);
    str += chars6bit.charAt(((c1 & 3) << 4) | ((c2 & 240) >> 4));
    str += chars6bit.charAt(((c2 & 15) << 2) | ((c3 & 192) >> 6));
    str += chars6bit.charAt(c3 & 63);
  }

  return str;
}

/**
 * 格式化歌手名称
 */
export function formatSingerName(singers: SingerInfo[] | string, key: string = 'name'): string {
  if (Array.isArray(singers)) {
    return singers.map((s: SingerInfo | string): string => {
      if (typeof s === 'string') {
        return s;
      }
      return s.name;
    }).join('、');
  }
  return singers;
}

export interface SingerInfo {
  name: string;
  mid?: string;
}
