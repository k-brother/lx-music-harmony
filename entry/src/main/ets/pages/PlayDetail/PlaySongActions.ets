/**
 * 播放页的「单曲动作」命令集
 *
 * 从 PlayDetailPage 抽出：分享 / 下载 / 收藏 / 加入歌单 / 保存歌词 / 保存封面 / 不喜欢 /
 * 换源候选与切源。这些动作的共同点是「拿到当前歌曲 → 调服务 → 提示结果」，
 * 与页面状态无关；留在页面里时，页面被这些 if-else 撑到 1400 行、难以看清 UI 结构。
 *
 * 约定：不直接依赖页面，只接收 `CurrentSong` 与 `toast` 回调，便于单独复用与核对。
 */
import { common } from '@kit.AbilityKit';
import { appLog as hilog } from '../../core/log/AppLogger';
import {
  addMusicToList,
  getUserList,
  LIST_IDS,
  toggleLoveList,
  type MusicItem,
} from '../../service/ListService';
import { t, tf, sourceLabel } from '../../service/LocalizationService';
import { appActionMenu } from '../../service/DialogService';
import { download, getMusicUrl, getOtherSource } from '../../core/music/MusicFeatureEntry';
import { buildShareText, getMusicDetailPageUrl } from '../../core/music/MusicDetailUrl';
import { shareText } from '../../service/ShareService';
import { mediaSaveService, type SaveResult } from '../../service/MediaSaveService';
import { dislikeList } from '../../core/dislike/DislikeList';
import { playerService, type SongInfo } from '../../service/PlayerService';
import { parsePlayTime } from '../../utils/CommonUtils';
import { showDislikeMenu } from './PlayDetailMenus';
import type { MusicInfo } from '../../types/MusicTypes';

const TAG = 'PlaySongActions';
const DOMAIN: number = 0x0001;
/** 结果提示回调（页面侧统一走 DialogService.appToast） */
export type ActionToast = (message: string) => void;

/** 加入歌单：默认列表 / 我喜欢 / 自建列表（系统菜单最多 5 项，超出由菜单自身折叠） */
export async function addSongToPlaylist(info: MusicInfo, toast: ActionToast): Promise<void> {
  if (!info || !info.name) {
    toast(t('player_no_song'));
    return;
  }
  const options: string[] = [t('default_list_label'), t('love_title')];
  const ids: string[] = [LIST_IDS.DEFAULT, LIST_IDS.LOVE];
  const userLists = getUserList();
  for (let i = 0; i < userLists.length && options.length < 5; i++) {
    options.push(userLists[i].name);
    ids.push(userLists[i].id);
  }
  const index = await appActionMenu(t('player_add_to_list'), options);
  if (index < 0 || index >= ids.length) {
    return;
  }
  const musicItem: MusicItem = {
    id: info.id || info.songmid || '',
    name: info.name,
    singer: info.singer,
    album: info.album ?? info.albumName ?? '',
    albumId: null,
    duration: 0,
    source: info.source,
    pic: info.pic || info.img || '',
    lrc: null,
  };
  try {
    await addMusicToList(ids[index], musicItem);
    toast(tf('toast_added_quoted', [options[index]]));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'addSongToPlaylist failed: %{public}s', JSON.stringify(err));
    toast(t('toast_add_list_fail'));
  }
}

/** 收藏 / 取消收藏，返回操作后的收藏态 */
export async function toggleLoveSong(info: MusicInfo, toast: ActionToast): Promise<boolean> {
  if (!info.id || !info.name) {
    toast(t('player_no_song'));
    return false;
  }
  try {
    const loved = await toggleLoveList({
      id: info.id,
      name: info.name,
      singer: info.singer,
      album: info.album ?? info.albumName ?? '',
      albumId: info.albumId ?? null,
      duration: 0,
      source: info.source ?? '',
      pic: info.pic ?? info.img ?? '',
      lrc: null,
    });
    toast(loved ? t('player_loved') : t('player_unloved_ok'));
    return loved;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'toggleLoveSong failed: %{public}s', JSON.stringify(err));
    toast(t('toast_operation_failed'));
    return false;
  }
}

/** 下载当前歌曲（走统一下载服务，下载页可见） */
export async function downloadSong(info: MusicInfo, toast: ActionToast): Promise<void> {
  if (!info.id || !info.name) {
    toast(t('player_no_song'));
    return;
  }
  try {
    const taskId = await download.startDownload({ musicInfo: info });
    hilog.info(DOMAIN, TAG, 'download started: %{public}s', taskId);
    toast(tf('toast_download_start_song', [info.name]));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'downloadSong failed: %{public}s', JSON.stringify(err));
    toast(t('toast_download_failed_network'));
  }
}

