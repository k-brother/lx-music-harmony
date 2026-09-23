/**
 * 歌曲详情页地址（对齐安卓版 `musicSdk[source].getMusicDetailPageUrl`）
 *
 * 分享/复制歌曲信息时带上详情页链接，接收方可直接打开对应平台页面；
 * 本地音乐没有在线详情页，返回空串（与安卓版一致）。
 */
import type { MusicInfo } from '../../types/MusicTypes';
import { settingsService } from '../../service/SettingsService';
import { formatMusicTitle } from './MusicTitle';

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

/**
 * 分享文案：歌曲信息 + 详情页链接（与安卓版 shareMusic 拼装规则一致）
 *
 * 标题部分走「设置 → 下载 → 下载文件名」的格式（安卓版同样用 `download.fileName`
 * 生成分享标题），因此改设置后分享与下载命名保持一致。
 */
export function buildShareText(musicInfo: MusicInfo, extra: string = ''): string {
  const title = formatMusicTitle(musicInfo, settingsService.get().downloadFileName);
  const album = musicInfo.albumName ?? musicInfo.album ?? '';
  const detailUrl = getMusicDetailPageUrl(musicInfo);
  let body = title;
  if (album.length > 0) {
    body = `${body} · ${album}`;
  }
  if (extra.length > 0) {
    body = `${body} · ${extra}`;
  }
  return detailUrl.length > 0 ? `${body}\n${detailUrl}` : body;
}
