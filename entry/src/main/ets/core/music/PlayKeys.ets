/**
 * 播放身份 key（源 + songmid/id）—— 全工程唯一实现
 *
 * 之前播放器、歌词中枢各写一份（歌词那边为了避开循环引用还换了分隔符），
 * 两边对「同一首歌」的判断口径不一致：源 JSON 里 id 可能是数字、也可能是字符串，
 * 字符串拼接时 `123` 与 `'123'` 会算出不同的 key，表现为切歌后歌词不刷新、
 * 列表高亮不跟随。这里统一收敛成一个实现，并强制字符串化。
 */
import { asText } from '../../utils/ValueCoerce';
import type { MusicInfo } from '../../types/MusicTypes';

/** 由各字段拼 key（列表行/页面高亮用，参数可能来自动态 JSON） */
export function playKeyOfIds(
  source: string | undefined, songmid: string | undefined, id: string | undefined): string {
  const primary: string = asText(songmid, asText(id));
  if (primary.length === 0) {
    return '';
  }
  return `${asText(source)}|${primary}`;
}

/** MusicInfo 版本（播放服务/歌词中枢/播控内部用） */
export function playKeyOf(info: MusicInfo | null | undefined): string {
  if (!info) {
    return '';
  }
  return playKeyOfIds(info.source, info.songmid, info.id);
}
