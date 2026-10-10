/**
 * 加密工具模块
 * 使用纯 ArkTS 实现 SHA1 和 MD5（不依赖原生 crypto API）
 */

/**
 * 获取十六进制字符（避免字符串索引访问）
 */
function getHexChar(index: number): string {
  switch (index) {
    case 0: return '0';
    case 1: return '1';
    case 2: return '2';
    case 3: return '3';
    case 4: return '4';
    case 5: return '5';
    case 6: return '6';
    case 7: return '7';
    case 8: return '8';
    case 9: return '9';
    case 10: return 'a';
    case 11: return 'b';
    case 12: return 'c';
    case 13: return 'd';
    case 14: return 'e';
    case 15: return 'f';
    default: return '0';
  }
}

/**
 * 十六进制字符表（避免字符串索引访问）
 */
const HEX_CHARS: string[] = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f'];

/**
 * 左旋转（模块级函数，避免嵌套）
 */
function leftRotate(value: number, shift: number): number {
  return (value << shift) | (value >>> (32 - shift));
}

/**
 * 追加十六进制字符到结果（避免字符串索引访问）
 */
function appendHex(result: string, value: number, shift1: number, shift2: number): string {
  result += HEX_CHARS[(value >> shift1) & 0xF];
  result += HEX_CHARS[(value >> shift2) & 0xF];
  return result;
}

/**
 * SHA1 哈希计算
 */
export function sha1(input: string): string {

  const bytes: number[] = [];
  for (let i = 0; i < input.length; i++) {
    bytes.push(input.charCodeAt(i) & 0xFF);
  }

  const originalLength = bytes.length * 8;
  bytes.push(0x80);
  while ((bytes.length * 8 + 64) % 512 !== 0) {
    bytes.push(0x00);
  }

  for (let i = 0; i < 8; i++) {
    bytes.push((originalLength >>> (56 - i * 8)) & 0xFF);
  }

  let h0 = 0x67452301;
  let h1 = 0xEFCDAB89;
  let h2 = 0x98BADCFE;
  let h3 = 0x10325476;
  let h4 = 0xC3D2E1F0;

  for (let i = 0; i < bytes.length; i += 64) {
    const chunk = bytes.slice(i, i + 64);
    const words: number[] = [];

    for (let j = 0; j < 16; j++) {
      words[j] = ((chunk[j * 4] << 24) | (chunk[j * 4 + 1] << 16) |
                  (chunk[j * 4 + 2] << 8) | chunk[j * 4 + 3]) >>> 0;
    }

    for (let j = 16; j < 80; j++) {
      words[j] = leftRotate(words[j - 3] ^ words[j - 8] ^ words[j - 14] ^ words[j - 16], 1);
    }

    let a = h0;
    let b = h1;
    let c = h2;
    let d = h3;
    let e = h4;

    for (let j = 0; j < 80; j++) {
      let f: number;
      let k: number;

      if (j < 20) {
        f = (b & c) | ((~b) & d);
        k = 0x5A827999;
      } else if (j < 40) {
        f = b ^ c ^ d;
        k = 0x6ED9EBA1;
      } else if (j < 60) {
        f = (b & c) | (b & d) | (c & d);
        k = 0x8F1BBCDC;
      } else {
        f = b ^ c ^ d;
        k = 0xCA62C1D6;
      }

      f = f >>> 0;
      const temp = (leftRotate(a, 5) + f + e + k + words[j]) >>> 0;
      e = d;
      d = c;
      c = leftRotate(b, 30);
      b = a;
      a = temp;
    }

    h0 = (h0 + a) >>> 0;
    h1 = (h1 + b) >>> 0;
    h2 = (h2 + c) >>> 0;
    h3 = (h3 + d) >>> 0;
    h4 = (h4 + e) >>> 0;
  }

  let result = '';
  const values = [h0, h1, h2, h3, h4];
  for (let v = 0; v < values.length; v++) {
    const value = values[v];
    for (let i = 0; i < 4; i++) {
      result += getHexChar((value >> (24 - i * 8)) & 0xF);
      result += getHexChar((value >> (20 - i * 8)) & 0xF);
    }
  }

  return result;
}

/**
 * MD5 哈希计算（字节版：酷狗指纹签名需要直接对二进制拼接结果取 MD5）
 */
