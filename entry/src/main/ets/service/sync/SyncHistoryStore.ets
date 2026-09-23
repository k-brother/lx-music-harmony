/**
 * 同步服务器历史（对齐安卓版 Sync/History）
 *
 * 只跟存储打交道：最近连接过的服务器地址、最多 10 条、同地址合并并更新时间。
 * 从 SyncService 抽出后，设置页「同步历史」与同步服务共用同一实现。
 */
import { appLog as hilog } from '../../core/log/AppLogger';
import { getStorageService } from '../../core/interfaces/IStorageService';
import type { SyncHistoryItem } from './SyncTypes';

const TAG = 'SyncHistory';
const DOMAIN: number = 0x0001;
/** 同步服务器历史存储键 */
export const SYNC_HISTORY_KEY = 'sync.serverHistory';
/** 历史最多保留条数 */
const MAX_HISTORY = 10;

/** 读取连接过的同步服务器历史（最近使用在前） */
export async function getServerHistory(): Promise<SyncHistoryItem[]> {
  try {
    const raw = await getStorageService().getString(SYNC_HISTORY_KEY, '');
    if (raw.length === 0) {
      return [];
    }
    const parsed = JSON.parse(raw) as SyncHistoryItem[];
    return Array.isArray(parsed) ? parsed : [];
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'getServerHistory failed: %{public}s', JSON.stringify(err));
    return [];
  }
}

/** 记录一次使用过的服务器地址（同地址合并并更新时间） */
export async function rememberServer(serverUrl: string): Promise<void> {
  const url = serverUrl.trim();
  if (url.length === 0) {
    return;
  }
  try {
    const list = await getServerHistory();
    const next: SyncHistoryItem[] = [{ serverUrl: url, lastUsed: Date.now() }];
    for (let i = 0; i < list.length; i++) {
      if (list[i].serverUrl !== url) {
        next.push(list[i]);
      }
    }
    await getStorageService().setString(SYNC_HISTORY_KEY, JSON.stringify(next.slice(0, MAX_HISTORY)));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'rememberServer failed: %{public}s', JSON.stringify(err));
  }
}

/** 删除一条历史 */
export async function removeServerHistory(serverUrl: string): Promise<void> {
  try {
    const list = await getServerHistory();
    const next = list.filter((item: SyncHistoryItem): boolean => item.serverUrl !== serverUrl);
    await getStorageService().setString(SYNC_HISTORY_KEY, JSON.stringify(next));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'removeServerHistory failed: %{public}s', JSON.stringify(err));
  }
}
