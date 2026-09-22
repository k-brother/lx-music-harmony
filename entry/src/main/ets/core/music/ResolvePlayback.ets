// 在线 + 本地播放解析（原 ResolveOnlinePlayback + ResolveLocalPlayback）

import { musicSdk, searchMusic as sdkSearchMusic } from './MusicSdkAggregate';
import type { MusicInfo, LyricInfo, Quality } from '../../types/MusicTypes';
import { getStorageService } from '../interfaces/IStorageService';
import { buildLyricInfo, createEmptyLyricInfo, getPlayQuality } from './MusicParsingUtils';
import {
  normalizeSingerText,
  normalizeCompareText,
  scoreCandidate,
  musicInfoTrace,
} from './playback/CandidateMatch';
import { pluginManager, PluginSongInfo as PluginSongInfoType } from '../plugin/PluginManager';
// 日志经由应用日志门面，既输出 hilog 也进入「设置 → 运行日志」
import { appLog as hilog } from '../log/AppLogger';
import { httpRequest } from '../network/http/HttpClient';
import { settingsService } from '../../service/SettingsService';
import {
  getCachedMusicUrl,
  saveMusicUrlToCache,
  clearCachedMusicUrl,
  getCachedLyricInfo,
  cacheNoLyric,
  saveLyricToCache,
} from './playback/PlaybackCache';
import { media } from '@kit.MediaKit';

const TAG = 'ONLINE_MUSIC';
const DOMAIN = 0x0003;

/** 各源列表/搜索常只带 id，下载与解析统一补全 songmid，避免误判无效 */
function ensureSongMid(musicInfo: MusicInfo): void {
  if ((!musicInfo.songmid || musicInfo.songmid.length === 0) && musicInfo.id && musicInfo.id.length > 0) {
    musicInfo.songmid = musicInfo.id;
  }
}

function isPluginPreferredForMusicUrl(musicInfo: MusicInfo): boolean {
  const source = musicInfo.source as string;
  const activePlugin = pluginManager.getActivePlugin();
  return source !== 'local' && !!(activePlugin && activePlugin.onGetMusicUrl);
}

function toPluginSongInfo(musicInfo: MusicInfo): PluginSongInfoType {
  const singerValue = normalizeSingerText(musicInfo.singer);
  return {
    songmid: musicInfo.songmid || musicInfo.id || '',
    name: musicInfo.name || '',
    singer: singerValue,
    source: musicInfo.source as string,
    albumName: musicInfo.album || musicInfo.albumName || '',
    albumId: musicInfo.albumId || '',
    duration: musicInfo.interval || '',
    hash: musicInfo.hash || musicInfo.songmid || musicInfo.id || '',
  };
}





let lazyCustomSourceRestorePromise: Promise<boolean> | null = null;

async function ensureCustomSourcePluginReady(): Promise<boolean> {
  const active = pluginManager.getActivePlugin();
  if (active && active.onGetMusicUrl) {
    return true;
  }
  if (lazyCustomSourceRestorePromise) {
    return await lazyCustomSourceRestorePromise;
  }
  lazyCustomSourceRestorePromise = (async (): Promise<boolean> => {
    try {
      const storage = getStorageService();
      const currentSource = await storage.getString('plugin.currentSource', 'kw');
      const customSourceUrl = await storage.getString('plugin.customSourceUrl', '');
      if (currentSource !== 'custom' || customSourceUrl.length === 0) {
        return false;
      }
      hilog.warn(DOMAIN, TAG, 'Lazy restoring custom source for playback: %{public}s', customSourceUrl);
      return await pluginManager.loadCustomSource(customSourceUrl);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Lazy custom source restore failed: %{public}s', JSON.stringify(err));
      return false;
    }
  })();
  try {
    return await lazyCustomSourceRestorePromise;
  } finally {
    lazyCustomSourceRestorePromise = null;
  }
}

/**
 * 获取音乐URL参数接口
 */
export interface GetMusicUrlParams {
  musicInfo: MusicInfo;
  quality?: Quality;
  isRefresh?: boolean;
  allowToggleSource?: boolean;
  onToggleSource?: ((musicInfo?: MusicInfo) => void) | null;
}

/**
 * 处理在线音乐URL获取参数接口
 */
