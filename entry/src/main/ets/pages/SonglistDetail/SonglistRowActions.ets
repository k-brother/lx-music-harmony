/**
 * 歌单详情「单曲菜单」背后的业务动作
 *
 * 长按行 / 行尾 ⋮ 弹出的菜单项在这里各对应一个函数：
 * 分享、加入默认歌单、下载、不喜欢、打开源站详情、跳歌手/专辑搜索。
 * 页面只负责弹菜单、按返回值给提示 —— 菜单文案与业务实现彻底分开。
 */
import { appLog as hilog } from '../../core/log/AppLogger';
import { common } from '@kit.AbilityKit';
import { addMusicToList, LIST_IDS, type MusicItem } from '../../service/ListService';
import { songRowToListItem, songRowToMusicInfo } from '../../core/list/SongMappers';
import { dislikeList } from '../../core/dislike/DislikeList';
import { buildShareText, getMusicDetailPageUrl } from '../../core/music/MusicDetailUrl';
import { shareText, type ShareResult } from '../../service/ShareService';
import { downloadOne } from './SonglistActions';
import type { SongItem } from './SonglistTypes';

const TAG = 'SonglistRowActions';
const DOMAIN: number = 0x0001;

/**
 * 分享单曲：按「设置 → 分享方式」走系统分享，失败回退剪贴板（与播放页一致）。
 * `sourceLabelText` 由页面传入（页面持有本地化上下文），拼在文案最前面。
 */
export async function shareSongRow(
  context: common.UIAbilityContext, song: SongItem, sourceLabelText: string
): Promise<ShareResult> {
  const musicInfo = songRowToMusicInfo(song);
  const text = `[${sourceLabelText}] ${buildShareText(musicInfo)}`;
  try {
    return await shareText(context, text, song.name, getMusicDetailPageUrl(musicInfo));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'shareSongRow failed: %{public}s', JSON.stringify(err));
    return 'failed';
  }
}

/** 加入「默认歌单」；返回空串表示成功，否则返回错误描述 */
export async function addRowToDefaultList(song: SongItem): Promise<string> {
  try {
    const item: MusicItem = songRowToListItem(song);
    await addMusicToList(LIST_IDS.DEFAULT, item);
    return '';
  } catch (err) {
    const message = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, 'add to default list failed: %{public}s', message);
    return message;
  }
}

/** 下载单曲；返回空串表示已开始，否则返回错误描述 */
export async function downloadRow(song: SongItem): Promise<string> {
  try {
    await downloadOne(song);
    return '';
  } catch (err) {
    return err instanceof Error ? err.message : JSON.stringify(err);
  }
}

/**
 * 不喜欢：歌曲 / 歌手 / 歌名三种粒度（与播放页同一套规则）。
 * `pick` 为菜单下标：0=歌曲、1=歌手、2=歌名。
 * @returns 加入后的不喜欢总条数
 */
export async function addRowToDislike(song: SongItem, pick: number): Promise<number> {
  await dislikeList.load();
  if (pick === 0) {
    await dislikeList.add(song.name, song.singer);
  } else if (pick === 1) {
    await dislikeList.add('', song.singer);
  } else {
    await dislikeList.add(song.name, '');
  }
  return dislikeList.count();
}

/** 用系统浏览器打开链接；返回是否成功发起 */
export function openInBrowser(context: common.UIAbilityContext, url: string): boolean {
  if (url.length === 0) {
    return false;
  }
  try {
    context.startAbility({ action: 'ohos.want.action.viewData', uri: url })
      .catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'openInBrowser failed: %{public}s', err.message);
      });
    return true;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'openInBrowser failed: %{public}s', JSON.stringify(err));
    return false;
  }
}

/** 该歌曲在对应平台的详情页链接（无链接时返回空串） */
export function sourceDetailUrl(song: SongItem): string {
  return getMusicDetailPageUrl(songRowToMusicInfo(song));
}