/** 分享：按「设置 → 分享方式」走系统分享，失败自动回退剪贴板 */
export async function shareSong(
  info: MusicInfo, uiContext: common.UIAbilityContext | null, toast: ActionToast): Promise<void> {
  if (!info.name) {
    toast(t('player_no_song'));
    return;
  }
  if (!uiContext) {
    toast(t('toast_operation_failed'));
    return;
  }
  // 附上当前播放位置 + 平台详情页链接（与安卓版分享内容一致）
  const progress = playerService.getProgress();
  const extra = progress.nowPlayTime > 0 ? progress.nowPlayTimeStr : '';
  const withPosition = `[${sourceLabel(info.source ?? '')}] ${buildShareText(info, extra)}`;
  try {
    const result = await shareText(uiContext, withPosition, info.name, getMusicDetailPageUrl(info));
    if (result === 'clipboard') {
      toast(t('toast_share_copy'));
    } else if (result === 'failed') {
      toast(t('toast_operation_failed'));
    }
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'shareSong failed: %{public}s', JSON.stringify(err));
    toast(t('toast_operation_failed'));
  }
}

/** 保存歌词到文件（失败原因由 MediaSaveService 给出） */
export async function saveLyricToFile(
  info: MusicInfo, rawLyric: string, toast: ActionToast): Promise<void> {
  if (!info || !info.name) {
    toast(t('player_no_song'));
    return;
  }
  if (!rawLyric) {
    toast(t('media_lyric_empty'));
    return;
  }
  try {
    const result: SaveResult = await mediaSaveService.saveLyricToFile(info, rawLyric);
    toast(result.success ? t('media_save_success') : (result.error || t('media_save_fail')));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'saveLyricToFile failed: %{public}s', JSON.stringify(err));
    toast(t('media_save_fail'));
  }
}

/** 保存封面到文件 */
export async function saveCoverToFile(info: MusicInfo, toast: ActionToast): Promise<void> {
  if (!info || !info.name) {
    toast(t('player_no_song'));
    return;
  }
  const imageUrl = info.pic || info.img || '';
  if (!imageUrl) {
    toast(t('media_url_empty'));
    return;
  }
  try {
    const result: SaveResult = await mediaSaveService.saveCoverToFile(info, imageUrl);
    toast(result.success ? t('media_save_success') : (result.error || t('media_save_fail')));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'saveCoverToFile failed: %{public}s', JSON.stringify(err));
    toast(t('media_save_fail'));
  }
}

/** 不喜欢：按 歌曲 / 歌手 / 歌名 三种粒度加入屏蔽（播放时自动跳过） */
export async function addToDislikeList(info: MusicInfo, toast: ActionToast): Promise<void> {
  if (!info.name) {
    toast(t('player_no_song'));
    return;
  }
  const level = await showDislikeMenu();
  if (level === null) {
    return;
  }
  try {
    await dislikeList.load();
    if (level === 'song') {
      await dislikeList.add(info.name, info.singer);
    } else if (level === 'singer') {
      await dislikeList.add('', info.singer);
    } else {
      await dislikeList.add(info.name, '');
    }
    toast(tf('dislike_added', [dislikeList.count().toString()]));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'addToDislikeList failed: %{public}s', JSON.stringify(err));
    toast(t('toast_operation_failed'));
  }
}

/**
 * 换源候选：同一首歌在其它源的匹配结果（每个源只留排序最靠前的一个）。
 * 返回空数组表示没找到候选（页面据此提示）。
 */
export async function fetchSourceCandidates(info: MusicInfo): Promise<MusicInfo[]> {
  if (!info || !info.name) {
    return [];
  }
  let candidates: MusicInfo[] = [];
  try {
    candidates = await getOtherSource(info);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'getOtherSource failed: %{public}s', JSON.stringify(err));
    return [];
  }
  const picked: MusicInfo[] = [];
  const usedSources: Set<string> = new Set();
  for (let i = 0; i < candidates.length && picked.length < 5; i++) {
    const item = candidates[i];
    const source = item.source ?? '';
    if (source.length === 0 || usedSources.has(source)) {
      continue;
    }
    usedSources.add(source);
    picked.push(item);
  }
  return picked;
}

/** 切到指定源的匹配结果并播放 */
export async function switchToSource(target: MusicInfo, toast: ActionToast): Promise<void> {
  try {
    const url = await getMusicUrl({ musicInfo: target, allowToggleSource: false });
    if (!url || url.length === 0) {
      toast(t('switch_source_failed'));
      return;
    }
    const durationSec = target.interval ? parsePlayTime(target.interval) : 0;
    const song: SongInfo = {
      id: target.id || target.songmid || '',
      songmid: target.songmid || target.id,
      url: url,
      title: target.name,
      artist: target.singer,
      album: target.album ?? target.albumName ?? '',
      artwork: target.pic ?? target.img ?? null,
      duration: durationSec,
      source: target.source,
      hash: target.hash,
      strMediaMid: target.strMediaMid,
      songId: target.songId,
      albumId: target.albumId,
      copyrightId: target.copyrightId,
    };
    playerService.setPlayList([song], 0);
    await playerService.playFromSelection(song, url, durationSec);
    toast(`${t('switch_source')}: ${sourceLabel(target.source ?? '')}`);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'switchToSource failed: %{public}s', JSON.stringify(err));
    toast(t('switch_source_failed'));
  }
}
