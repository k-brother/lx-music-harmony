/**
 * 歌单详情的「播放落点」
 *
 * 页面原先在 playSong / playAll 里各写了一遍「建队列 → 取播放地址 → 入队 → 开播」，
 * 两份实现细节还不一致（列表为空、取地址失败的收尾各不相同）。
 * 这里收口成一处：页面只保留「置播放态 → 调这里 → 按结果给提示」。
 */
import { appLog as hilog } from '../../core/log/AppLogger';
import { playerService } from '../../service/PlayerService';
import type { SongInfo } from '../../service/PlayerService';
import { buildFullQueue, buildQueue, resolvePlayUrl, toMusicInfo } from './SonglistPlayback';
import type { SongItem, SonglistInfo } from './SonglistTypes';

const TAG = 'SonglistPlay';
const DOMAIN: number = 0x0001;

/**
 * 播放结果
 * - ok：已开播
 * - no-url：没取到播放地址（调用方回滚播放态并提示）
 * - empty：列表为空 / 下标越界（调用方静默返回）
 */
export type SonglistPlayResult = 'ok' | 'no-url' | 'empty';

/**
 * 列表「正在播放」高亮不再由页面对数据打标（那会在自动切歌后停在旧行），
 * 统一改为比较播放器发布的全局 key：AppStorage['playingSongKey']（PlayerService.playKeyOfIds）。
 * 这里保留说明，避免后来者又加回一份本地播放态。
 */

/**
 * 播放已加载列表里的第 index 首。
 *
 * 队列语义对齐安卓版：点行 = 整张歌单入队并立即播放。
 * `listClickPlay=true` 时只用当前已加载的列表（安卓 onPlayList）；
 * 否则先播已加载页，随后后台补全全部页替换队列（安卓渐进式 temp list）。
 */
export async function playSongRow(
  rows: SongItem[], index: number, info: SonglistInfo, listClickPlay: boolean
): Promise<SonglistPlayResult> {
  if (rows.length === 0) {
    return 'empty';
  }
  const song = rows[index];
  if (!song) {
    hilog.error(DOMAIN, TAG, 'song not found at index %{public}d', index);
    return 'empty';
  }

  const queue: SongInfo[] = buildQueue(rows, info.pic);
  const url: string | null = await resolvePlayUrl(toMusicInfo(song));
  if (!url || url.length === 0) {
    hilog.error(DOMAIN, TAG, 'no url for %{public}s', song.name);
    return 'no-url';
  }

  queue[index].url = url;
  playerService.setPlayList(queue, index);
  hilog.info(DOMAIN, TAG, 'playlist set: %{public}d songs from index %{public}d', queue.length, index);
  if (!listClickPlay) {
    void fillQueueWithAllPages(info, rows.length, song.name);
  }
  await playerService.playFromSelection(queue[index], url, song.duration);
  return 'ok';
}

/** 播放全部：等价于点第一行，并让第一行显示为播放中 */
export async function playAllRows(rows: SongItem[], info: SonglistInfo): Promise<SonglistPlayResult> {
  if (rows.length === 0) {
    return 'empty';
  }
  return await playSongRow(rows, 0, info, true);
}

/**
 * 后台拉取在线歌单的全部页并替换队列（安卓 handlePlay 里 getListDetailAll 的等价实现）。
 * 只补齐「当前仍在播放的那首歌所属的队列」，避免用户已切歌却被覆盖。
 */
export async function fillQueueWithAllPages(
  info: SonglistInfo, loadedCount: number, anchorName: string
): Promise<void> {
  const queue: SongInfo[] | null = await buildFullQueue(info.source, info.id, info.pic, loadedCount);
  if (!queue) {
    return;
  }
  playerService.refineQueueWithFullList(queue);
  hilog.info(DOMAIN, TAG, 'queue refined: %{public}d songs (anchor=%{public}s)', queue.length, anchorName);
}