interface HandleGetOnlineMusicUrlParams {
  musicInfo: MusicInfo;
  quality: Quality;
  isRefresh: boolean;
  allowToggleSource: boolean;
  onToggleSource?: ((musicInfo?: MusicInfo) => void) | null;
}

/**
 * 音乐URL结果对象接口
 */
interface MusicUrlResultObj {
  url: string;
  quality: Quality;
  musicInfo: MusicInfo;
  isFromCache: boolean;
  cacheMode: 'plugin' | 'builtin';
}

interface HeadProbeResponse {
  status: number;
}

/**
 * 从其他源获取音乐URL参数接口
 */
interface GetOnlineOtherSourceMusicUrlParams {
  musicInfos: MusicInfo[];
  quality: Quality;
  isRefresh: boolean;
  onToggleSource?: ((musicInfo?: MusicInfo) => void) | null;
  retryedSource?: string[];
}

/**
 * 处理在线歌词获取参数接口
 */
interface HandleGetOnlineLyricInfoParams {
  musicInfo: MusicInfo;
  isRefresh: boolean;
  allowToggleSource: boolean;
  onToggleSource?: ((musicInfo?: MusicInfo) => void) | null;
}

/**
 * 歌词结果对象接口
 */
interface LyricResultObj {
  lyricInfo: LyricInfo;
  musicInfo: MusicInfo;
  isFromCache: boolean;
}

function getInlinePic(musicInfo: MusicInfo): string {
  return (musicInfo.img || musicInfo.pic || '').trim();
}


/** 源明确返回"无歌词"时的占位文案（判断用，不做展示） */
const NO_LYRIC_MARKERS: string[] = ['暂无歌词', '纯音乐', '没有歌词', '无歌词'];
/** "无歌词"负缓存标记与有效期（24 小时） */
const NO_LYRIC_CACHE_PREFIX = '#no-lyric#';
const NO_LYRIC_CACHE_TTL_MS = 24 * 60 * 60 * 1000;

function hasLyricContent(lyricInfo: LyricInfo | null | undefined): boolean {
  if (!lyricInfo) {
    return false;
  }
  const lyric = (lyricInfo.lyric ?? '').trim();
  if (lyric.length === 0) {
    return false;
  }
  for (let i = 0; i < NO_LYRIC_MARKERS.length; i++) {
    if (lyric.includes(NO_LYRIC_MARKERS[i])) {
      return false;
    }
  }
  return true;
}

/**
 * 获取歌词信息参数接口
 */
export interface GetLyricInfoParams {
  musicInfo: MusicInfo;
  isRefresh?: boolean;
  allowToggleSource?: boolean;
  onToggleSource?: ((musicInfo?: MusicInfo) => void) | null;
}

/**
 * 获取封面图片URL参数接口
 */
export interface GetPicUrlParams {
  musicInfo: MusicInfo;
  listId?: string;
  isRefresh?: boolean;
  allowToggleSource?: boolean;
  onToggleSource?: ((musicInfo?: MusicInfo) => void) | null;
}

/**
 * 处理在线封面获取参数接口
 */
interface HandleGetOnlinePicUrlParams {
  musicInfo: MusicInfo;
  isRefresh: boolean;
  allowToggleSource: boolean;
  onToggleSource?: ((musicInfo?: MusicInfo) => void) | null;
}

/**
 * 获取在线音乐播放URL
 */
