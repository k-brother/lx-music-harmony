/**
 * 自定义源（插件）解析
 *
 * 从 ResolvePlayback 抽出：自定义源的「是否优先、参数怎么转、懒恢复插件」是独立话题，
 * 与内置音源解析混在一起时，排查「自定义源没生效」要跨十几个函数找。
 */
import { appLog as hilog } from '../log/AppLogger';
import { getStorageService } from '../interfaces/IStorageService';
import { pluginManager, PluginSongInfo as PluginSongInfoType } from '../plugin/PluginManager';
import { normalizeSingerText } from './playback/CandidateMatch';
import type { MusicInfo } from '../../types/MusicTypes';

const TAG = 'ONLINE_MUSIC';
const DOMAIN = 0x0003;

/** 懒恢复自定义源：并发调用只跑一次 */
let lazyCustomSourceRestorePromise: Promise<boolean> | null = null;

export function isPluginPreferredForMusicUrl(musicInfo: MusicInfo): boolean {
  const source = musicInfo.source as string;
  const activePlugin = pluginManager.getActivePlugin();
  return source !== 'local' && !!(activePlugin && activePlugin.onGetMusicUrl);
}

export function toPluginSongInfo(musicInfo: MusicInfo): PluginSongInfoType {
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

export async function ensureCustomSourcePluginReady(): Promise<boolean> {
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
