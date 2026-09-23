/**
 * 同步数据加解密（AES-128-CBC/PKCS7 + 标准 Base64）
 *
 * 从 SyncService 抽出后顺便去掉手写的 Base64 编解码（原来编码 + 解码各 40 行），
 * 改用系统 `util.Base64Helper`：等价的标准 Base64，少 80 行自维护代码。
 * 加密失败时回退为明文（与拆分前行为一致），保证不会因为加密问题完全同步不了。
 */
import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import { appLog as hilog } from '../../core/log/AppLogger';
import { utf8Encode, utf8Decode } from '../../utils/TextCodec';

const TAG = 'SyncCrypto';
const DOMAIN: number = 0x0001;
/** 固定 IV：需要与对端（安卓版）保持一致，不能随机 */
const SYNC_IV = '1234567890123456';
const DEFAULT_KEY = 'default-sync-key';

function keyBytes(key: string): Uint8Array {
  const value = key.length > 0 ? key : DEFAULT_KEY;
  const bytes = new Uint8Array(value.length);
  for (let i = 0; i < value.length; i++) {
    bytes[i] = value.charCodeAt(i) & 0xFF;
  }
  return bytes;
}

function ivBytes(): Uint8Array {
  const bytes = new Uint8Array(SYNC_IV.length);
  for (let i = 0; i < SYNC_IV.length; i++) {
    bytes[i] = SYNC_IV.charCodeAt(i) & 0xFF;
  }
  return bytes;
}

/** 加密：失败时返回明文（调用方无需感知） */
export async function encryptPayload(data: string, key: string): Promise<string> {
  try {
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
    const keyBlob: cryptoFramework.DataBlob = { data: keyBytes(key) };
    const ivParamsSpec: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: { data: ivBytes() },
    };
    const symKeyGen: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
    const symKey: cryptoFramework.SymKey = await symKeyGen.convertKey(keyBlob);
    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, ivParamsSpec);
    const encrypted: cryptoFramework.DataBlob = await cipher.doFinal({ data: utf8Encode(data) });
    return new util.Base64Helper().encodeToStringSync(encrypted.data);
  } catch (err) {
    hilog.error(DOMAIN, TAG, '加密数据失败: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    return data;
  }
}

/** 解密：密文非法时返回原文（调用方按 JSON 解析失败处理） */
export async function decryptPayload(encryptedData: string, key: string): Promise<string> {
  try {
    const clean = encryptedData.replace(/[\r\n]/g, '');
    const encryptedBytes: Uint8Array = new util.Base64Helper().decodeSync(clean);
    const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
    const keyBlob: cryptoFramework.DataBlob = { data: keyBytes(key) };
    const ivParamsSpec: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: { data: ivBytes() },
    };
    const symKeyGen: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
    const symKey: cryptoFramework.SymKey = await symKeyGen.convertKey(keyBlob);
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, ivParamsSpec);
    const decrypted: cryptoFramework.DataBlob = await cipher.doFinal({ data: encryptedBytes });
    return utf8Decode(decrypted.data);
  } catch (err) {
    hilog.error(DOMAIN, TAG, '解密数据失败: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    return encryptedData;
  }
}