export async function getMusicUrl(params: GetMusicUrlParams): Promise<string | null> {
  const musicInfo = params.musicInfo;
  const quality = params.quality;
  const isRefresh = params.isRefresh ?? false;
  const allowToggleSource = params.allowToggleSource ?? true;
  const onToggleSource = params.onToggleSource;

  if (!musicInfo) {
    return null;
  }
  ensureSongMid(musicInfo);
  if (!musicInfo.songmid || musicInfo.songmid.length === 0) {
    return null;
  }

  // 获取目标音质：未显式指定时跟随「设置 -> 播放设置 -> 高品质音乐」
  const preferredQuality: Quality = quality ?? settingsService.get().playQuality;
  const targetQuality = getPlayQuality(preferredQuality, musicInfo);
  const pluginPreferred = isPluginPreferredForMusicUrl(musicInfo);

  // 尝试从缓存获取
  const cacheMode: 'plugin' | 'builtin' = pluginPreferred ? 'plugin' : 'builtin';
  const cachedUrl = await getCachedMusicUrl(musicInfo, targetQuality, cacheMode);
  if (cachedUrl && !isRefresh) {
    const cachedPlayable = await isPlayableMediaUrl(cachedUrl);
    if (cachedPlayable) {
      hilog.warn(DOMAIN, TAG, 'Using cached URL (pluginPreferred=%{public}s)', pluginPreferred.toString());
      return cachedUrl;
    }
    hilog.warn(DOMAIN, TAG, 'Cached music url is not playable, refreshing from source');
    await clearCachedMusicUrl(musicInfo, targetQuality, cacheMode);
  }

  try {
    // 直接从当前源获取URL
    const result = await handleGetOnlineMusicUrl({
      musicInfo,
      quality: targetQuality,
      isRefresh,
      allowToggleSource,
      onToggleSource,
    });

    // 缓存URL
    if (result.url) {
      await saveMusicUrlToCache(musicInfo, result.quality, result.url, result.cacheMode);
    }

    return result.url;
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : 'Unknown error';
    hilog.error(DOMAIN, TAG, 'getMusicUrl failed: %{public}s', errMsg);
    return null;
  }
}

/**
 * 处理在线音乐URL获取
 */
async function handleGetOnlineMusicUrl(params: HandleGetOnlineMusicUrlParams): Promise<MusicUrlResultObj> {
  const musicInfo = params.musicInfo;
  const quality = params.quality;
  const allowToggleSource = params.allowToggleSource;
  const onToggleSource = params.onToggleSource;

  try {
    // 调用对应音乐源的getMusicUrl
    const result = await getMusicUrlFromSource(musicInfo, quality);

    if (result && result.url) {
      const playable = await isPlayableMediaUrl(result.url);
      if (!playable) {
        throw new Error('Source returned unplayable media url');
      }
      const retObj: MusicUrlResultObj = {
        url: result.url,
        quality: result.type as Quality,
        musicInfo,
        isFromCache: false,
        cacheMode: result.mode,
      };
      return retObj;
    }

    throw new Error('Failed to get music url');
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : 'Unknown error';
    hilog.error(DOMAIN, TAG, 'handleGetOnlineMusicUrl error: %{public}s', errMsg);

    if (!allowToggleSource) {
      throw new Error(errMsg);
    }

    // 尝试从其他源获取
    if (onToggleSource) {
      onToggleSource();
    }

    const otherSource = await getOtherSource(musicInfo);
    if (otherSource.length > 0) {
      return getOnlineOtherSourceMusicUrl({
        musicInfos: otherSource,
        quality,
        isRefresh: params.isRefresh,
        onToggleSource,
        retryedSource: [musicInfo.source as string],
      });
    }

    throw new Error('All sources failed');
  }
}

async function isPlayableMediaUrl(url: string): Promise<boolean> {
  if (!url || url.length === 0) {
    return false;
  }
  if (url.startsWith('file://')) {
    return true;
  }
  try {
    const headTask = httpRequest(url, {
      method: 'HEAD',
      connectTimeout: 5000,
      readTimeout: 5000,
      responseType: 'text',
    });
    const headResp = await headTask.promise as HeadProbeResponse;
    if (headResp.status >= 200 && headResp.status < 400) {
      return true;
    }
    // 部分源站不支持 HEAD 或拒绝 HEAD（403/405/501），降级为小范围 GET 探测
    if (headResp.status !== 403 && headResp.status !== 405 && headResp.status !== 501) {
      hilog.warn(DOMAIN, TAG, 'Media URL probe failed with status: %{public}d', headResp.status);
      return false;
    }
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'HEAD probe failed: %{public}s', (err as Error).message);
  }

  try {
    const getTask = httpRequest(url, {
      method: 'GET',
      header: {
        'Range': 'bytes=0-1',
      },
      connectTimeout: 5000,
      readTimeout: 5000,
      responseType: 'text',
    });
    const getResp = await getTask.promise as HeadProbeResponse;
    if (getResp.status >= 200 && getResp.status < 400) {
      return true;
    }
    hilog.warn(DOMAIN, TAG, 'GET probe failed with status: %{public}d', getResp.status);
    return false;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'GET probe failed: %{public}s', (err as Error).message);
    return false;
  }
}

