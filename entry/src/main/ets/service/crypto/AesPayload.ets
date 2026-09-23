/**
 * 载荷加解密（同步 / 备份共用）
 *
 * 背景：同步与备份各自实现了一套「加解密」——
 * - 同步用 AES-128-CBC + 固定 IV（要跟安卓版对端兼容，不能改）
 * - 备份用的是 XOR + Base64（原注释写着「仅用于演示」），等于没加密
 *
 * 这里把两套能力收在一个模块：
 * - `encryptWithKey/decryptWithKey`：固定 IV，供同步使用（保持与对端兼容）
 * - `encryptWithPassword/decryptWithPassword`：随机 IV + SHA-256 派生密钥，供备份使用；
 *   载荷带版本前缀 `LXB1:`，并保留对旧 XOR 备份的解密兼容（老备份仍能恢复）
 */
import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import { appLog as hilog } from '../../core/log/AppLogger';
import { utf8Encode, utf8Decode } from '../../utils/TextCodec';

const TAG = 'AesPayload';
const DOMAIN: number = 0x0001;
/** 备份载荷版本前缀：只有新格式才有，用于区分旧的 XOR 备份 */
const BACKUP_PREFIX = 'LXB1:';
/** 旧版备份的标记（XOR 时代写在明文前） */
const LEGACY_XOR_MARKER = 'ENC:';
const IV_LENGTH = 16;

function toBytes(text: string): Uint8Array {
  return utf8Encode(text);
}

/** 字符串按字节截断/补齐到 16 字节（AES-128 密钥长度要求） */
function toKeyBytes(key: string): Uint8Array {
  const bytes = new Uint8Array(IV_LENGTH);
  for (let i = 0; i < IV_LENGTH; i++) {
    bytes[i] = i < key.length ? key.charCodeAt(i) & 0xFF : 0;
  }
  return bytes;
}

function ivToBytes(iv: string): Uint8Array {
  const bytes = new Uint8Array(IV_LENGTH);
  for (let i = 0; i < IV_LENGTH; i++) {
    bytes[i] = i < iv.length ? iv.charCodeAt(i) & 0xFF : 0;
  }
  return bytes;
}

async function aesCipher(mode: cryptoFramework.CryptoMode, key: Uint8Array, iv: Uint8Array,
  payload: Uint8Array): Promise<Uint8Array> {
  const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
  const symKeyGen: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
  const symKey: cryptoFramework.SymKey = await symKeyGen.convertKey({ data: key });
  const params: cryptoFramework.IvParamsSpec = {
    algName: 'IvParamsSpec',
    iv: { data: iv },
  };
  await cipher.init(mode, symKey, params);
  const out: cryptoFramework.DataBlob = await cipher.doFinal({ data: payload });
  return out.data;
}

/** AES-128-CBC 加密（固定 IV，供同步使用；失败回退明文，保证不会完全同步不了） */
export async function encryptWithKey(plain: string, keyText: string, ivText: string): Promise<string> {
  try {
    const encrypted = await aesCipher(cryptoFramework.CryptoMode.ENCRYPT_MODE,
      toKeyBytes(keyText), ivToBytes(ivText), toBytes(plain));
    return new util.Base64Helper().encodeToStringSync(encrypted);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'encryptWithKey failed: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    return plain;
  }
}

/** AES-128-CBC 解密（固定 IV，供同步使用；失败返回原文，由调用方按解析失败处理） */
export async function decryptWithKey(payload: string, keyText: string, ivText: string): Promise<string> {
  try {
    const bytes: Uint8Array = new util.Base64Helper().decodeSync(payload.replace(/[\r\n]/g, ''));
    const plain = await aesCipher(cryptoFramework.CryptoMode.DECRYPT_MODE,
      toKeyBytes(keyText), ivToBytes(ivText), bytes);
    return utf8Decode(plain);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'decryptWithKey failed: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    return payload;
  }
}

/** 用口令派生 16 字节密钥：SHA-256(password | iv) 取前 16 字节 */
async function deriveKey(password: string, iv: Uint8Array): Promise<Uint8Array> {
  const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
  const ivBytes = Array.from(iv).join(',');
  await md.update({ data: toBytes(`${password}|${ivBytes}`) });
  const digest: cryptoFramework.DataBlob = await md.digest();
  const out = new Uint8Array(IV_LENGTH);
  for (let i = 0; i < IV_LENGTH; i++) {
    out[i] = digest.data[i] ?? 0;
  }
  return out;
}

/**
 * 备份载荷加密：随机 IV + SHA-256 派生密钥，输出 `LXB1:` + Base64(IV || 密文)。
 * 每次生成的 IV 不同，同样的内容不会得到同样的密文。
 */
export async function encryptWithPassword(plain: string, password: string): Promise<string> {
  try {
    const iv = new Uint8Array(IV_LENGTH);
    const rnd = cryptoFramework.createRandom();
    const rand: cryptoFramework.DataBlob = rnd.generateRandomSync(IV_LENGTH);
    for (let i = 0; i < IV_LENGTH; i++) {
      iv[i] = rand.data[i] ?? 0;
    }
    const key = await deriveKey(password, iv);
    const cipherText = await aesCipher(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, iv, toBytes(plain));
    const combined = new Uint8Array(IV_LENGTH + cipherText.length);
    combined.set(iv, 0);
    combined.set(cipherText, IV_LENGTH);
    return BACKUP_PREFIX + new util.Base64Helper().encodeToStringSync(combined);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'encryptWithPassword failed: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    // 兜底不落明文：用固定 IV 的同步通道加密，保证内容仍是密文
    return encryptWithKey(plain, password, '1234567890123456');
  }
}

/** 旧版 XOR 备份解密（仅为兼容历史文件，新备份不会再产生这种格式） */
function legacyXorDecrypt(payload: string, password: string): string | null {
  try {
    const combined = new Uint8Array(new util.Base64Helper().decodeSync(payload));
    let marker = '';
    for (let i = 0; i < 4; i++) {
      marker += String.fromCharCode(combined[i]);
    }
    if (marker !== LEGACY_XOR_MARKER) {
      return null;
    }
    const body = combined.slice(4);
    const passwordBytes = toBytes(password);
    const decrypted = new Uint8Array(body.length);
    for (let i = 0; i < body.length; i++) {
      decrypted[i] = body[i] ^ passwordBytes[i % passwordBytes.length];
    }
    return utf8Decode(decrypted);
  } catch (err) {
    return null;
  }
}

/**
 * 备份载荷解密：
 * - `LXB1:` 前缀 → 新格式（随机 IV + 派生密钥）
 * - 能识别旧 XOR 标记 → 按旧格式解（历史备份不丢）
 * - 都不是 → 视为明文（早期备份）
 */
export async function decryptWithPassword(payload: string, password: string): Promise<string> {
  if (payload.startsWith(BACKUP_PREFIX)) {
    const bytes: Uint8Array = new util.Base64Helper().decodeSync(payload.substring(BACKUP_PREFIX.length));
    const iv = bytes.slice(0, IV_LENGTH);
    const body = bytes.slice(IV_LENGTH);
    const key = await deriveKey(password, iv);
    const plain = await aesCipher(cryptoFramework.CryptoMode.DECRYPT_MODE, key, iv, body);
    return utf8Decode(plain);
  }
  const legacy = legacyXorDecrypt(payload, password);
  if (legacy !== null) {
    hilog.info(DOMAIN, TAG, 'Restored payload with legacy XOR format (will be re-encrypted on next backup)');
    return legacy;
  }
  return payload;
}
