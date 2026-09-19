/**
 * 音乐特性对外主入口（门面）：集中再导出根目录各能力，供 presentation / app / core 等优先 import。
 *
 * 依赖方向（无环）：
 * - 本文件编排 → `MusicSdkAggregate` → `MusicSourceRegistry`（含 `MusicSourceFactory`）→ `sources/*` 各源
 * - 本文件编排 → `ResolvePlayback` → `MusicSdkAggregate` + `MusicParsingUtils`
 * - `RunMusicDownloads` → `ResolvePlayback` + `MusicParsingUtils`
 * - `MusicSdkSetup`（插件/枚举）→ `MusicSourceRegistry` 取内置 SDK
 */

// 导入音乐源SDK
import { musicSdk, SearchResult as SDKSearchResult } from './MusicSdkAggregate';
import { getMusicSourceFactory } from './MusicSourceRegistry';
import {
  getMusicUrl as resolveGetMusicUrl,
  getLyricInfo as resolveGetLyricInfo,
  getPicUrl as resolveGetPicUrl,
  type GetMusicUrlParams as ResolveGetMusicUrlParams,
} from './ResolvePlayback';
import type { MusicInfo, LyricInfo } from '../../types/MusicTypes';
import { pluginManager, PluginSongInfo } from '../plugin/PluginManager';
import hilog from '@ohos.hilog';

const TAG = 'MUSIC';
const DOMAIN = 0x0003;

function isBuiltinMusicSourceId(id: string): boolean {
  return id === 'kw' || id === 'kg' || id === 'tx' || id === 'wy' || id === 'mg';
}

// 搜索结果项类型
export interface SearchResultItem {
  id: string;
  name: string;
  singer: string;
  album: string;
  source: string;
  duration: number;
  interval: string | null;
  pic: string;
  songmid?: string;
  albumId?: string;
  hash?: string;
  strMediaMid?: string;
  songId?: number;
  copyrightId?: string;
}

// 获取歌词参数接口
interface GetLyricInfoParams {
  musicInfo: MusicInfo;
  isRefresh?: boolean | null;
  onToggleSource?: ((mInfo: MusicInfo | null) => void) | null;
}

// 获取图片路径参数接口
interface GetPicPathParams {
  musicInfo: MusicInfo;
  listId?: string | null;
  isRefresh?: boolean | null;
  onToggleSource?: ((mInfo: MusicInfo | null) => void) | null;
}

// 搜索音乐参数接口
interface SearchMusicParams {
  name: string;
  singer: string | null;
  source: string | null;
  page: number | null;
  limit: number | null;
}

// 查找音乐参数接口
interface FindMusicParams {
  name: string;
  singer: string;
  albumName: string | null;
  interval: string | null;
  source: string | null;
}

// 获取音乐播放URL - 委托给 ResolvePlayback（包含缓存和回源逻辑）
export type GetMusicUrlParams = ResolveGetMusicUrlParams;

export async function getMusicUrl(params: GetMusicUrlParams): Promise<string | null> {
  return resolveGetMusicUrl(params);
}

// 获取歌词信息
export async function getLyricInfo(params: GetLyricInfoParams): Promise<LyricInfo> {
  return resolveGetLyricInfo({
    musicInfo: params.musicInfo,
    isRefresh: params.isRefresh ?? false,
    onToggleSource: params.onToggleSource ? (mInfo?: MusicInfo) => params.onToggleSource!(mInfo ?? null) : null,
  });
}

// 获取图片路径
export async function getPicPath(params: GetPicPathParams): Promise<string> {
  const musicInfo = params.musicInfo;
  if (!musicInfo) {
    return '';
  }
  return resolveGetPicUrl({
    musicInfo,
    isRefresh: params.isRefresh ?? false,
    onToggleSource: params.onToggleSource ? (mInfo?: MusicInfo) => params.onToggleSource!(mInfo ?? null) : null,
  });
}