/**
 * 从其他源获取音乐URL
 */
async function getOnlineOtherSourceMusicUrl(params: GetOnlineOtherSourceMusicUrlParams): Promise<MusicUrlResultObj> {
  const musicInfos = params.musicInfos;
  const quality = params.quality;
  const onToggleSource = params.onToggleSource;
  const retryedSource: string[] = params.retryedSource ?? [];

  // 遍历音乐源列表
  for (const mInfo of musicInfos) {
    if (retryedSource.includes(mInfo.source as string)) {
      continue;
    }

    retryedSource.push(mInfo.source as string);

    hilog.info(DOMAIN, TAG, 'try toggle to: %{public}s %{public}s', mInfo.source, mInfo.name);
    if (onToggleSource) {
      onToggleSource(mInfo);
    }

    try {
      const result = await getMusicUrlFromSource(mInfo, quality);

      if (result && result.url) {
        const retObj: MusicUrlResultObj = {
          url: result.url,
          quality: result.type as Quality,
          musicInfo: mInfo,
          isFromCache: false,
          cacheMode: result.mode,
        };
        return retObj;
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Source failed, trying next: %{public}s', (err as Error).message);
    }
  }

  throw new Error('All sources failed');
}

/**
 * 音乐URL从源结果接口
 */
interface MusicUrlFromSourceResult {
  url: string;
  type: string;
  mode: 'plugin' | 'builtin';
}

/**
 * 从指定源获取音乐URL
 */
async function getMusicUrlFromSource(musicInfo: MusicInfo, quality: Quality): Promise<MusicUrlFromSourceResult | null> {
  const source = musicInfo.source as string;
  if (source !== 'local') {
    let activePlugin = pluginManager.getActivePlugin();
    if (!activePlugin || !activePlugin.onGetMusicUrl) {
      await ensureCustomSourcePluginReady();
      activePlugin = pluginManager.getActivePlugin();
    }
    if (activePlugin && activePlugin.onGetMusicUrl) {
      try {
        hilog.warn(DOMAIN, TAG, 'Route=plugin-first, source=%{public}s, quality=%{public}s', source, quality);
        const pluginSongInfo: PluginSongInfoType = {
          songmid: musicInfo.songmid || musicInfo.id || '',
          name: musicInfo.name || '',
          singer: musicInfo.singer || '',
          source: source,
          albumName: musicInfo.album || musicInfo.albumName || '',
          duration: musicInfo.interval || '',
          hash: musicInfo.hash || musicInfo.songmid || musicInfo.id || '',
        };
        const url = await activePlugin.onGetMusicUrl(pluginSongInfo, quality);
        if (url && url.length > 0) {
          hilog.warn(DOMAIN, TAG, 'Route=plugin-success, source=%{public}s', source);
          return { url, type: quality, mode: 'plugin' };
        }
        hilog.warn(DOMAIN, TAG, 'Plugin returned empty URL, fallback to builtin source');
      } catch (err) {
        const errMsg = err instanceof Error ? err.message : JSON.stringify(err);
        hilog.warn(DOMAIN, TAG, 'Plugin getMusicUrl failed, fallback to builtin source: %{public}s', errMsg);
      }
    }
  }

  switch (source) {
    case 'kw':
      {
        const result = await musicSdk.kw.getMusicUrl(musicInfo, quality);
        return result ? { url: result.url, type: result.type, mode: 'builtin' } : null;
      }
    case 'kg':
      {
        const result = await musicSdk.kg.getMusicUrl(musicInfo, quality);
        return result ? { url: result.url, type: result.type, mode: 'builtin' } : null;
      }
    case 'tx':
      {
        const result = await musicSdk.tx.getMusicUrl(musicInfo, quality);
        return result ? { url: result.url, type: result.type, mode: 'builtin' } : null;
      }
    case 'wy':
      {
        const result = await musicSdk.wy.getMusicUrl(musicInfo, quality);
        return result ? { url: result.url, type: result.type, mode: 'builtin' } : null;
      }
    case 'mg':
      {
        const result = await musicSdk.mg.getMusicUrl(musicInfo, quality);
        return result ? { url: result.url, type: result.type, mode: 'builtin' } : null;
      }
    default:
      return null;
  }
}

/**
 * 获取歌词信息
 */
export async function getLyricInfo(params: GetLyricInfoParams): Promise<LyricInfo> {
  const musicInfo = params.musicInfo;
  const isRefresh = params.isRefresh ?? false;
  const allowToggleSource = params.allowToggleSource ?? true;
  const onToggleSource = params.onToggleSource;

  if (!musicInfo) {
    return createEmptyLyricInfo();
  }
  ensureSongMid(musicInfo);
  if (!musicInfo.songmid || musicInfo.songmid.length === 0) {
    return createEmptyLyricInfo();
  }

  // 尝试从缓存获取
  if (!isRefresh) {
    const cachedLyric = await getCachedLyricInfo(musicInfo);
    if (cachedLyric) {
      return buildLyricInfo(cachedLyric);
    }
  }

  try {
    const result = await handleGetOnlineLyricInfo({
      musicInfo,
      isRefresh,
      allowToggleSource,
      onToggleSource,
    });

    // 缓存歌词
    await saveLyricToCache(musicInfo, result.lyricInfo);

    return buildLyricInfo(result.lyricInfo);
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : 'Unknown error';
    // "无歌词"是正常结果，返回空歌词让 UI 显示"纯音乐，请欣赏"
    if (errMsg === 'LyricNotAvailable') {
      hilog.info(DOMAIN, TAG, 'getLyricInfo: no lyric available, return empty');
      await cacheNoLyric(musicInfo);
    } else {
      hilog.error(DOMAIN, TAG, 'getLyricInfo failed: %{public}s', errMsg);
    }
    return createEmptyLyricInfo();
  }
}

/**
 * 处理在线歌词获取
 */
async function handleGetOnlineLyricInfo(params: HandleGetOnlineLyricInfoParams): Promise<LyricResultObj> {
  const musicInfo = params.musicInfo;
  const allowToggleSource = params.allowToggleSource;
  const onToggleSource = params.onToggleSource;

  try {
    hilog.info(DOMAIN, TAG, 'lyric fetch start: %{public}s', musicInfoTrace(musicInfo));
    const lyricInfo = await getLyricFromSource(musicInfo);

    if (hasLyricContent(lyricInfo)) {
      hilog.info(DOMAIN, TAG, 'lyric fetch success: %{public}s lyricLen=%{public}d',
        musicInfoTrace(musicInfo), (lyricInfo.lyric || '').length);
      const retObj: LyricResultObj = {
        lyricInfo,
        musicInfo,
        isFromCache: false,
      };
      return retObj;
    }

    // 源没有返回有效歌词（含"暂无歌词/纯音乐"标记）属于正常结果，交给上层展示占位文案
    hilog.info(DOMAIN, TAG, 'lyric not available from %{public}s, trying fallback sources', musicInfo.source);
    throw new Error('LyricNotAvailable');
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : 'Unknown error';
    if (errMsg === 'LyricNotAvailable') {
      hilog.info(DOMAIN, TAG, 'handleGetOnlineLyricInfo: no lyric from primary source');
    } else {
      hilog.error(DOMAIN, TAG, 'handleGetOnlineLyricInfo error: %{public}s', errMsg);
    }

    if (!allowToggleSource) {
      throw new Error(errMsg);
    }

    // 尝试从其他源获取
    if (onToggleSource) {
      onToggleSource();
    }

    const otherSource = await getOtherSource(musicInfo);
    if (otherSource.length > 0) {
      for (const mInfo of otherSource) {
        try {
          hilog.info(DOMAIN, TAG, 'lyric fallback source try: %{public}s', musicInfoTrace(mInfo));
          const lyricInfo = await getLyricFromSource(mInfo);
          if (hasLyricContent(lyricInfo)) {
            hilog.info(DOMAIN, TAG, 'lyric fallback source success: %{public}s lyricLen=%{public}d',
              musicInfoTrace(mInfo), (lyricInfo.lyric || '').length);
            const retObj: LyricResultObj = {
              lyricInfo,
              musicInfo: mInfo,
              isFromCache: false,
            };
            return retObj;
          }
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'Lyric source failed, trying next: %{public}s', (err as Error).message);
        }
      }
    }

    hilog.info(DOMAIN, TAG, 'No lyric found on any source for: %{public}s', musicInfoTrace(musicInfo));
    throw new Error('LyricNotAvailable');
  }
}

