/**
 * 歌单详情的播放/队列构建
 *
 * 页面里原先有五处「列表行 -> 播放项 / 平台对象」的手写映射，字段还不完全一致。
 * 这里统一成一组函数：页面只关心「点了第几首、是否播成功」。
 */
import type { MusicInfo } from '../../types/MusicTypes';
import type { SongInfo } from '../../service/PlayerService';
import type { MusicItem } from '../../service/ListService';
import { getMusicUrl } from '../../core/music/MusicFeatureEntry';
import { fetchAllOnlineSongs } from '../../service/UserListSyncService';
import {
  musicItemToQueueItem,
  songRowToMusicInfo,
  songRowToQueueItem,
  type SongRowLike,
} from '../../core/list/SongMappers';
import { appLog as hilog } from '../../core/log/AppLogger';

const DOMAIN = 0x0001;
const TAG = 'SonglistPlayback';

/** 列表行 -> 播放队列（封面回退到歌单封面） */
export function buildQueue(rows: SongRowLike[], listCover: string): SongInfo[] {
  const queue: SongInfo[] = [];
  for (let i = 0; i < rows.length; i++) {
    queue.push(songRowToQueueItem(rows[i], '', listCover));
  }
  return queue;
}

/** 取播放地址（失败返回 null，由调用方给出提示） */
export async function resolvePlayUrl(musicInfo: MusicInfo): Promise<string | null> {
  try {
    const url: string | null = await getMusicUrl({
      musicInfo: musicInfo,
      isRefresh: false,
      onToggleSource: null,
      allowToggleSource: true,
    });
    if (!url || url.length === 0) {
      hilog.error(DOMAIN, TAG, 'no url for %{public}s', musicInfo.name);
      return null;
    }
    return url;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'resolve url failed for %{public}s: %{public}s',
      musicInfo.name, err instanceof Error ? err.message : JSON.stringify(err));
    return null;
  }
}

/** 列表行 -> 平台音乐对象（分享、下载、详情页链接共用） */
export function toMusicInfo(song: SongRowLike): MusicInfo {
  return songRowToMusicInfo(song);
}

/**
 * 拉取在线歌单的全部歌曲并转成队列（用于「先播第一页、后台补全」）
 *
 * @returns 补全后的队列；没有更多页或失败时返回 null（调用方保持现有队列）
 */
export async function buildFullQueue(
  source: string, listId: string, listCover: string, loadedCount: number
): Promise<SongInfo[] | null> {
  if (source.length === 0 || source === 'local' || listId.length === 0) {
    return null;
  }
  try {
    const all: MusicItem[] = await fetchAllOnlineSongs(source, listId);
    if (all.length <= loadedCount) {
      return null;
    }
    const queue: SongInfo[] = [];
    for (let i = 0; i < all.length; i++) {
      queue.push(musicItemToQueueItem(all[i], listCover));
    }
    return queue;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'buildFullQueue failed: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    return null;
  }
}
