/**
 * 本地音乐解析（从 ResolvePlayback 抽出）
 *
 * 职责：扫描目录、读取元数据（AVMetadataExtractor）、本地取链/封面/歌词、
 * 本地条目转在线结构、内嵌封面提取与文件信息工具。
 *
 * 与在线解析完全独立：在线那套走音源 SDK + 缓存，本地这套走文件系统，
 * 分开后各自演进不会互相影响（也便于按平台裁剪）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { image } from '@kit.ImageKit';
import type { MusicInfo, LyricInfo, MusicQualityType } from '../../../types/MusicTypes';
import { buildLyricInfo, createEmptyLyricInfo } from '../MusicParsingUtils';
import { getMusicUrl, getLyricInfo, getPicUrl } from '../ResolvePlayback';
import { formatBytes } from '../../../utils/FormatTools';
import { readSidecarLyric } from './LocalLyricFile';

const TAG_LOCAL = 'LOCAL_MUSIC';
const DOMAIN_LOCAL = 0x0003;

// 本地音乐信息接口
export interface LocalMusicInfo {
  id: string;
  name: string;
  singer: string;
  album: string;
  duration: number;
  interval: string;
  filePath: string;
  size: number;
  picUrl?: string;
}

/**
 * 本地音频扩展名（小写，含点）
 */
const LOCAL_AUDIO_EXTENSIONS: string[] = [
  '.mp3', '.flac', '.m4a', '.aac', '.wav', '.ogg', '.opus', '.wma', '.ape', '.mgg', '.mflac'
];

function isAudioFile(fileName: string): boolean {
  const lower = fileName.toLowerCase();
  for (let i = 0; i < LOCAL_AUDIO_EXTENSIONS.length; i++) {
    if (lower.endsWith(LOCAL_AUDIO_EXTENSIONS[i])) {
      return true;
    }
  }
  return false;
}