/**
 * 从指定源获取歌词
 */
async function getLyricFromSource(musicInfo: MusicInfo): Promise<LyricInfo> {
  const source = musicInfo.source as string;
  if (source !== 'local') {
    let activePlugin = pluginManager.getActivePlugin();
    if (!activePlugin || !activePlugin.onGetLyric) {
      await ensureCustomSourcePluginReady();
      activePlugin = pluginManager.getActivePlugin();
    }
    if (activePlugin && activePlugin.onGetLyric) {
      try {
        const pluginResult = await activePlugin.onGetLyric(toPluginSongInfo(musicInfo));
        if (pluginResult && pluginResult.lyric && pluginResult.lyric.length > 0) {
          hilog.warn(DOMAIN, TAG, 'Route=plugin-lyric-success, source=%{public}s', source);
          return {
            lyric: pluginResult.lyric || '',
            tlyric: pluginResult.tlyric || null,
            lxlyric: pluginResult.lxlyric || null,
            rlyric: pluginResult.rlyric || null,
          };
        }
        hilog.warn(DOMAIN, TAG, 'Plugin returned empty lyric, fallback to builtin source');
      } catch (err) {
        const errMsg = err instanceof Error ? err.message : JSON.stringify(err);
        hilog.warn(DOMAIN, TAG, 'Plugin lyric failed, fallback to builtin source: %{public}s', errMsg);
      }
    }
  }

  switch (source) {
    case 'kw':
      {
        const info = await musicSdk.kw.getLyric(musicInfo);
        hilog.info(DOMAIN, TAG, 'lyric source result kw: %{public}s lyricLen=%{public}d',
          musicInfoTrace(musicInfo), (info.lyric || '').length);
        return info;
      }
    case 'kg':
      {
        const info = await musicSdk.kg.getLyric(musicInfo);
        hilog.info(DOMAIN, TAG, 'lyric source result kg: %{public}s lyricLen=%{public}d',
          musicInfoTrace(musicInfo), (info.lyric || '').length);
        return info;
      }
    case 'tx':
      {
        const info = await musicSdk.tx.getLyric(musicInfo);
        hilog.info(DOMAIN, TAG, 'lyric source result tx: %{public}s lyricLen=%{public}d',
          musicInfoTrace(musicInfo), (info.lyric || '').length);
        return info;
      }
    case 'wy':
      {
        const info = await musicSdk.wy.getLyric(musicInfo);
        hilog.info(DOMAIN, TAG, 'lyric source result wy: %{public}s lyricLen=%{public}d',
          musicInfoTrace(musicInfo), (info.lyric || '').length);
        return info;
      }
    case 'mg':
      {
        const info = await musicSdk.mg.getLyric(musicInfo);
        hilog.info(DOMAIN, TAG, 'lyric source result mg: %{public}s lyricLen=%{public}d',
          musicInfoTrace(musicInfo), (info.lyric || '').length);
        return info;
      }
    default:
      return createEmptyLyricInfo();
  }
}

