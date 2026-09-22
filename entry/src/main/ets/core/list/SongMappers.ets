/**
 * 歌曲对象转换（列表项 ↔ 播放项 ↔ 平台音乐对象）
 *
 * 这些转换原先散落在歌单详情页里（各 20~30 行、字段顺序还不一致），
 * 现在收敛到一处：任何页面要"把列表行变成可播放/可下载的对象"都用这里。
 */
import type { MusicInfo, MusicSource } from '../../types/MusicTypes';
import type { MusicItem } from '../../service/ListService';
import type { SongInfo } from '../../service/PlayerService';

/** 列表行（歌单详情 / 排行榜 / 本地音乐通用的最小字段集） */
export interface SongRowLike {
  id: string;
  name: string;
  singer: string;
  album: string;
  duration: number;
  source: string;
  pic: string;
  albumId?: string;
  songmid?: string;
  strMediaMid?: string;
  hash?: string;
  copyrightId?: string;
}

/** 秒 -> "mm:ss"（播放/下载接口需要的时长文本） */
export function secondsToInterval(seconds: number): string {
  const safe = isNaN(seconds) || seconds < 0 ? 0 : seconds;
  const minutes = Math.floor(safe / 60);
  const remainder = Math.floor(safe % 60);
  return `${minutes.toString().padStart(2, '0')}:${remainder.toString().padStart(2, '0')}`;
}

/** "mm:ss" -> 秒 */
export function intervalToSeconds(interval: string | null | undefined): number {
  if (!interval) {
    return 0;
  }
  const parts = interval.split(':');
  let seconds = 0;
  for (let i = 0; i < parts.length; i++) {
    const value = parseInt(parts[i], 10);
    if (!isNaN(value)) {
      seconds = seconds * 60 + value;
    }
  }
  return seconds;
}

/** 列表行 -> 平台音乐对象（取链、评论、分享、详情页链接都用它） */
export function songRowToMusicInfo(song: SongRowLike): MusicInfo {
  return {
    id: song.id,
    name: song.name,
    singer: song.singer,
    source: song.source as MusicSource,
    songmid: song.songmid || song.id,
    strMediaMid: song.strMediaMid,
    hash: song.hash ?? '',
    copyrightId: song.copyrightId ?? '',
    albumId: song.albumId ?? '',
    albumName: song.album,
    album: song.album,
    interval: secondsToInterval(song.duration),
    img: song.pic.length > 0 ? song.pic : null,
    pic: song.pic.length > 0 ? song.pic : undefined,
    lrc: null,
  };
}

/** 列表行 -> 本地列表项（加入我的列表时用） */
export function songRowToListItem(song: SongRowLike): MusicItem {
  return {
    id: song.id,
    name: song.name,
    singer: song.singer,
    album: song.album,
    albumId: song.albumId ?? null,
    duration: song.duration,
    source: song.source,
    pic: song.pic,
    lrc: null,
  };
}

/** 列表行 -> 播放队列项（url 留空由播放器按索引取链） */
export function songRowToQueueItem(song: SongRowLike, url: string = ''): SongInfo {
  return {
    id: song.id,
    songmid: song.songmid || song.id,
    url,
    title: song.name,
    artist: song.singer,
    album: song.album,
    artwork: song.pic.length > 0 ? song.pic : null,
    duration: song.duration,
    source: song.source,
    hash: song.hash,
    strMediaMid: song.strMediaMid,
    albumId: song.albumId,
    copyrightId: song.copyrightId,
  };
}