// 搜索音乐
export async function searchMusic(params: SearchMusicParams): Promise<SearchResultItem[]> {
  const name = params.name;
  const singer = params.singer;
  const source = params.source ?? 'kw';
  const page = params.page ?? 1;
  const limit = params.limit ?? 30;

  const keyword = singer ? `${name} ${singer}` : name;

  try {
    // all 源：聚合内置源搜索结果（禁止路由到插件分支）
    if (source === 'all') {
      const builtinSources: string[] = ['kw', 'kg', 'tx', 'wy', 'mg'];
      const mergedResults: SearchResultItem[] = [];
      for (let i = 0; i < builtinSources.length; i++) {
        const src = builtinSources[i];
        try {
          const sdkResult = await getMusicSourceFactory().getSdk(src).musicSearch.search(keyword, page, limit);
          if (!sdkResult || !sdkResult.list || sdkResult.list.length === 0) {
            continue;
          }
          for (const item of sdkResult.list) {
            let duration = 0;
            if (item.interval) {
              const parts = item.interval.split(':');
              let multiplier = 1;
              for (let j = parts.length - 1; j >= 0; j--) {
                duration += parseInt(parts[j]) * multiplier;
                multiplier *= 60;
              }
            }
            mergedResults.push({
              id: item.songmid || item.id || '',
              name: item.name || '',
              singer: item.singer || '',
              album: item.albumName || item.album || '',
              source: item.source || src,
              duration: duration,
              interval: item.interval || null,
              pic: item.img || item.pic || '',
            });
          }
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'searchMusic all-source branch failed on %{public}s: %{public}s',
            src, JSON.stringify(err));
        }
      }
      return mergedResults;
    }

    // 自定义源：仅 custom 源走插件搜索
    if (source === 'custom') {
      const activePlugin = pluginManager.getActivePlugin();
      if (activePlugin && activePlugin.onSearch) {
        hilog.info(DOMAIN, TAG, 'Searching via custom source plugin');
        const pluginResult = await activePlugin.onSearch(keyword, page);
        if (pluginResult && pluginResult.list && pluginResult.list.length > 0) {
          // 转换插件搜索结果到本地搜索结果
          const convertedList: SearchResultItem[] = [];
          for (const item of pluginResult.list) {
            const pluginItem = item as PluginSongInfo;
            convertedList.push({
              id: pluginItem.songmid || '',
              songmid: pluginItem.songmid || '',
              name: pluginItem.name || '',
              singer: pluginItem.singer || '',
              album: pluginItem.albumName || '',
              source: 'custom',
              duration: 0,
              interval: pluginItem.duration || null,
              pic: '',
            });
          }
          return convertedList;
        }
      }
      return [];
    }

    // 未知非内置源：直接返回空
    if (!isBuiltinMusicSourceId(source)) {
      hilog.warn(DOMAIN, TAG, 'searchMusic unknown source: %{public}s', source);
      return [];
    }

    // 内置源搜索
    let result: SDKSearchResult | null = null;
    if (isBuiltinMusicSourceId(source)) {
      result = await getMusicSourceFactory().getSdk(source).musicSearch.search(keyword, page, limit);
    }

    if (result && result.list) {
      // 转换SDK搜索结果到本地搜索结果
      const convertedList: SearchResultItem[] = [];
      for (const item of result.list) {
        // 解析时长字符串为秒数
        let duration = 0;
        if (item.interval) {
          const parts = item.interval.split(':');
          let multiplier = 1;
          for (let i = parts.length - 1; i >= 0; i--) {
            duration += parseInt(parts[i]) * multiplier;
            multiplier *= 60;
          }
        }

        const convertedItem: SearchResultItem = {
          id: item.songmid || item.id || '',
          songmid: item.songmid || item.id || '',
          name: item.name || '',
          singer: item.singer || '',
          album: item.albumName || item.album || '',
          source: item.source || source,
          duration: duration,
          interval: item.interval || null,
          pic: item.img || item.pic || '',
          albumId: item.albumId,
          hash: item.hash,
          strMediaMid: item.strMediaMid,
          songId: item.songId,
          copyrightId: item.copyrightId,
        };
        convertedList.push(convertedItem);
      }
      return convertedList;
    }
    return [];
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'searchMusic error: %{public}s', JSON.stringify(err));
    return [];
  }
}