/**
 * 获取封面图片URL
 */
export async function getPicUrl(params: GetPicUrlParams): Promise<string> {
  const musicInfo = params.musicInfo;
  const isRefresh = params.isRefresh ?? false;
  const allowToggleSource = params.allowToggleSource ?? true;
  const onToggleSource = params.onToggleSource;

  if (!musicInfo) {
    return '';
  }
  ensureSongMid(musicInfo);
  if (!musicInfo.songmid || musicInfo.songmid.length === 0) {
    return '';
  }

  // 如果已经有封面URL，直接返回（兼容 img / pic）
  const inlinePic = getInlinePic(musicInfo);
  if (inlinePic.length > 0 && !isRefresh) {
    return inlinePic;
  }

  try {
    return await handleGetOnlinePicUrl({
      musicInfo,
      isRefresh,
      allowToggleSource,
      onToggleSource,
    });
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : 'Unknown error';
    hilog.error(DOMAIN, TAG, 'getPicUrl failed: %{public}s', errMsg);
    return getInlinePic(musicInfo);
  }
}

/**
 * 处理在线封面获取
 */
async function handleGetOnlinePicUrl(params: HandleGetOnlinePicUrlParams): Promise<string> {
  const musicInfo = params.musicInfo;
  const isRefresh = params.isRefresh;
  const allowToggleSource = params.allowToggleSource;
  const onToggleSource = params.onToggleSource;

  // 如果已经有封面，直接返回（兼容 img / pic）
  const inlinePic = getInlinePic(musicInfo);
  if (inlinePic.length > 0 && !isRefresh) {
    return inlinePic;
  }

  try {
    const picUrl = await getPicFromSource(musicInfo);
    if (picUrl) {
      return picUrl;
    }
    throw new Error('Failed to get pic');
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : 'Unknown error';
    hilog.error(DOMAIN, TAG, 'handleGetOnlinePicUrl error: %{public}s', errMsg);

    if (!allowToggleSource) {
      throw new Error(errMsg);
    }

    // 尝试从其他源获取
    if (onToggleSource) {
      onToggleSource();
    }

    const otherSource = await getOtherSource(musicInfo);
    if (otherSource.length > 0) {
      for (const mInfo of otherSource) {
        try {
          const picUrl = await getPicFromSource(mInfo);
          if (picUrl) {
            return picUrl;
          }
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'Pic source failed, trying next: %{public}s', (err as Error).message);
        }
      }
    }

    throw new Error('All pic sources failed');
  }
}

