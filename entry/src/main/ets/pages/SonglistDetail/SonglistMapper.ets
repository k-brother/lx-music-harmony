/**
 * 歌单详情的数据映射（纯函数）
 *
 * 从 SonglistDetailPage 抽出：在线歌单（MusicInfo）与本地曲库（MusicItem）两条链路
 * 都在往同一个行结构 SongItem 上映射，字段口径必须一致；放在一起后新增字段只改一处。
 * 顺带把「时长字符串 → 秒」统一到 utils/CommonUtils.parsePlayTime（原来页面自己又写了一份）。
 */
import { parsePlayTime } from '../../utils/CommonUtils';
import type { MusicInfo } from '../../types/MusicTypes';
import type { MusicItem } from '../../service/ListService';
import type { SongItem } from './SonglistTypes';

/** "1234" 或 "1.2万" 这类播放量文本 → 数值（解析失败为 0） */
export function parsePlayCountText(countStr: string): number {
  if (!countStr) {
    return 0;
  }
  const num = parseFloat(countStr);
  return isNaN(num) ? 0 : num;
}

/** "03:55" → 秒（非法/空返回 0） */
export function secondsFromInterval(interval: string | null): number {
  if (!interval) {
    return 0;
  }
  const seconds = parsePlayTime(interval);
  return isNaN(seconds) ? 0 : seconds;
}

/** 在线歌单的一首歌 → 页面行 */
export function musicInfoToSongItem(m: MusicInfo, source: string): SongItem {
  return {
    id: m.songmid || m.id || '',
    name: m.name || '',
    singer: m.singer || '',
    album: m.albumName || m.album || '',
    duration: secondsFromInterval(m.interval),
    isPlaying: false,
    source: source,
    pic: m.img || m.pic || '',
    albumId: m.albumId || '',
    songmid: m.songmid || '',
    strMediaMid: m.strMediaMid || '',
    hash: m.hash || '',
    copyrightId: m.copyrightId || '',
  };
}

/** 本地曲库的一行 → 页面行 */
export function musicRowToSongItem(song: MusicItem): SongItem {
  return {
    id: song.id || '',
    name: song.name || '',
    singer: song.singer || '',
    album: song.album || '',
    duration: song.duration || 0,
    isPlaying: false,
    source: song.source || 'local',
    pic: song.pic || '',
    albumId: song.albumId || '',
    songmid: song.id || '',
    hash: '',
    strMediaMid: '',
    copyrightId: '',
  };
}

/** 整列表映射：在线歌单 */
export function musicInfoListToSongItems(list: MusicInfo[], source: string): SongItem[] {
  const items: SongItem[] = [];
  for (let i = 0; i < list.length; i++) {
    items.push(musicInfoToSongItem(list[i], source));
  }
  return items;
}

/** 整列表映射：本地曲库 */
export function musicRowListToSongItems(list: MusicItem[]): SongItem[] {
  const items: SongItem[] = [];
  for (let i = 0; i < list.length; i++) {
    items.push(musicRowToSongItem(list[i]));
  }
  return items;
}