// 查找音乐在其他源
export async function findMusic(params: FindMusicParams): Promise<SearchResultItem[]> {
  const name = params.name;
  const singer = params.singer;
  const source = params.source ?? 'kw';

  const keyword = `${name} ${singer}`;
  const results: SearchResultItem[] = [];

  try {
    // 搜索所有源
    const sourceKeys = ['kw', 'kg', 'tx', 'wy', 'mg'];
    for (const src of sourceKeys) {
      if (src === source) continue;
      try {
        let sdkResult: SDKSearchResult | null = null;
        if (isBuiltinMusicSourceId(src)) {
          sdkResult = await getMusicSourceFactory().getSdk(src).musicSearch.search(keyword, 1, 25);
        }
        if (sdkResult && sdkResult.list) {
          // 转换SDK搜索结果到本地搜索结果
          for (const item of sdkResult.list) {
            // 解析时长字符串为秒数
            let duration = 0;
            if (item.interval) {
              const parts = item.interval.split(':');
              let multiplier = 1;
              for (let i = parts.length - 1; i >= 0; i--) {
                duration += parseInt(parts[i]) * multiplier;
                multiplier *= 60;
              }
            }

            const convertedItem: SearchResultItem = {
              id: item.songmid || item.id || '',
              songmid: item.songmid || item.id || '',
              name: item.name || '',
              singer: item.singer || '',
              album: item.albumName || item.album || '',
              source: item.source || src,
              duration: duration,
              interval: item.interval || null,
              pic: item.img || item.pic || '',
              albumId: item.albumId,
              hash: item.hash,
              strMediaMid: item.strMediaMid,
              songId: item.songId,
              copyrightId: item.copyrightId,
            };
            results.push(convertedItem);
          }
        }
      } catch (e) {
        // 忽略搜索失败的源
        hilog.warn(DOMAIN, TAG, 'Search failed for source %{public}s: %{public}s', src, JSON.stringify(e));
      }
    }
    return results;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'findMusic error: %{public}s', JSON.stringify(err));
    return [];
  }
}

// 导出音乐源SDK
export { musicSdk } from './MusicSdkAggregate';

// 导出本地音乐模块
export {
  scanLocalMusic,
  getLocalMusicUrl,
  getLocalPicUrl,
  getLocalLyricInfo,
} from './ResolvePlayback';

// 导出下载模块
export {
  startDownload,
  pauseDownload,
  resumeDownload,
  cancelDownload,
  getDownloadTask,
  getAllDownloadTasks,
  downloadLyric,
  downloadPic,
  setDownloadContext,
  setMaxConcurrentDownloads,
  initDownloadService,
  createDownloadTask,
  DownloadTask,
  DownloadStatus,
} from './RunMusicDownloads';

// 导出工具函数
export {
  parseInterval,
  formatInterval,
  parseLrc,
  getCurrentLyricIndex,
  getPlayQuality,
  buildLyricInfo,
  filterMusicName,
  isSameMusic,
  getMusicKey,
  sortSingerName,
  compareQuality,
  getHighestQuality,
  isSupportQuality,
  isValidUrl,
  getFileExtension,
  isAudioUrl,
} from './MusicParsingUtils';

// 导出类型
export type { MusicInfo, LyricInfo } from '../../types/MusicTypes';

// 导出子模块供高级用法
export { online } from './ResolvePlayback';
export { local } from './ResolvePlayback';
export { download } from './RunMusicDownloads';
export { utils } from './MusicParsingUtils';

// 初始化、源枚举与插件桥（原 MusicSdkSetup；经门面再导出，避免业务直连 MusicSdkSetup）
export {
  initMusicSDK,
  MusicSource,
  supportQuality,
  getPluginSystem,
  isUsingCustomSource,
  getCurrentSource,
  loadCustomSource,
  unloadCustomSource,
  getPluginInfo,
  getMusicUrlByPlugin,
} from './MusicSdkSetup';

export type { SongInfo, PluginInfoResult } from './MusicSdkSetup';

// 内置源工厂单例（供 DI 等）
export { getMusicSourceFactory } from './MusicSourceRegistry';

// SDK 聚合中的列表/排行/热搜等（与门面 getMusicUrl 无重名）
export {
  getSongListTags,
  getSongList,
  getSongListDetail,
  searchSongLists,
  getLeaderboard,
  getLeaderboardList,
  getHotSearch,
} from './MusicSdkAggregate';

export type {
  HotSearchResult,
  HotSearchItem,
  SongListTagsResult,
  SongListResult,
  SongListDetailResult,
  SongListDetailInfo,
  LeaderboardResult,
  LeaderboardSdkInterface,
  LeaderboardItem,
  LeaderboardListResult,
  SingleMusicSdkInterface,
  SongListInfo,
} from './sources/MusicSdkContracts';

// 测试页直连内置源实现（路径仍经本门面）
export { KuwoMusicSource } from './sources/kw/KuwoMusicSource';
