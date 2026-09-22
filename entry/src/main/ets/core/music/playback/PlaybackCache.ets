/**
 * 播放缓存读写（从 ResolvePlayback 抽出）
 *
 * 两类缓存：
 * - 播放链接：key = 源 + songmid + 音质 + 取链方式（插件/内置），避免不同方式互相污染；
 * - 歌词：含"确实没有歌词"的负缓存（带 24h TTL），避免每次都把全部音源打一遍。
 *
 * 缓存条目同时登记到 CacheService（键 + 估算大小），供设置页做分项统计与清理。
 */
import hilog from '@ohos.hilog';
import { getStorageService } from '../../interfaces/IStorageService';
import { cacheService } from '../../../service/CacheService';
import type { MusicInfo, LyricInfo, Quality } from '../../../types/MusicTypes';
import { createEmptyLyricInfo } from '../MusicParsingUtils';
import { musicInfoTrace } from './CandidateMatch';

const DOMAIN = 0x0003;
const TAG = 'PLAYBACK_CACHE';

/** 源明确返回"无歌词"时的占位文案（判断用，不做展示） */
const NO_LYRIC_MARKERS: string[] = ['暂无歌词', '纯音乐', '没有歌词', '无歌词'];
const NO_LYRIC_CACHE_PREFIX = '#no-lyric#';
const NO_LYRIC_CACHE_TTL_MS = 24 * 60 * 60 * 1000;

/**
 * 获取缓存的音乐URL
 */
export function buildMusicUrlCacheKey(musicInfo: MusicInfo, quality: Quality, mode: 'plugin' | 'builtin'): string {
  // v2 key avoids polluted cache entries from older fallback logic
  return `music_url_v2_${mode}_${musicInfo.source}_${musicInfo.songmid}_${quality}`;
}

export async function getCachedMusicUrl(musicInfo: MusicInfo, quality: Quality, mode: 'plugin' | 'builtin'): Promise<string | null> {
  try {
    const key = buildMusicUrlCacheKey(musicInfo, quality, mode);
    const cached = await getStorageService().getString(key, '');
    if (cached && cached.length > 0) {
      return cached;
    }
    return null;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'getCachedMusicUrl failed: %{public}s', (err as Error).message);
    return null;
  }
}

/**
 * 保存音乐URL到缓存
 */
export async function saveMusicUrlToCache(musicInfo: MusicInfo, quality: Quality, url: string, mode: 'plugin' | 'builtin'): Promise<void> {
  try {
    const key = buildMusicUrlCacheKey(musicInfo, quality, mode);
    await getStorageService().setString(key, url);
    await cacheService.trackMetadataKey(key, url.length);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'saveMusicUrlToCache failed: %{public}s', (err as Error).message);
  }
}

export async function clearCachedMusicUrl(musicInfo: MusicInfo, quality: Quality, mode: 'plugin' | 'builtin'): Promise<void> {
  try {
    const key = buildMusicUrlCacheKey(musicInfo, quality, mode);
    await getStorageService().setString(key, '');
    await cacheService.untrackMetadataKey(key);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'clearCachedMusicUrl failed: %{public}s', (err as Error).message);
  }
}

/**
 * 获取缓存的歌词
 */
export async function getCachedLyricInfo(musicInfo: MusicInfo): Promise<LyricInfo | null> {
  try {
    const key = `lyric_${musicInfo.source}_${musicInfo.songmid}`;
    const storage = getStorageService();
    const cached = await storage.getString(key, '');
    if (cached && cached.length > 0) {
      // "无歌词"负缓存：避免每次播放都重新请求所有源
      if (cached.startsWith(NO_LYRIC_CACHE_PREFIX)) {
        const cachedAt = parseInt(cached.substring(NO_LYRIC_CACHE_PREFIX.length), 10);
        if (!isNaN(cachedAt) && Date.now() - cachedAt < NO_LYRIC_CACHE_TTL_MS) {
          hilog.info(DOMAIN, TAG, 'Lyric negative cache hit: %{public}s', musicInfoTrace(musicInfo));
          return createEmptyLyricInfo();
        }
        await storage.remove(key);
        await cacheService.untrackMetadataKey(key);
        return null;
      }
      // 简单解析缓存的歌词
      const lyricInfo: LyricInfo = {
        lyric: cached,
        tlyric: null,
        lxlyric: null,
        rlyric: null,
      };
      return lyricInfo;
    }
    return null;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'getCachedLyricInfo failed: %{public}s', (err as Error).message);
    return null;
  }
}

/**
 * 记录"这首歌确实没有歌词"，带 TTL，避免每次都打满所有源
 */
export async function cacheNoLyric(musicInfo: MusicInfo): Promise<void> {
  try {
    const key = `lyric_${musicInfo.source}_${musicInfo.songmid}`;
    const value = `${NO_LYRIC_CACHE_PREFIX}${Date.now()}`;
    await getStorageService().setString(key, value);
    await cacheService.trackMetadataKey(key, value.length);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'cacheNoLyric failed: %{public}s', (err as Error).message);
  }
}

/**
 * 保存歌词到缓存
 */
export async function saveLyricToCache(musicInfo: MusicInfo, lyricInfo: LyricInfo): Promise<void> {
  try {
    const key = `lyric_${musicInfo.source}_${musicInfo.songmid}`;
    const value = lyricInfo.lyric || '';
    await getStorageService().setString(key, value);
    await cacheService.trackMetadataKey(key, value.length);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'saveLyricToCache failed: %{public}s', (err as Error).message);
  }
}


