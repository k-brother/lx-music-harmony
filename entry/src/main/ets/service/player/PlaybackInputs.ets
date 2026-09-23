/**
 * 播放入参的准备与校验
 *
 * PlayerService.setSource 里原先夹着两段与播控无关的代码：
 * 队列项 → 平台音乐对象（喂给播控中心/歌词/播放历史）的字段映射，
 * 以及播放地址的合法性判断。抽到这里之后，setSource 只剩「状态流转 + 调底层」。
 */
import type { MusicInfo, MusicSource } from '../../types/MusicTypes';
import { formatPlayTime } from '../../utils/CommonUtils';
import { asText } from '../../utils/ValueCoerce';
import type { SongInfo } from '../PlayerService';

/** 允许的播放地址协议（网络地址、文件描述符、本地文件） */
const ALLOWED_SCHEMES: string[] = ['http://', 'https://', 'fd://', 'file://'];

/**
 * 校验播放地址；返回空串表示可用，否则返回给调用方抛错的说明。
 *
 * 提前拦截的好处是错误信息是「哪首歌、什么问题」，
 * 而不是底层解码器抛出的「参数错误」。
 */
export function validatePlayUrl(url: string, title: string): string {
  if (!url || url.trim().length === 0) {
    return `Invalid URL for song: ${title}`;
  }
  for (let i = 0; i < ALLOWED_SCHEMES.length; i++) {
    if (url.startsWith(ALLOWED_SCHEMES[i])) {
      return '';
    }
  }
  return `Invalid URL format for song: ${title}`;
}

/**
 * 播放队列项 → 平台音乐对象。
 *
 * 播控中心（锁屏/控制中心/灵动岛）、歌词请求、播放历史都吃这个形状；
 * 空封面与空专辑统一转成 undefined，避免下游拿到空字符串当有效值。
 *
 * 所有文本字段强制走 asText：各源 JSON 里的 id/albumId 经常是数字
 * （酷狗 Audioid、酷我 id、咪咕 songId），直接透传会让系统播控拒收元数据
 * ——真机表现为「这首歌进不了灵动岛/播控中心」，日志里是
 * `[GetAssetId] invalid type → Failed to set AVMetadata: get metaData failed`。
 */
export function songInfoToMusicInfo(song: SongInfo): MusicInfo {
  const artwork: string | undefined = asText(song.artwork);
  const album: string | undefined = asText(song.album);
  const source: MusicSource = asText(song.source, 'local') as MusicSource;
  const songmid: string = asText(song.songmid, asText(song.id));
  const id: string = asText(song.id, songmid);
  return {
    id: id,
    songmid: songmid,
    hash: asText(song.hash),
    strMediaMid: asText(song.strMediaMid),
    songId: song.songId,
    albumId: asText(song.albumId),
    copyrightId: asText(song.copyrightId),
    img: artwork ?? null,
    pic: artwork,
    lrc: null,
    name: asText(song.title),
    singer: asText(song.artist),
    source: source,
    interval: song.duration > 0 ? formatPlayTime(song.duration) : null,
    albumName: album ?? '',
    album: album ?? '',
  };
}
