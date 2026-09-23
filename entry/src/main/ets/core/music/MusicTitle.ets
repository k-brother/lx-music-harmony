/**
 * 歌曲标题拼装（歌名 / 歌手顺序）与文件名词干
 *
 * 对齐安卓版 `download.fileName` 设置：
 * - 下载保存的文件名、歌词/封面缓存文件名、分享文案标题都走这一处；
 * - 之前三处文件命名 + 两处分享文案各写了一遍 `name + ' - ' + singer`，
 *   一旦用户想改成「歌手 - 歌名」就得改四个地方，且分享文案永远改不动。
 *
 * 类型定义放在 core：service 层（SettingsTypes）反过来依赖它，
 * 与 `S2TMode` 的处理方式保持一致，避免 core 依赖 service。
 */
import type { MusicInfo } from '../../types/MusicTypes';

/** 文件名/分享标题格式（对齐安卓版 `download.fileName` 的三个取值） */
export type DownloadFileNameFormat = 'name-singer' | 'singer-name' | 'name';

/** 全部格式（顺序即设置面板顺序） */
export const DOWNLOAD_FILE_NAME_FORMATS: DownloadFileNameFormat[] =
  ['name-singer', 'singer-name', 'name'];

/** 持久化值容错：非法值回落到「歌名 - 歌手」 */
export function toDownloadFileNameFormat(value: string): DownloadFileNameFormat {
  if (value === 'singer-name' || value === 'name') {
    return value;
  }
  return 'name-singer';
}

/** 歌名 + 歌手，按设置决定顺序；歌手为空时只给歌名 */
export function formatMusicTitle(musicInfo: MusicInfo, format: DownloadFileNameFormat): string {
  const name = musicInfo.name ?? '';
  const singer = musicInfo.singer ?? '';
  if (singer.length === 0) {
    return name;
  }
  if (format === 'name') {
    return name;
  }
  if (format === 'singer-name') {
    return `${singer} - ${name}`;
  }
  return `${name} - ${singer}`;
}

/** 去掉文件系统非法字符，得到安全文件名（所有落盘文件共用） */
export function sanitizeFileStem(stem: string): string {
  const cleaned = stem
    .replace(/[<>:"/\\|?*]/g, '_')
    .replace(/\s+/g, ' ')
    .trim();
  return cleaned.length > 0 ? cleaned : 'unknown';
}

/** 下载文件名词干（含扩展名由调用方补） */
export function buildMusicFileStem(musicInfo: MusicInfo, format: DownloadFileNameFormat): string {
  return sanitizeFileStem(formatMusicTitle(musicInfo, format));
}
