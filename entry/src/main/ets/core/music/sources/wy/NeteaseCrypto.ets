/**
 * 网易云 weapi / linuxapi 加密（对齐 Binaryify NeteaseCloudMusicApi util/crypto.js）
 */
import cryptoFramework from '@ohos.security.cryptoFramework';
import { utf8Encode } from '../../../../utils/TextCodec';

const PRESET_KEY = '0CoJUm6Qyw8W8jud';
const IV_STR = '0102030405060708';
const LINUX_API_KEY = 'rFgB&h#%2?^eDg:Q';

/** RSA 公钥模数 n（1024 bit，大端十六进制） */
const RSA_N_HEX =
  'e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7';

function hexToBigInt(hex: string): bigint {
  return BigInt('0x' + hex);
}

const RSA_N: bigint = hexToBigInt(RSA_N_HEX);
const RSA_E: bigint = BigInt(65537);

function modPow(base: bigint, exp: bigint, mod: bigint): bigint {
  let result = BigInt(1);
  let b = base % mod;
  let e = exp;
  while (e > BigInt(0)) {
    if (e % BigInt(2) === BigInt(1)) {
      result = (result * b) % mod;
    }
    e = e >> BigInt(1);
    b = (b * b) % mod;
  }
  return result;
}

function bytesToBase64(data: Uint8Array): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let out = '';
  const len = data.length;
  let i = 0;
  while (i < len) {
    const a = data[i++];
    const b = i < len ? data[i++] : 0;
    const c = i < len ? data[i++] : 0;
    const triplet = (a << 16) | (b << 8) | c;
    out += chars.charAt((triplet >> 18) & 63);
    out += chars.charAt((triplet >> 12) & 63);
    out += i - 2 < len ? chars.charAt((triplet >> 6) & 63) : '=';
    out += i - 1 < len ? chars.charAt(triplet & 63) : '=';
  }
  return out;
}

function bytesToHexUpper(data: Uint8Array): string {
  const HEX = '0123456789ABCDEF';
  let s = '';
  for (let i = 0; i < data.length; i++) {
    const v = data[i];
    s += HEX.charAt((v >> 4) & 15);
    s += HEX.charAt(v & 15);
  }
  return s;
}

async function importAes128KeyUtf8(keyStr: string): Promise<cryptoFramework.SymKey> {
  try {
    const keyData = utf8Encode(keyStr);
    const keyBlob: cryptoFramework.DataBlob = { data: keyData };
    const symKeyGen = cryptoFramework.createSymKeyGenerator('AES128');
    return symKeyGen.convertKey(keyBlob);
  } catch (e) {
    throw new Error('Failed to import AES key: ' + (e instanceof Error ? e.message : String(e)));
  }
}

async function aes128CbcPkcs7Encrypt(plain: Uint8Array, keyStr: string, ivStr: string): Promise<Uint8Array> {
  try {
    const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
    const symKey = await importAes128KeyUtf8(keyStr);
    const ivBlob: cryptoFramework.DataBlob = { data: utf8Encode(ivStr) };
    const ivParams: cryptoFramework.IvParamsSpec = { algName: 'IvParamsSpec', iv: ivBlob };
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, ivParams);
    const inBlob: cryptoFramework.DataBlob = { data: plain };
    const outBlob: cryptoFramework.DataBlob = await cipher.doFinal(inBlob);
    return outBlob.data;
  } catch (e) {
    throw new Error('AES CBC encryption failed: ' + (e instanceof Error ? e.message : String(e)));
  }
}

async function aes128EcbPkcs7Encrypt(plain: Uint8Array, keyStr: string): Promise<Uint8Array> {
  try {
    const cipher = cryptoFramework.createCipher('AES128|ECB|PKCS7');
    const symKey = await importAes128KeyUtf8(keyStr);
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, null);
    const inBlob: cryptoFramework.DataBlob = { data: plain };
    const outBlob: cryptoFramework.DataBlob = await cipher.doFinal(inBlob);
    return outBlob.data;
  } catch (e) {
    throw new Error('AES ECB encryption failed: ' + (e instanceof Error ? e.message : String(e)));
  }
}

/** 与 Binaryify weapi 一致：16 位 base62 字符作第二层 AES 密钥 */
const BASE62 =
  'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

function randomSecretKeyBase62_16(): string {
  let s = '';
  for (let i = 0; i < 16; i++) {
    s += BASE62.charAt(Math.floor(Math.random() * 62));
  }
  return s;
}

function rsaNoPaddingEncryptSecret(secretUtf8: string): string {
  const sk = utf8Encode(secretUtf8);
  const block = new Uint8Array(128);
  const n = sk.length;
  for (let i = 0; i < n; i++) {
    block[128 - n + i] = sk[n - 1 - i];
  }
  let m = BigInt(0);
  for (let i = 0; i < 128; i++) {
    m = (m << BigInt(8)) | BigInt(block[i]);
  }
  const c = modPow(m, RSA_E, RSA_N);
  const out = new Uint8Array(128);
  let x = c;
  for (let i = 127; i >= 0; i--) {
    out[i] = Number(x & BigInt(255));
    x = x >> BigInt(8);
  }
  return bytesToHexUpper(out);
}

/** weapi 请求体（扁平 JSON 字段） */
export type WeapiJsonObject = Record<string, string | number | boolean | null>;

/**
 * weapi：返回 URL 表单字段 params（Base64 密文）与 encSecKey（十六进制大写）
 * 对齐 NeteaseCloudMusicApi util/crypto.js：首层 AES 明文为 UTF-8(JSON)，非 Base64(JSON)。
 */
export async function neteaseWeapi(object: WeapiJsonObject): Promise<WeapiForm> {
  const text = JSON.stringify(object);
  const first = await aes128CbcPkcs7Encrypt(utf8Encode(text), PRESET_KEY, IV_STR);
  const firstB64 = bytesToBase64(first);
  const secretKey = randomSecretKeyBase62_16();
  const second = await aes128CbcPkcs7Encrypt(utf8Encode(firstB64), secretKey, IV_STR);
  const params = bytesToBase64(second);
  const encSecKey = rsaNoPaddingEncryptSecret(secretKey);
  return { params, encSecKey };
}

export interface WeapiForm {
  params: string;
  encSecKey: string;
}

/**
 * linuxapi：返回表单字段 eparams（十六进制大写）
 */
export async function neteaseLinuxapi(object: WeapiJsonObject): Promise<LinuxapiForm> {
  const text = JSON.stringify(object);
  return neteaseLinuxapiFromJsonString(text);
}

/** linuxapi：直接传入完整 JSON 字符串（用于含嵌套 params 的请求体） */
export async function neteaseLinuxapiFromJsonString(json: string): Promise<LinuxapiForm> {
  const enc = await aes128EcbPkcs7Encrypt(utf8Encode(json), LINUX_API_KEY);
  return { eparams: bytesToHexUpper(enc) };
}

export interface LinuxapiForm {
  eparams: string;
}

export function buildWeapiFormBody(form: WeapiForm): string {
  return `params=${encodeURIComponent(form.params)}&encSecKey=${encodeURIComponent(form.encSecKey)}`;
}

export function buildLinuxapiFormBody(form: LinuxapiForm): string {
  return `eparams=${encodeURIComponent(form.eparams)}`;
}
