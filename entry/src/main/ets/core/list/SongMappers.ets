/**
 * 歌曲对象转换（列表项 ↔ 播放项 ↔ 平台音乐对象）
 *
 * 这些转换原先散落在歌单详情页里（各 20~30 行、字段顺序还不一致），
 * 现在收敛到一处：任何页面要"把列表行变成可播放/可下载的对象"都用这里。
 */
import type { MusicInfo, MusicSource } from '../../types/MusicTypes';
import { formatClock } from '../../utils/FormatTools';
import { asText } from '../../utils/ValueCoerce';
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


/** 列表行 -> 平台音乐对象（取链、评论、分享、详情页链接都用它） */
export function songRowToMusicInfo(song: SongRowLike): MusicInfo {
  // id/songmid 必须字符串化：源 JSON 里可能是数字，透传到系统播控会被拒收元数据
  const songmid: string = asText(song.songmid, asText(song.id));
  const id: string = asText(song.id, songmid);
  const pic: string = asText(song.pic);
  return {
    id: id,
    name: asText(song.name),
    singer: asText(song.singer),
    source: asText(song.source, 'kw') as MusicSource,
    songmid: songmid,
    strMediaMid: asText(song.strMediaMid),
    hash: asText(song.hash),
    copyrightId: asText(song.copyrightId),
    albumId: asText(song.albumId),
    albumName: asText(song.album),
    album: asText(song.album),
    interval: secondsToInterval(song.duration),
    img: pic.length > 0 ? pic : null,
    pic: pic.length > 0 ? pic : undefined,
    lrc: null,
  };
}

/** 列表行 -> 本地列表项（加入我的列表时用） */
export function songRowToListItem(song: SongRowLike): MusicItem {
  return {
    id: asText(song.id, asText(song.songmid)),
    name: asText(song.name),
    singer: asText(song.singer),
    album: asText(song.album),
    albumId: asText(song.albumId) || null,
    duration: song.duration,
    source: asText(song.source, 'kw'),
    pic: asText(song.pic),
    lrc: null,
  };
}

/** 列表行 -> 播放队列项（url 留空由播放器按索引取链） */
export function songRowToQueueItem(song: SongRowLike, url: string = '', fallbackCover: string = ''): SongInfo {
  const songmid: string = asText(song.songmid, asText(song.id));
  const cover: string = asText(song.pic, fallbackCover);
  return {
    id: asText(song.id, songmid),
    songmid: songmid,
    url,
    title: asText(song.name),
    artist: asText(song.singer),
    album: asText(song.album),
    artwork: cover.length > 0 ? cover : null,
    duration: song.duration,
    source: asText(song.source, 'kw'),
    hash: asText(song.hash),
    strMediaMid: asText(song.strMediaMid),
    albumId: asText(song.albumId),
    copyrightId: asText(song.copyrightId),
  };
}

/**
 * 本地列表项 -> 播放队列项
 *
 * 队列补全时拿到的是 MusicItem（已经落库的形状），字段名与 SongRowLike 不同，
 * 这里统一转换，避免各页面再手写一遍。
 */
export function musicItemToQueueItem(item: MusicItem, fallbackCover: string = ''): SongInfo {
  const id: string = asText(item.id);
  const cover: string = asText(item.pic, fallbackCover);
  return {
    id: id,
    songmid: id,
    url: '',
    title: asText(item.name),
    artist: asText(item.singer),
    album: asText(item.album),
    artwork: cover.length > 0 ? cover : null,
    duration: item.duration,
    source: asText(item.source, 'kw'),
  };
}
