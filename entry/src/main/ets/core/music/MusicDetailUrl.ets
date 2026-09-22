/**
 * 歌曲详情页地址（对齐安卓版 `musicSdk[source].getMusicDetailPageUrl`）
 *
 * 分享/复制歌曲信息时带上详情页链接，接收方可直接打开对应平台页面；
 * 本地音乐没有在线详情页，返回空串（与安卓版一致）。
 */
import type { MusicInfo } from '../../types/MusicTypes';

export function getMusicDetailPageUrl(musicInfo: MusicInfo): string {
  const source = musicInfo.source as string;
  const songmid = musicInfo.songmid || musicInfo.id || '';
  switch (source) {
    case 'kw':
      return songmid.length > 0 ? `http://www.kuwo.cn/play_detail/${songmid}` : '';
    case 'tx':
      return songmid.length > 0 ? `https://y.qq.com/n/yqq/song/${songmid}.html` : '';
    case 'wy':
      return songmid.length > 0 ? `https://music.163.com/#/song?id=${songmid}` : '';
    case 'kg':
      return musicInfo.hash
        ? `https://www.kugou.com/song/#hash=${musicInfo.hash}&album_id=${musicInfo.albumId ?? ''}`
        : '';
    case 'mg':
      return musicInfo.copyrightId
        ? `http://music.migu.cn/v3/music/song/${musicInfo.copyrightId}`
        : '';
    default:
      // 本地音乐 / 未知音源：没有在线详情页
      return '';
  }
}

/** 分享文案：歌曲信息 + 详情页链接（与安卓版 shareMusic 拼装规则一致） */
export function buildShareText(musicInfo: MusicInfo, extra: string = ''): string {
  const name = musicInfo.name ?? '';
  const singer = musicInfo.singer ?? '';
  const album = musicInfo.albumName ?? musicInfo.album ?? '';
  const title = album.length > 0 ? `${name} - ${singer} · ${album}` : `${name} - ${singer}`;
  const detailUrl = getMusicDetailPageUrl(musicInfo);
  const body = extra.length > 0 ? `${title} · ${extra}` : title;
  return detailUrl.length > 0 ? `${body}\n${detailUrl}` : body;
}