export function md5Bytes(input: Uint8Array): string {

  const bytes: number[] = [];
  for (let i = 0; i < input.length; i++) {
    bytes.push(input[i]);
  }

  const originalLength = bytes.length * 8;
  bytes.push(0x80);
  while ((bytes.length * 8 + 64) % 512 !== 0) {
    bytes.push(0x00);
  }

  for (let i = 0; i < 8; i++) {
    bytes.push((originalLength >>> (i * 8)) & 0xFF);
  }

  let a = 0x67452301;
  let b = 0xEFCDAB89;
  let c = 0x98BADCFE;
  let d = 0x10325476;

  const s: number[] = [
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
  ];

  const k: number[] = [
    0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
    0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
    0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
    0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
    0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
    0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
    0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
    0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
    0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
    0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
    0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
    0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
    0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
    0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
    0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
    0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
  ];

  for (let i = 0; i < bytes.length; i += 64) {
    const chunk = bytes.slice(i, i + 64);
    const m: number[] = [];

    for (let j = 0; j < 16; j++) {
      m[j] = ((chunk[j * 4 + 3] << 24) | (chunk[j * 4 + 2] << 16) |
              (chunk[j * 4 + 1] << 8) | chunk[j * 4]) >>> 0;
    }

    let aa = a;
    let bb = b;
    let cc = c;
    let dd = d;

    for (let j = 0; j < 64; j++) {
      let f: number;
      let g: number;

      if (j < 16) {
        f = (b & c) | ((~b) & d);
        g = j;
      } else if (j < 32) {
        f = (d & b) | ((~d) & c);
        g = (5 * j + 1) % 16;
      } else if (j < 48) {
        f = b ^ c ^ d;
        g = (3 * j + 5) % 16;
      } else {
        f = c ^ (b | (~d));
        g = (7 * j) % 16;
      }

      f = f >>> 0;
      const temp = d;
      d = c;
      c = b;
      b = (b + leftRotate((a + f + k[j] + m[g]) >>> 0, s[j])) >>> 0;
      a = temp;
    }

    a = (a + aa) >>> 0;
    b = (b + bb) >>> 0;
    c = (c + cc) >>> 0;
    d = (d + dd) >>> 0;
  }

  let result = '';
  const values = [a, b, c, d];
  for (let v = 0; v < values.length; v++) {
    const value = values[v];
    for (let i = 0; i < 4; i++) {
      result += getHexChar((value >> (i * 8)) & 0xF);
      result += getHexChar((value >> (i * 8 + 4)) & 0xF);
    }
  }

  return result;
}

/**
 * MD5 哈希计算（字符串版：按字节解释，等价于 md5Bytes 的便捷入口）
 */
export function md5(input: string): string {
  const bytes = new Uint8Array(input.length);
  for (let i = 0; i < input.length; i++) {
    bytes[i] = input.charCodeAt(i) & 0xFF;
  }
  return md5Bytes(bytes);
}

/**
 * Base64 编码
 */
export function base64Encode(data: string | number[]): string {
  let bytes: number[];
  if (typeof data === 'string') {
    bytes = [];
    for (let i = 0; i < data.length; i++) {
      bytes.push(data.charCodeAt(i));
    }
  } else {
    bytes = data;
  }
  
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let result = '';
  let i = 0;
  
  while (i < bytes.length) {
    const c1 = bytes[i++];
    let c2: number = 0;
    let c3: number = 0;
    
    if (i < bytes.length) {
      c2 = bytes[i++];
    } else {
      result += chars.charAt((c1 >> 2) & 0x3F);
      result += chars.charAt(((c1 & 3) << 4) & 0x3F);
      break;
    }
    
    if (i < bytes.length) {
      c3 = bytes[i++];
    } else {
      result += chars.charAt((c1 >> 2) & 0x3F);
      result += chars.charAt((((c1 & 3) << 4) | ((c2 >> 4) & 0x0F)) & 0x3F);
      result += chars.charAt(((c2 & 0x0F) << 2) & 0x3F);
      break;
    }
    
    result += chars.charAt((c1 >> 2) & 0x3F);
    result += chars.charAt((((c1 & 3) << 4) | ((c2 >> 4) & 0x0F)) & 0x3F);
    result += chars.charAt((((c2 & 0x0F) << 2) | ((c3 >> 6) & 0x03)) & 0x3F);
    result += chars.charAt(c3 & 0x3F);
  }
  
  return result;
}

/**
 * Base64 解码
 */
export function base64Decode(str: string): number[] {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const result: number[] = [];
  let buffer: number = 0;
  let bitsCollected: number = 0;
  
  for (let i = 0; i < str.length; i++) {
    const c = str.charAt(i);
    if (c === '=') break;
    
    const idx = chars.indexOf(c);
    if (idx === -1) continue;
    
    buffer = ((buffer << 6) | idx) & 0xFFFFFF;
    bitsCollected += 6;
    
    if (bitsCollected >= 8) {
      bitsCollected -= 8;
      result.push(((buffer >> bitsCollected) & 0xFF));
    }
  }
  
  return result;
}


/**
 * 字节数组转字符串
 */
export function bytesToString(bytes: number[]): string {
  let result = '';
  for (let i = 0; i < bytes.length; i++) {
    result += String.fromCharCode(bytes[i]);
  }
  return result;
}