/**
 * 从指定源获取封面
 */
async function getPicFromSource(musicInfo: MusicInfo): Promise<string> {
  const source = musicInfo.source as string;
  if (source !== 'local') {
    let activePlugin = pluginManager.getActivePlugin();
    if (!activePlugin || !activePlugin.onGetPic) {
      await ensureCustomSourcePluginReady();
      activePlugin = pluginManager.getActivePlugin();
    }
    if (activePlugin && activePlugin.onGetPic) {
      try {
        const pluginPic = await activePlugin.onGetPic(toPluginSongInfo(musicInfo));
        if (pluginPic && pluginPic.length > 0) {
          hilog.warn(DOMAIN, TAG, 'Route=plugin-pic-success, source=%{public}s', source);
          return pluginPic;
        }
        hilog.warn(DOMAIN, TAG, 'Plugin returned empty pic, fallback to builtin source');
      } catch (err) {
        const errMsg = err instanceof Error ? err.message : JSON.stringify(err);
        hilog.warn(DOMAIN, TAG, 'Plugin pic failed, fallback to builtin source: %{public}s', errMsg);
      }
    }
  }

  switch (source) {
    case 'kw':
      return await musicSdk.kw.getPic(musicInfo);
    case 'kg':
      return await musicSdk.kg.getPic(musicInfo);
    case 'tx':
      return await musicSdk.tx.getPic(musicInfo);
    case 'wy':
      return await musicSdk.wy.getPic(musicInfo);
    case 'mg':
      return await musicSdk.mg.getPic(musicInfo);
    default:
      return '';
  }
}

/**
 * 获取其他源的音乐信息
 */
export async function getOtherSource(musicInfo: MusicInfo): Promise<MusicInfo[]> {
  try {
    const safeSinger = normalizeSingerText(musicInfo.singer);
    const keyword = `${musicInfo.name} ${safeSinger}`.trim();
    const baseName = normalizeCompareText(musicInfo.name || '');
    const baseSinger = normalizeCompareText(safeSinger);
    const results = await sdkSearchMusic(keyword, 1, 10);
    if (!results || results.length === 0) {
      hilog.warn(DOMAIN, TAG, 'getOtherSource empty search result: %{public}s', musicInfoTrace(musicInfo));
      return [];
    }
    const merged: MusicInfo[] = [];
    const seenKeys: Set<string> = new Set<string>();
    for (let i = 0; i < results.length; i++) {
      const group = results[i];
      if (!group || !group.list || group.list.length === 0) {
        continue;
      }
      for (let j = 0; j < group.list.length; j++) {
        const item = group.list[j];
        if (!item || item.source === musicInfo.source) {
          continue;
        }
        const itemSinger = normalizeSingerText(item.singer);
        const dedupeKey = `${item.source || ''}|${item.songmid || item.id || ''}|${item.name || ''}|${itemSinger}`;
        if (seenKeys.has(dedupeKey)) {
          continue;
        }
        seenKeys.add(dedupeKey);
        const normalizedItem: MusicInfo = item;
        normalizedItem.singer = itemSinger;
        merged.push(normalizedItem);
      }
    }
    merged.sort((a: MusicInfo, b: MusicInfo) => {
      const sa = scoreCandidate(baseName, baseSinger, a);
      const sb = scoreCandidate(baseName, baseSinger, b);
      return sb - sa;
    });
    const ranked = merged.slice(0, 12);
    hilog.info(DOMAIN, TAG, 'getOtherSource merged=%{public}d ranked=%{public}d for %{public}s',
      merged.length, ranked.length, musicInfoTrace(musicInfo));
    return ranked;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'getOtherSource failed: %{public}s', (err as Error).message);
    return [];
  }
}

