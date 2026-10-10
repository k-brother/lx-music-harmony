/**
 * 敏感凭据存储（华为官方推荐通道：AssetStoreKit）
 *
 * 为什么不放 preferences：偏好文件是明文落盘，口令类（备份密码、WebDAV 密码）写在里面
 * 既不符合官方的"敏感资产用资产存储"，也有上架合规风险。这里统一走 `@kit.AssetStoreKit`：
 * 由系统托管加密与访问控制（本工程取 DEVICE_FIRST_UNLOCKED：开机首次解锁后即可读，
 * 与备份/同步这类后台任务的时机匹配）。
 *
 * 约定：
 * - 调用方只传 alias 与口令，不关心底层编码；
 * - 空串 = 删除该凭据（避免"空口令记录"残留）；
 * - 读不到（24000002）返回空串，不抛异常 —— 凭据缺失属于正常状态。
 */
import { asset } from '@kit.AssetStoreKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import { appLog as hilog } from '../core/log/AppLogger';
import { utf8Encode, utf8Decode } from '../utils/TextCodec';

const TAG = 'CredentialStore';
const DOMAIN = 0x0003;

/** 备份口令（加密备份用） */
export const CREDENTIAL_BACKUP_PASSWORD: string = 'lxmusic.backup.password';
/** WebDAV 口令 */
export const CREDENTIAL_WEBDAV_PASSWORD: string = 'lxmusic.webdav.password';

/** Base error codes of @kit.AssetStoreKit */
const ERR_NOT_FOUND: number = 24000002;
const ERR_ALREADY_EXISTS: number = 24000003;

function aliasQuery(alias: string): asset.AssetMap {
  const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
  query.set(asset.Tag.ALIAS, utf8Encode(alias));
  query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
  return query;
}

function describe(err: Object): string {
  const e = err as BusinessError;
  if (e && typeof e.code === 'number') {
    return `${e.code}:${e.message ?? ''}`;
  }
  return JSON.stringify(err);
}

/** 写入/更新口令；value 为空串时删除 */
export async function saveSecret(alias: string, value: string): Promise<void> {
  if (value.length === 0) {
    await removeSecret(alias);
    return;
  }
  const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
  attributes.set(asset.Tag.ALIAS, utf8Encode(alias));
  attributes.set(asset.Tag.SECRET, utf8Encode(value));
  attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
  try {
    await asset.add(attributes);
  } catch (err) {
    const code: number = (err as BusinessError)?.code ?? 0;
    if (code === ERR_ALREADY_EXISTS) {
      const update: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      update.set(asset.Tag.SECRET, utf8Encode(value));
      try {
        await asset.update(aliasQuery(alias), update);
        return;
      } catch (updateErr) {
        hilog.error(DOMAIN, TAG, 'updateSecret failed: %{public}s', describe(updateErr as Object));
        return;
      }
    }
    hilog.error(DOMAIN, TAG, 'saveSecret failed: %{public}s', describe(err as Object));
  }
}

/** 读取口令；不存在或读取失败返回空串 */
export async function readSecret(alias: string): Promise<string> {
  try {
    const rows: Array<asset.AssetMap> = await asset.query(aliasQuery(alias));
    if (rows.length === 0) {
      return '';
    }
    const secret: asset.Value | undefined = rows[0].get(asset.Tag.SECRET);
    if (secret === undefined) {
      return '';
    }
    return typeof secret === 'string' ? secret : utf8Decode(secret as Uint8Array);
  } catch (err) {
    const code: number = (err as BusinessError)?.code ?? 0;
    if (code !== ERR_NOT_FOUND) {
      hilog.warn(DOMAIN, TAG, 'readSecret failed: %{public}s', describe(err as Object));
    }
    return '';
  }
}

/** 删除口令；本就不存在时静默返回 */
export async function removeSecret(alias: string): Promise<void> {
  try {
    await asset.remove(aliasQuery(alias));
  } catch (err) {
    const code: number = (err as BusinessError)?.code ?? 0;
    if (code !== ERR_NOT_FOUND) {
      hilog.warn(DOMAIN, TAG, 'removeSecret failed: %{public}s', describe(err as Object));
    }
  }
}
