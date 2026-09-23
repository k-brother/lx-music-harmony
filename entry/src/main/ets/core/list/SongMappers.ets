/**
 * 歌曲对象转换（列表项 ↔ 播放项 ↔ 平台音乐对象）
 *
 * 这些转换原先散落在歌单详情页里（各 20~30 行、字段顺序还不一致），
 * 现在收敛到一处：任何页面要"把列表行变成可播放/可下载的对象"都用这里。
 */
import type { MusicInfo, MusicSource } from '../../types/MusicTypes';
import { formatClock, parsePlayTimeText } from '../../utils/FormatTools';
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

/** 秒 → "mm:ss"（实现统一在 FormatTools，这里保留原函数名） */
export function secondsToInterval(seconds: number): string {
  return formatClock(seconds);
}

/** "mm:ss" → 秒（实现统一在 FormatTools，这里保留原函数名） */
export function intervalToSeconds(interval: string | null | undefined): number {
  return parsePlayTimeText(interval);
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
export function songRowToQueueItem(song: SongRowLike, url: string = '', fallbackCover: string = ''): SongInfo {
  const cover = song.pic.length > 0 ? song.pic : fallbackCover;
  return {
    id: song.id,
    songmid: song.songmid || song.id,
    url,
    title: song.name,
    artist: song.singer,
    album: song.album,
    artwork: cover.length > 0 ? cover : null,
    duration: song.duration,
    source: song.source,
    hash: song.hash,
    strMediaMid: song.strMediaMid,
    albumId: song.albumId,
    copyrightId: song.copyrightId,
  };
}

/**
 * 本地列表项 -> 播放队列项
 *
 * 队列补全时拿到的是 MusicItem（已经落库的形状），字段名与 SongRowLike 不同，
 * 这里统一转换，避免各页面再手写一遍。
 */
export function musicItemToQueueItem(item: MusicItem, fallbackCover: string = ''): SongInfo {
  const cover = item.pic.length > 0 ? item.pic : fallbackCover;
  return {
    id: item.id,
    songmid: item.id,
    url: '',
    title: item.name,
    artist: item.singer,
    album: item.album,
    artwork: cover.length > 0 ? cover : null,
    duration: item.duration,
    source: item.source,
  };
}
