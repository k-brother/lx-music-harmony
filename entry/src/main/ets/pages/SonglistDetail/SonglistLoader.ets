/**
 * 歌单详情的加载（在线 / 本地）
 *
 * 从 SonglistDetailPage 抽出：源支持性判断、在线接口调用、结果规范化（名称/创建者/封面/播放量）
 * 与本地列表读取，都与页面状态无关；页面只负责把结果写进 @State 并处理滚动位置。
 */
import { appLog as hilog } from '../../core/log/AppLogger';
import { t } from '../../service/LocalizationService';
import { getSongListDetail, type SongListDetailResult } from '../../core/music/MusicFeatureEntry';
import { getUserList, getUserListMusic, type ListInfo, type MusicItem } from '../../service/ListService';
import { SUPPORTED_SOURCES, type MusicSource } from '../../types/MusicSource';
import {
  musicInfoListToSongItems,
  musicRowListToSongItems,
  parsePlayCountText,
} from './SonglistMapper';
import { plainTextFromHtml } from '../../utils/CommonUtils';
import type { SongItem, SonglistInfo } from './SonglistTypes';

const TAG = 'SonglistLoader';
const DOMAIN: number = 0x0001;
/** 支持歌单详情接口的音源（local 走本地读取）：列表统一在 types/MusicSource */

/** 加载结果：页面据此决定「展示 / 报错 / 不支持的源」 */
export interface SonglistLoadOutcome {
  status: 'ok' | 'unsupported' | 'error';
  info?: SonglistInfo;
  songs?: SongItem[];
}

/** 在线歌单详情：接口返回后做一次规范化 */
export async function loadOnlineSonglist(source: string, id: string): Promise<SonglistLoadOutcome> {
  if (!SUPPORTED_SOURCES.includes(source as MusicSource)) {
    hilog.warn(DOMAIN, TAG, 'Source %{public}s does not support song list detail', source);
    return { status: 'unsupported' };
  }
  try {
    const result: SongListDetailResult = await getSongListDetail(id, 1, source);
    hilog.info(DOMAIN, TAG, 'API returned: %{public}s songs, info: %{public}s',
      result.list.length.toString(), JSON.stringify(result.info));
    if (result.list.length === 0) {
      hilog.warn(DOMAIN, TAG, 'Empty song list returned for source: %{public}s', source);
    }
    const info: SonglistInfo = {
      source: source,
      id: id,
      name: plainTextFromHtml(result.info.name || '') || t('unknown_playlist'),
      // 作者字段各源都可能带 HTML 实体或纯空白，先转纯文本，空则由头部隐藏该行
      creator: plainTextFromHtml(result.info.author || ''),
      pic: result.info.img || '',
      // 源返回的简介是 HTML 片段（含 <br>），这里统一转纯文本，界面不再出现标签字面量
      desc: plainTextFromHtml(result.info.desc || ''),
      playCount: parsePlayCountText(result.info.play_count),
    };
    return { status: 'ok', info: info, songs: musicInfoListToSongItems(result.list, source) };
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to load song list detail: %{public}s', JSON.stringify(err));
    return { status: 'error' };
  }
}

/** 本地自建歌单：直接从 ListService 读 */
export function loadLocalSonglist(id: string): SonglistLoadOutcome {
  try {
    const listInfo: ListInfo | undefined = getUserList().find((item: ListInfo): boolean => item.id === id);
    if (!listInfo) {
      hilog.warn(DOMAIN, TAG, 'Local list not found: %{public}s', id);
      return { status: 'error' };
    }
    const localSongs: MusicItem[] = getUserListMusic(id);
    const info: SonglistInfo = {
      source: 'local',
      id: listInfo.id,
      name: listInfo.name,
      creator: t('local_playlist'),
      pic: listInfo.pic || (localSongs.length > 0 ? (localSongs[0].pic ?? '') : ''),
      desc: plainTextFromHtml(listInfo.desc || ''),
      playCount: 0,
    };
    return { status: 'ok', info: info, songs: musicRowListToSongItems(localSongs) };
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to load local song list: %{public}s', JSON.stringify(err));
    return { status: 'error' };
  }
}