function formatDurationText(durationMs: number): string {
  const totalSec = Math.max(0, Math.floor(durationMs / 1000));
  const minutes = Math.floor(totalSec / 60);
  const seconds = totalSec % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

/**
 * 用系统 AVMetadataExtractor 读取本地音频的标题/歌手/专辑/时长。
 * 读不到时返回 null，由调用方用文件名兜底。
 */
async function extractLocalMetadata(filePath: string): Promise<LocalMusicInfo | null> {
  let file: fs.File | null = null;
  let extractor: media.AVMetadataExtractor | null = null;
  try {
    file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(filePath);
    extractor = await media.createAVMetadataExtractor();
    extractor.fdSrc = { fd: file.fd };
    const meta = await extractor.fetchMetadata();
    const durationMs = parseInt(meta.duration ?? '0');
    const fileName = filePath.substring(filePath.lastIndexOf('/') + 1);
    const nameFromFile = fileName.replace(/\.[^.]+$/, '');
    const info: LocalMusicInfo = {
      id: filePath,
      name: meta.title && meta.title.length > 0 ? meta.title : nameFromFile,
      singer: meta.artist && meta.artist.length > 0 ? meta.artist : (meta.albumArtist ?? ''),
      album: meta.album ?? '',
      duration: isNaN(durationMs) ? 0 : durationMs,
      interval: formatDurationText(isNaN(durationMs) ? 0 : durationMs),
      filePath: filePath,
      size: stat.size,
    };
    return info;
  } catch (err) {
    hilog.warn(DOMAIN_LOCAL, TAG_LOCAL, 'extractLocalMetadata failed (%{public}s): %{public}s',
      filePath, err instanceof Error ? err.message : JSON.stringify(err));
    return null;
  } finally {
    if (extractor !== null) {
      try {
        await extractor.release();
      } catch (releaseErr) {
        hilog.warn(DOMAIN_LOCAL, TAG_LOCAL, 'extractor release failed');
      }
    }
    if (file !== null) {
      fs.closeSync(file);
    }
  }
}

/**
 * 扫描本地音乐目录（递归一层子目录），返回可播放的曲目列表。
 */
export async function scanLocalMusic(dirPath: string): Promise<LocalMusicInfo[]> {
  hilog.info(DOMAIN_LOCAL, TAG_LOCAL, 'Scanning local music: %{public}s', dirPath);
  const results: LocalMusicInfo[] = [];
  if (!dirPath || dirPath.length === 0) {
    return results;
  }

  const candidates: string[] = [];
  try {
    const rootFiles = fs.listFileSync(dirPath);
    for (let i = 0; i < rootFiles.length; i++) {
      const name = rootFiles[i];
      const fullPath = `${dirPath}/${name}`;
      try {
        if (fs.statSync(fullPath).isDirectory()) {
          const subFiles = fs.listFileSync(fullPath);
          for (let j = 0; j < subFiles.length; j++) {
            if (isAudioFile(subFiles[j])) {
              candidates.push(`${fullPath}/${subFiles[j]}`);
            }
          }
        } else if (isAudioFile(name)) {
          candidates.push(fullPath);
        }
      } catch (statErr) {
        hilog.warn(DOMAIN_LOCAL, TAG_LOCAL, 'scan skip %{public}s', name);
      }
    }
  } catch (err) {
    hilog.warn(DOMAIN_LOCAL, TAG_LOCAL, 'scanLocalMusic failed: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    return results;
  }

  for (let i = 0; i < candidates.length; i++) {
    const info = await extractLocalMetadata(candidates[i]);
    if (info) {
      results.push(info);
    }
  }
  hilog.info(DOMAIN_LOCAL, TAG_LOCAL, 'Scan finished: %{public}d tracks', results.length);
  return results;
}

// 本地音乐 URL 获取参数接口
interface LocalGetMusicUrlParams {
  musicInfo: LocalMusicInfo;
  isRefresh?: boolean;
  allowToggleSource?: boolean;
  onToggleSource?: ((musicInfo?: MusicInfo) => void) | null;
}

/**
 * 获取本地音乐URL
 */
export async function getLocalMusicUrl(params: LocalGetMusicUrlParams): Promise<string> {
  const musicInfo: LocalMusicInfo = params.musicInfo;
  const isRefresh: boolean = params.isRefresh ?? false;
  const allowToggleSource: boolean = params.allowToggleSource ?? true;
  const onToggleSource = params.onToggleSource;

  // 如果是本地文件路径，直接返回文件路径（由播放器负责打开）
  // 注意：不在此处调用 openSync，避免 FD 泄漏；播放器会自己打开文件
  if (musicInfo.filePath) {
    return `file://${musicInfo.filePath}`;
  }

  // 尝试从其他源获取在线URL
  if (allowToggleSource) {
    try {
      const onlineMusicInfo = localToOnlineMusicInfo(musicInfo);
      const url = await getMusicUrl({
        musicInfo: onlineMusicInfo,
        isRefresh,
        allowToggleSource: false,
        onToggleSource,
      });
      if (url) {
        return url;
      }
    } catch (err) {
      hilog.warn(DOMAIN_LOCAL, TAG_LOCAL, 'getLocalMusicUrl online fetch failed: %{public}s', (err as Error).message);
    }
  }

  throw new Error('Failed to get local music url');
}

// 本地音乐封面获取参数接口
interface LocalGetPicUrlParams {
  musicInfo: LocalMusicInfo;
  isRefresh?: boolean;
  allowToggleSource?: boolean;
  onToggleSource?: ((musicInfo?: MusicInfo) => void) | null;
}

/**
 * 获取本地音乐封面
 */
export async function getLocalPicUrl(params: LocalGetPicUrlParams): Promise<string> {
  const musicInfo: LocalMusicInfo = params.musicInfo;
  const isRefresh: boolean = params.isRefresh ?? false;
  const onToggleSource = params.onToggleSource;
  const allowToggleSource: boolean = params.allowToggleSource ?? true;

  // 如果已经有封面，直接返回
  if (musicInfo.picUrl && !isRefresh) {
    return musicInfo.picUrl;
  }

  // 尝试从文件读取封面
  try {
    const embeddedPic = await readEmbeddedPic(musicInfo.filePath);
    if (embeddedPic) {
      return embeddedPic;
    }
  } catch (err) {
    hilog.warn(DOMAIN_LOCAL, TAG_LOCAL, 'readEmbeddedPic failed: %{public}s', (err as Error).message);
  }

  // 尝试从在线源获取
  if (allowToggleSource) {
    try {
      const onlineMusicInfo = localToOnlineMusicInfo(musicInfo);
      const url = await getPicUrl({
        musicInfo: onlineMusicInfo,
        isRefresh,
        onToggleSource,
      });
      return url;
    } catch (err) {
      hilog.warn(DOMAIN_LOCAL, TAG_LOCAL, 'getLocalPicUrl online fetch failed: %{public}s', (err as Error).message);
    }
  }

  return musicInfo.picUrl || '';
}

// 本地音乐歌词获取参数接口
interface LocalGetLyricInfoParams {
  musicInfo: LocalMusicInfo;
  isRefresh?: boolean;
  onToggleSource?: ((musicInfo?: MusicInfo) => void) | null;
}

/**
 * 获取本地音乐歌词
 */
export async function getLocalLyricInfo(params: LocalGetLyricInfoParams): Promise<LyricInfo> {
  const musicInfo: LocalMusicInfo = params.musicInfo;
  const isRefresh: boolean = params.isRefresh ?? false;
  const onToggleSource = params.onToggleSource;

  // 尝试从歌词文件读取
  try {
    const lyricInfo = await readLyricFile(musicInfo.filePath);
    if (lyricInfo) {
      return buildLyricInfo(lyricInfo);
    }
  } catch (err) {
    hilog.warn(DOMAIN_LOCAL, TAG_LOCAL, 'readLyricFile failed: %{public}s', (err as Error).message);
  }

  // 尝试从在线源获取
  try {
    const onlineMusicInfo = localToOnlineMusicInfo(musicInfo);
    const lyric = await getLyricInfo({
      musicInfo: onlineMusicInfo,
      isRefresh,
      onToggleSource,
    });
    return lyric;
  } catch (err) {
    hilog.warn(DOMAIN_LOCAL, TAG_LOCAL, 'getLocalLyricInfo online fetch failed: %{public}s', (err as Error).message);
  }

  return createEmptyLyricInfo();
}

/**
 * 将本地音乐信息转换为在线音乐信息
 */
export function localToOnlineMusicInfo(localInfo: LocalMusicInfo): MusicInfo {
  const types: MusicQualityType[] = [{ type: '128k', size: null }];
  return {
    id: localInfo.id,
    name: localInfo.name,
    singer: localInfo.singer,
    source: 'local',
    songmid: localInfo.id,
    albumId: '',
    albumName: localInfo.album,
    interval: localInfo.interval,
    img: localInfo.picUrl || '',
    lrc: null,
    otherSource: null,
    types: types,
    _types: new Map(),
    typeUrl: new Map(),
    copyrightId: '',
  };
}

/**
 * 检查文件是否存在
 */
/**
 * 读取音频文件内嵌封面并缓存为同目录图片文件，返回可直接给 Image 用的路径。
 * 封面较大时只在首次读取时解码，后续命中缓存。
 */
async function readEmbeddedPic(filePath: string): Promise<string | null> {
  if (!filePath || filePath.length === 0) {
    return null;
  }
  const coverPath = `${filePath}.cover.jpg`;
  try {
    if (fs.accessSync(coverPath)) {
      return coverPath;
    }
  } catch (accessErr) {
    // 还没有缓存，继续提取
  }

  let file: fs.File | null = null;
  let extractor: media.AVMetadataExtractor | null = null;
  let packer: image.ImagePacker | null = null;
  try {
    file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
    extractor = await media.createAVMetadataExtractor();
    extractor.fdSrc = { fd: file.fd };
    const cover: image.PixelMap = await extractor.fetchAlbumCover();
    packer = image.createImagePacker();
    const packed: ArrayBuffer = await packer.packing(cover, { format: 'image/jpeg', quality: 85 });
    const out: fs.File = fs.openSync(coverPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
    try {
      fs.writeSync(out.fd, packed);
    } finally {
      fs.closeSync(out);
    }
    hilog.info(DOMAIN_LOCAL, TAG_LOCAL, 'Embedded cover extracted: %{public}s', coverPath);
    return coverPath;
  } catch (err) {
    hilog.info(DOMAIN_LOCAL, TAG_LOCAL, 'No embedded cover for %{public}s: %{public}s',
      filePath, err instanceof Error ? err.message : '');
    return null;
  } finally {
    if (packer !== null) {
      try {
        await packer.release();
      } catch (packErr) {
        hilog.warn(DOMAIN_LOCAL, TAG_LOCAL, 'packer release failed');
      }
    }
    if (extractor !== null) {
      try {
        await extractor.release();
      } catch (releaseErr) {
        hilog.warn(DOMAIN_LOCAL, TAG_LOCAL, 'extractor release failed');
      }
    }
    if (file !== null) {
      fs.closeSync(file);
    }
  }
}

/**
 * 读取同名歌词文件（.lrc）
 *
 * 本地音乐最常见的整理方式是「音频与歌词同名放一起」，读到了就不必联网取词。
 * 读写实现在 core/music/local/LocalLyricFile（播放链路也用它）。
 */
async function readLyricFile(filePath: string): Promise<LyricInfo | null> {
  const text = await readSidecarLyric(filePath);
  return text === null ? null : { lyric: text };
}

/**
 * 获取支持的音乐格式
 */
export function getSupportedAudioFormats(): string[] {
  return ['.mp3', '.flac', '.m4a', '.aac', '.ogg', '.wav', '.opus', '.ape'];
}

/**
 * 获取单个音乐文件的元数据（标题/歌手/专辑/时长）。
 * 扫描目录时走同一实现；读不到标签时返回 null，由调用方用文件名兜底。
 */
export async function getMusicFileMetadata(filePath: string): Promise<LocalMusicInfo | null> {
  return await extractLocalMetadata(filePath);
}

/**
 * 格式化文件大小（规则统一在 utils/FormatTools，这里保留原函数名给既有调用方）
 */
export function formatFileSize(bytes: number): string {
  return formatBytes(bytes);
}

// 本地音乐模块接口

// ==================== 模块对象（供高级用法直接取用） ====================

interface LocalModule {
  scanLocalMusic: (dirPath: string) => Promise<LocalMusicInfo[]>;
  getMusicUrl: (params: LocalGetMusicUrlParams) => Promise<string>;
  getPicUrl: (params: LocalGetPicUrlParams) => Promise<string>;
  getLyricInfo: (params: LocalGetLyricInfoParams) => Promise<LyricInfo>;
  localToOnlineMusicInfo: (localInfo: LocalMusicInfo) => MusicInfo;
  getSupportedAudioFormats: () => string[];
  getMusicFileMetadata: (filePath: string) => Promise<LocalMusicInfo | null>;
  formatFileSize: (bytes: number) => string;
}

export const local: LocalModule = {
  scanLocalMusic,
  getMusicUrl: getLocalMusicUrl,
  getPicUrl: getLocalPicUrl,
  getLyricInfo: getLocalLyricInfo,
  localToOnlineMusicInfo,
  getSupportedAudioFormats,
  getMusicFileMetadata,
  formatFileSize,
};
