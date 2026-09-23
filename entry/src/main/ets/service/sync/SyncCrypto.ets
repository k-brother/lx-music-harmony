/**
 * 同步数据加解密（AES-128-CBC + 标准 Base64）
 *
 * 具体实现统一在 service/crypto/AesPayload：同步用的是「固定 IV + 口令当密钥」通道
 * （必须与安卓版对端保持一致，不能随机 IV），备份用的是「随机 IV + SHA-256 派生密钥」通道。
 * 这里只保留「同步的固定 IV 约定」这一层语义。
 */
import { encryptWithKey, decryptWithKey } from '../crypto/AesPayload';

const TAG = 'SyncCrypto';
/** 固定 IV：需要与对端（安卓版）保持一致，不能随机 */
const SYNC_IV = '1234567890123456';

/** 加密：失败时返回明文（调用方无需感知） */
export async function encryptPayload(data: string, key: string): Promise<string> {
  return encryptWithKey(data, key, SYNC_IV);
}

/** 解密：密文非法时返回原文（调用方按 JSON 解析失败处理） */
export async function decryptPayload(encryptedData: string, key: string): Promise<string> {
  return decryptWithKey(encryptedData, key, SYNC_IV);
}
