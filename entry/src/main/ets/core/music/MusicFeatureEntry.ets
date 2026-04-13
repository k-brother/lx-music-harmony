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
import { musicSdk, SearchResult as SDKSearchResult, MusicUrlResult } from './MusicSdkAggregate';
import { getMusicSourceFactory } from './MusicSourceRegistry';
import { getMusicUrl as resolveGetMusicUrl, type GetMusicUrlParams as ResolveGetMusicUrlParams } from './ResolvePlayback';
import type { MusicQualityType, MusicInfo, LyricInfo, Quality } from '../../types/MusicTypes';
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
  const musicInfo = params.musicInfo;
  const isRefresh = params.isRefresh ?? false;

  if (!musicInfo || !musicInfo.id) {
    const emptyLyricInfo: LyricInfo = {
      lyric: '',
      tlyric: null,
      lxlyric: null,
      rlyric: null,
    };
    return emptyLyricInfo;
  }

  const source = musicInfo.source;
  const songmid = musicInfo.id;

  try {
    let result: LyricInfo | null = null;
    if (isBuiltinMusicSourceId(source)) {
      result = await getMusicSourceFactory().getSdk(source).getLyric(musicInfo);
    }
    if (result) {
      return result;
    }
    const emptyLyricInfo: LyricInfo = {
      lyric: '',
      tlyric: null,
      lxlyric: null,
      rlyric: null,
    };
    return emptyLyricInfo;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'getLyricInfo error: %{public}s', JSON.stringify(err));
    return {
      lyric: '',
      tlyric: null,
      lxlyric: null,
      rlyric: null,
    };
  }
}

// 获取图片路径
export async function getPicPath(params: GetPicPathParams): Promise<string> {
  const musicInfo = params.musicInfo;
  const isRefresh = params.isRefresh ?? false;

  if (!musicInfo) {
    return '';
  }

  // 如果有缓存的图片URL且不需要刷新，直接返回
  if (musicInfo.pic && !isRefresh) {
    return musicInfo.pic;
  }

  const source = musicInfo.source;
  const songmid = musicInfo.id;

  try {
    let picUrl: string = '';
    if (isBuiltinMusicSourceId(source)) {
      picUrl = await getMusicSourceFactory().getSdk(source).getPic(musicInfo);
    }
    if (picUrl) {
      return picUrl;
    }
    return musicInfo.pic || '';
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'getPicPath error: %{public}s', JSON.stringify(err));
    return musicInfo.pic || '';
  }
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
          name: item.name || '',
          singer: item.singer || '',
          album: item.albumName || item.album || '',
          source: item.source || source,
          duration: duration,
          interval: item.interval || null,
          pic: item.img || item.pic || ''
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
              name: item.name || '',
              singer: item.singer || '',
              album: item.albumName || item.album || '',
              source: item.source || src,
              duration: duration,
              interval: item.interval || null,
              pic: item.img || item.pic || ''
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
