/**
 * 歌单详情的「收藏 / 列表级同步」动作
 *
 * 从 SonglistDetailPage 抽出：收藏在线歌单 = 建一张绑定它的自建歌单；
 * 已收藏时提供「更新内容 / 取消收藏」。这一组动作只依赖 UserListSyncService，
 * 与页面渲染无关，单独成文件后「收藏语义」一眼可见。
 */
import { appLog as hilog } from '../../core/log/AppLogger';
import { t, tf } from '../../service/LocalizationService';
import {
  collectOnlineSonglist,
  isOnlineSonglistCollected,
  syncUserListFromOnline,
  uncollectOnlineSonglist,
} from '../../service/UserListSyncService';
import { findUserListByBinding } from '../../service/ListService';
import type { ActionConfirm, ActionToast } from './SonglistActions';
import type { SonglistInfo } from './SonglistTypes';

const TAG = 'SonglistCollect';
const DOMAIN: number = 0x0001;

/** 收藏动作的结果：collected=已收藏（应弹「更新/取消」菜单） */
export interface CollectOutcome {
  kind: 'collected' | 'menu' | 'failed' | 'skip';
  /** 新收藏时拉到的歌曲数 */
  count: number;
}

/**
 * 收藏在线歌单。
 * `busy` 由调用方（页面）传入并在调用前置位，避免重复触发耗时拉取。
 */
export async function collectSonglist(info: SonglistInfo, toast: ActionToast): Promise<CollectOutcome> {
  if (info.source === 'local') {
    toast(t('toast_local_list_no_collect'));
    return { kind: 'skip', count: 0 };
  }
  if (isOnlineSonglistCollected(info.source, info.id)) {
    // 已收藏：交给调用方弹菜单（更新内容 / 取消收藏）
    return { kind: 'menu', count: 0 };
  }
  try {
    hilog.info(DOMAIN, TAG, 'Collect songlist: %{public}s', info.name);
    toast(t('toast_collecting'));
    const result = await collectOnlineSonglist(info.source, info.id, info.name, info.pic);
    toast(tf('toast_collected_count', [String(result.localCount ?? 0)]));
    return { kind: 'collected', count: result.localCount ?? 0 };
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, 'Failed to collect: %{public}s', errorMsg);
    toast(t('toast_operation_failed') + ': ' + errorMsg);
    return { kind: 'failed', count: 0 };
  }
}

/** 列表级同步：重新拉在线内容覆盖本地绑定歌单 */
export async function syncBoundSonglist(info: SonglistInfo, toast: ActionToast): Promise<void> {
  const bound = findUserListByBinding(info.source, info.id);
  if (!bound) {
    toast(t('toast_operation_failed'));
    return;
  }
  try {
    toast(t('toast_syncing'));
    const result = await syncUserListFromOnline(bound.id);
    toast(result.ok
      ? tf('toast_sync_done_count', [String(result.count)])
      : t('toast_sync_local_failed'));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'syncBoundSonglist failed: %{public}s', JSON.stringify(err));
    toast(t('toast_sync_local_failed'));
  }
}

/** 取消收藏（删掉绑定的自建歌单，二次确认） */
export async function uncollectSonglist(
  info: SonglistInfo, confirm: ActionConfirm, toast: ActionToast): Promise<boolean> {
  const confirmed = await confirm(
    t('toast_uncollected_action'),
    tf('confirm_uncollect', [info.name]));
  if (!confirmed) {
    return false;
  }
  try {
    await uncollectOnlineSonglist(info.source, info.id);
    toast(tf('toast_uncollected', [info.name]));
    return true;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'uncollectSonglist failed: %{public}s', JSON.stringify(err));
    toast(t('toast_operation_failed'));
    return false;
  }
}
