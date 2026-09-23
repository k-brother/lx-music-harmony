/**
 * 歌单详情里「与本地自建歌单打交道」的动作
 *
 * 两件事都只依赖 ListService，与页面渲染无关：
 * 1. 顺序落库：排序/去重后把当前顺序写回本地歌单，否则退出再进又变回原顺序；
 * 2. 同步到本地：把在线歌单整体存成一张同名自建歌单（同名则覆盖更新）。
 *
 * 落库时优先复用「库里已有的 MusicItem」，只对缺失的行做转换 ——
 * 这样本地文件、下载信息等 SongItem 装不下的字段不会被一次排序抹掉。
 */
import { appLog as hilog } from '../../core/log/AppLogger';
import { t, tf } from '../../service/LocalizationService';
import {
  createUserList,
  getUserList,
  getUserListMusic,
  replaceUserListMusic,
  type ListInfo,
  type MusicItem,
} from '../../service/ListService';
import { songRowToListItem } from '../../core/list/SongMappers';
import type { ActionConfirm, ActionToast } from './SonglistActions';
import type { SongItem, SonglistInfo } from './SonglistTypes';

const TAG = 'SonglistLocal';
const DOMAIN: number = 0x0001;

/**
 * 把当前顺序写回本地歌单（排序 / 去重后调用）。
 * 只对本地歌单生效；失败只记日志，不影响界面（顺序已在内存里生效）。
 */
export async function persistLocalOrder(listId: string, rows: SongItem[]): Promise<void> {
  if (listId.length === 0) {
    return;
  }
  try {
    const existing = getUserListMusic(listId);
    const byId = new Map<string, MusicItem>();
    for (let i = 0; i < existing.length; i++) {
      byId.set(existing[i].id, existing[i]);
    }
    for (let i = 0; i < rows.length; i++) {
      const song = rows[i];
      if (!byId.has(song.id)) {
        byId.set(song.id, songRowToListItem(song));
      }
    }
    const keep: MusicItem[] = [];
    for (let i = 0; i < rows.length; i++) {
      const item = byId.get(rows[i].id);
      if (item && keep.indexOf(item) < 0) {
        keep.push(item);
      }
    }
    await replaceUserListMusic(listId, keep);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'persistLocalOrder failed: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
  }
}

/**
 * 在线歌单 → 本地自建歌单（同名则覆盖更新）。
 * 已有同名歌单时直接更新内容，不再新建一张重名的。
 */
export async function syncOnlineListToLocal(
  info: SonglistInfo, rows: SongItem[], confirm: ActionConfirm, toast: ActionToast
): Promise<void> {
  if (rows.length === 0) {
    toast(t('toast_songlist_empty'));
    return;
  }
  const name = info.name || t('songlist_title');
  const confirmed = await confirm(
    t('list_sync_local'),
    tf('confirm_sync_local', [name, rows.length.toString()]));
  if (!confirmed) {
    return;
  }
  try {
    const existing: ListInfo | undefined = getUserList().find((item: ListInfo) => item.name === name);
    let listId: string = existing ? existing.id : '';
    if (!listId) {
      const created = await createUserList(name);
      listId = created.id;
    }
    const items: MusicItem[] = [];
    for (let i = 0; i < rows.length; i++) {
      items.push(songRowToListItem(rows[i]));
    }
    await replaceUserListMusic(listId, items);
    toast(tf('toast_sync_local_done', [name, items.length.toString()]));
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'syncOnlineListToLocal failed: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    toast(t('toast_sync_local_failed'));
  }
}
