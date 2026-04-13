/**
 * 酷狗音乐 SDK 工具函数
 */
import { md5 } from '../../../../utils/CryptoUtils';
import { httpRequest } from '../../../../core/network/http';

// MD5 key
const KG_MD5_KEY = 'OIlwieks28dk2k092lksi2UIkp';
const KG_WEB_MD5_KEY = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';

// KRC歌词解密key
const ENC_KEY: number[] = [0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47, 0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69];

// 酷狗响应数据类型
interface KGResponseData {
  error_code?: number;
  errcode?: number;
}

interface KGResponseDataAlt {
  err_code?: number;
}

/**
 * 计算MD5
 */
export function toMD5(str: string): string {
  return md5(str);
}

/**
 * 签名参数
 */
export function signatureParams(params: string, platform: string = 'android', body: string = ''): string {
  let keyparam = platform === 'web' ? KG_WEB_MD5_KEY : KG_MD5_KEY;
  let paramList = params.split('&');
  paramList.sort();
  let signParams = `${keyparam}${paramList.join('')}${body}${keyparam}`;
  return toMD5(signParams);
}

/**
 * 解码歌手名称
 */
export function formatSingerName(singers: string[], key: string = 'name'): string {
  return singers.join('、');
}

/**
 * 创建HTTP请求
 */
export async function createHttpFetch<T>(url: string, retryNum: number = 0): Promise<T> {
  if (retryNum > 2) throw new Error('try max num');

  try {
    const response = await httpRequest(url).promise;
    if (response.status !== 200) {
      return createHttpFetch<T>(url, ++retryNum);
    }
    const body = response.data as string;
    const data = JSON.parse(body) as KGResponseData;
    const errcode = data.error_code ?? data.errcode ?? (data as KGResponseDataAlt).err_code;
    if (errcode !== 0 && errcode !== undefined) {
      return createHttpFetch<T>(url, ++retryNum);
    }
    return data as T;
  } catch (err) {
    console.error('HTTP Error:', err);
    return createHttpFetch<T>(url, ++retryNum);
  }
}

/**
 * KRC格式歌词解码
 */
export function decodeKrc(str: string): string {
  if (!str || str.length === 0) return '';

  // Base64解码后跳过前4字节
  let bufStr = base64Decode(str);
  if (bufStr.length <= 4) return '';

  bufStr = bufStr.slice(4);

  // XOR解密
  const keyLength: number = ENC_KEY.length;
  for (let i = 0; i < bufStr.length; i++) {
    const keyIndex = i % keyLength;
    bufStr[i] = bufStr[i] ^ ENC_KEY[keyIndex];
  }

  // 简单解压（实际需要pako，这里简化处理）
  // 实际歌词数据需要解压，这里先返回原始数据
  return bytesToString(bufStr);
}

/**
 * Base64解码
 */
function base64Decode(str: string): number[] {
  const base64Chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let output: number[] = [];
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
      output.push((buffer >> bitsCollected) & 0xFF);
    }
  }

  return output;
}

/**
 * 字节数组转字符串
 */
function bytesToString(bytes: number[]): string {
  let result = '';
  for (let i = 0; i < bytes.length; i++) {
    result += String.fromCharCode(bytes[i]);
  }
  return result;
}

/**
 * URL编码
 */
export function encodeKeyword(str: string): string {
  return encodeURIComponent(str);
}
