/**
 * 歌单内「调整位置 / 移动到其他列表」动作
 *
 * 从 SonglistDetailPage 抽出：两个动作都是「本地歌单 + ListService 的位置/跨列表操作」，
 * 与页面渲染无关。页面只负责开关面板、刷新本地行与提示。
 */
import { appLog as hilog } from '../../core/log/AppLogger';
import { t, tf } from '../../service/LocalizationService';
import {
  addMusicToList,
  getUserList,
  moveMusicInList,
  removeMusicsFromList,
  type ListInfo,
} from '../../service/ListService';
import { songRowToListItem } from '../../core/list/SongMappers';
import type { SettingOption } from '../../components/ui/SettingsTypes';
import type { SongItem } from './SonglistTypes';

const TAG = 'SonglistMove';
const DOMAIN: number = 0x0001;

/** 页面提示回调 */
export type MoveToast = (message: string) => void;

/** 可移动的目标歌单（排除当前歌单） */
export function buildMoveTargetOptions(currentListId: string): SettingOption[] {
  const options: SettingOption[] = [];
  const lists: ListInfo[] = getUserList();
  for (let i = 0; i < lists.length; i++) {
    if (lists[i].id === currentListId) {
      continue;
    }
    options.push({ label: lists[i].name, value: lists[i].id });
  }
  return options;
}

/** 当前歌曲在列表里的位置（用于面板默认值） */
export function positionOf(songs: SongItem[], songId: string): number {
  for (let i = 0; i < songs.length; i++) {
    if (songs[i].id === songId) {
      return i + 1;
    }
  }
  return 0;
}

/** 应用位置调整（1 基）。返回是否成功提交 */
export async function applyMovePosition(
  listId: string, song: SongItem, value: string, songs: SongItem[], toast: MoveToast): Promise<boolean> {
  const position = parseInt(value.trim(), 10);
  if (isNaN(position) || position < 1 || position > songs.length) {
    toast(tf('list_position_invalid', [songs.length.toString()]));
    return false;
  }
  try {
    const moved = await moveMusicInList(listId, song.id, position);
    toast(moved ? tf('list_position_moved', [position.toString()]) : t('list_position_unchanged'));
    return true;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'applyMovePosition failed: %{public}s', JSON.stringify(err));
    toast(t('toast_operation_failed'));
    return false;
  }
}

/** 「移动」= 加入目标列表 + 从当前列表移除（与安卓版 move_to 语义一致） */
export async function applyMoveToList(
  currentListId: string, song: SongItem, targetListId: string, toast: MoveToast): Promise<boolean> {
  if (targetListId.length === 0) {
    return false;
  }
  try {
    await addMusicToList(targetListId, songRowToListItem(song));
    await removeMusicsFromList(currentListId, [song.id]);
    toast(t('list_move_done'));
    return true;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'applyMoveToList failed: %{public}s', JSON.stringify(err));
    toast(t('toast_operation_failed'));
    return false;
  }
}