/**
 * 搜索音乐（多源搜索）
 */
interface SearchMusicParams {
  name: string;
  singer?: string;
  limit?: number;
}

export async function searchMusic(params: SearchMusicParams): Promise<MusicInfo[]> {
  const name = params.name;
  const singer = params.singer;
  const limit = params.limit ?? 25;
  const keyword = `${name} ${singer || ''}`.trim();

  if (!keyword) {
    return [];
  }

  const sources = ['kw', 'kg', 'tx', 'wy', 'mg'];
  const results: MusicInfo[][] = [];

  // 并行搜索所有源
  const searchPromises: Promise<MusicInfo[]>[] = sources.map(async (source) => {
    try {
      const result = await searchFromSource(source, keyword, 1, limit);
      return result;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'searchFromSource failed for %{public}s: %{public}s', source, (err as Error).message);
      return [];
    }
  });

  const searchResults = await Promise.all(searchPromises);

  // 合并结果
  for (const result of searchResults) {
    if (result && result.length > 0) {
      results.push(result);
    }
  }

  // 返回第一个搜索结果（通常是最好的匹配）
  return results[0] || [];
}

/**
 * 从指定源搜索音乐
 */
async function searchFromSource(source: string, keyword: string, page: number, limit: number): Promise<MusicInfo[]> {
  const sdk = getSdkBySource(source);
  if (!sdk || !sdk.musicSearch) {
    return [];
  }

  const result = await sdk.musicSearch.search(keyword, page, limit);
  if (result && result.list) {
    return result.list;
  }

  return [];
}

/**
 * 音乐搜索接口
 */
interface MusicSearchModule {
  search: (keyword: string, page: number, limit: number) => Promise<SearchResultLocal | null>;
}

interface SearchResultLocal {
  list: MusicInfo[];
}

/**
 * SDK接口（避免使用any）
 */
interface SdkSearchInterface {
  musicSearch: MusicSearchModule;
}

/**
 * 根据源获取SDK
 */
function getSdkBySource(source: string): SdkSearchInterface | null {
  switch (source) {
    case 'kw':
      return musicSdk.kw as SdkSearchInterface;
    case 'kg':
      return musicSdk.kg as SdkSearchInterface;
    case 'tx':
      return musicSdk.tx as SdkSearchInterface;
    case 'wy':
      return musicSdk.wy as SdkSearchInterface;
    case 'mg':
      return musicSdk.mg as SdkSearchInterface;
    default:
      return null;
  }
}

/**
 * 在线音乐模块
 */
interface OnlineModule {
  getMusicUrl: (params: GetMusicUrlParams) => Promise<string | null>;
  getLyricInfo: (params: GetLyricInfoParams) => Promise<LyricInfo>;
  getPicUrl: (params: GetPicUrlParams) => Promise<string>;
  getOtherSource: (musicInfo: MusicInfo) => Promise<MusicInfo[]>;
  searchMusic: (params: SearchMusicParams) => Promise<MusicInfo[]>;
}



// ========== 本地曲库（原 ResolveLocalPlayback）==========

export const online: OnlineModule = {
  getMusicUrl,
  getLyricInfo,
  getPicUrl,
  getOtherSource,
  searchMusic,
};
