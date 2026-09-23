/**
 * 歌单详情的批量与下载动作
 *
 * 从 SonglistDetailPage 抽出：批量加歌单、批量下载、批量移出、整列表下载，
 * 都是「拿选中/全部歌曲 → 调服务 → 报进度与结果」的流程，与页面布局无关。
 * 页面只传数据与两个回调（确认、提示），不再被这几段 for 循环撑开。
 */
import { appLog as hilog } from '../../core/log/AppLogger';
import { t, tf } from '../../service/LocalizationService';
import { addMusicToList, LIST_IDS, removeMusicsFromList } from '../../service/ListService';
import { download } from '../../core/music/MusicFeatureEntry';
import { songRowToListItem, songRowToMusicInfo } from '../../core/list/SongMappers';
import type { MusicInfo } from '../../types/MusicTypes';
import type { SongItem } from './SonglistTypes';

const TAG = 'SonglistActions';
const DOMAIN: number = 0x0001;

/** 提示回调（页面侧统一走页面 toast） */
export type ActionToast = (message: string) => void;
/** 二次确认回调（页面侧统一走 DialogService.appConfirm） */
export type ActionConfirm = (title: string, message: string) => Promise<boolean>;

/** 目标歌单身份（判断是否本地列表、调用哪个列表接口） */
export interface SonglistTarget {
  source: string;
  listId: string;
  name: string;
}

/** 批量加入默认列表，返回成功条数 */
export async function batchAddToDefaultList(songs: SongItem[], toast: ActionToast): Promise<number> {
  if (songs.length === 0) {
    toast(t('toast_no_selection'));
    return 0;
  }
  let added = 0;
  for (let i = 0; i < songs.length; i++) {
    try {
      await addMusicToList(LIST_IDS.DEFAULT, songRowToListItem(songs[i]));
      added++;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'batch add failed: %{public}s', JSON.stringify(err));
    }
  }
  toast(tf('toast_batch_added', [added.toString()]));
  return added;
}

/** 下载单首（返回任务 id；失败抛出，由调用方决定提示） */
export async function downloadOne(song: SongItem): Promise<string> {
  const musicInfo: MusicInfo = songRowToMusicInfo(song);
  const taskId = await download.startDownload({ musicInfo: musicInfo });
  hilog.info(DOMAIN, TAG, 'Download started: %{public}s, taskId: %{public}s', song.name, taskId);
  return taskId;
}

/** 批量下载选中歌曲，返回成功条数 */
export async function batchDownloadSongs(
  songs: SongItem[], confirm: ActionConfirm, toast: ActionToast): Promise<number> {
  if (songs.length === 0) {
    toast(t('toast_no_selection'));
    return 0;
  }
  const confirmed = await confirm(
    t('player_download'),
    tf('confirm_download_songs', [songs.length.toString()]));
  if (!confirmed) {
    return 0;
  }
  let done = 0;
  for (let i = 0; i < songs.length; i++) {
    try {
      await downloadOne(songs[i]);
      done++;
      toast(tf('toast_downloading_progress', [(i + 1).toString(), songs.length.toString()]));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'batch download failed: %{public}s', JSON.stringify(err));
    }
  }
  toast(tf('toast_batch_downloaded', [done.toString()]));
  return done;
}

/**
 * 批量移出本地歌单（在线歌单只读，避免用户误以为云端被改）。
 * @returns 实际移除条数；-1 表示未执行（在线歌单或用户取消）
 */
export async function batchRemoveFromLocalList(
  target: SonglistTarget, songs: SongItem[],
  confirm: ActionConfirm, toast: ActionToast): Promise<number> {
  if (songs.length === 0) {
    toast(t('toast_no_selection'));
    return -1;
  }
  if (target.source !== 'local') {
    toast(t('toast_online_list_readonly'));
    return -1;
  }
  const confirmed = await confirm(
    t('list_remove_songs'),
    tf('confirm_remove_songs', [songs.length.toString()]));
  if (!confirmed) {
    return -1;
  }
  const ids: string[] = [];
  for (let i = 0; i < songs.length; i++) {
    ids.push(songs[i].id);
  }
  const removed = await removeMusicsFromList(target.listId, ids);
  toast(tf('toast_removed_count', [removed.toString()]));
  return removed;
}

/** 下载整张歌单（逐首提交，实时报进度，最后给汇总） */
export async function downloadWholeList(
  target: SonglistTarget, songs: SongItem[],
  confirm: ActionConfirm, toast: ActionToast): Promise<void> {
  if (songs.length === 0) {
    toast(t('toast_songlist_empty'));
    return;
  }
  const confirmed = await confirm(
    t('download_confirm_title'),
    tf('confirm_download_songlist', [target.name, songs.length.toString()]));
  if (!confirmed) {
    toast(t('toast_cancel_download'));
    return;
  }
  let successCount = 0;
  let failCount = 0;
  for (let i = 0; i < songs.length; i++) {
    try {
      await downloadOne(songs[i]);
      successCount++;
      toast(tf('toast_downloading_progress', [(i + 1).toString(), songs.length.toString()]));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to download song %{public}s: %{public}s',
        songs[i].name, JSON.stringify(err));
      failCount++;
    }
  }
  if (successCount > 0) {
    toast(tf('toast_download_summary', [successCount.toString(), failCount.toString()]));
  } else {
    toast(t('toast_download_failed_network'));
  }
}
