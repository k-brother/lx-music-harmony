 // Search Core Module - 对应 src/core/search/
// 搜索核心模块

import { searchState } from '../../store/search/SearchStoreState';
import { musicSearchState, MusicInfoItem } from '../../store/search/music/MusicStoreState';
import { musicSearchAction } from '../../store/search/music/MusicStoreAction';
import { songlistSearchState } from '../../store/search/songlist/SonglistStoreState';
import {
  searchMusic as searchMusicApi,
  searchSongLists,
  musicSdk,
  type SearchResultItem,
  type HotSearchResult as SdkHotSearchResult,
  type HotSearchItem as SdkHotSearchItem,
  MusicSource,
} from '../music/MusicFeatureEntry';
import { getStorageService } from '../interfaces/IStorageService';
import { pluginManager } from '../plugin/PluginManager';
import { settingsService } from '../../service/SettingsService';
import hilog from '@ohos.hilog';
import { SUPPORTED_SOURCES } from '../../types/MusicSource';

const TAG = 'SEARCH';
const DOMAIN = 0x0004;

// 音乐源类型
export type Source = 'kw' | 'kg' | 'tx' | 'wy' | 'mg' | 'all';

// 搜索音乐参数接口
interface SearchMusicParams {
  name: string;
  singer: string | null;
  source: string | null;
  page: number | null;
  limit: number | null;
}


// 设置搜索文本
export function setSearchText(text: string): void {
  searchState.searchText = text;
}

// 搜索历史存储键
const SEARCH_HISTORY_KEY = 'search_history';

// 获取搜索历史
export async function getSearchHistory(): Promise<string[]> {
  if (!searchState.searchHistory.length) {
    try {
      const historyStr = await getStorageService().getString(SEARCH_HISTORY_KEY, '');
      if (historyStr) {
        searchState.searchHistory = JSON.parse(historyStr) as string[];
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getSearchHistory parse failed: %{public}s', (err as Error).message);
    }
  }
  const limit = settingsService.get().searchHistoryCount;
  return searchState.searchHistory.slice(0, limit);
}

// 添加搜索历史
export async function addHistoryWord(word: string): Promise<void> {
  if (!word) return;

  // 如果没有历史，先获取
  if (!searchState.searchHistory.length) {
    await getSearchHistory();
  }

  const index = searchState.searchHistory.indexOf(word);
  if (index === 0) return;
  if (index > -1) {
    searchState.searchHistory.splice(index, 1);
  }
  // 条数上限跟随「设置 -> 搜索设置 -> 搜索历史数量」
  const limit = settingsService.get().searchHistoryCount;
  if (searchState.searchHistory.length >= limit) {
    searchState.searchHistory.splice(limit - 1, searchState.searchHistory.length - (limit - 1));
  }
  searchState.searchHistory.unshift(word);

  // 保存到持久化存储
  try {
    await getStorageService().setString(SEARCH_HISTORY_KEY, JSON.stringify(searchState.searchHistory));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'addHistoryWord save failed: %{public}s', (err as Error).message);
  }
}

// 移除搜索历史项
export async function removeHistoryWord(index: number): Promise<void> {
  searchState.searchHistory.splice(index, 1);
  // 保存到持久化存储
  try {
    await getStorageService().setString(SEARCH_HISTORY_KEY, JSON.stringify(searchState.searchHistory));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'removeHistoryWord save failed: %{public}s', (err as Error).message);
  }
}

// 清空搜索历史
export async function clearHistoryList(): Promise<void> {
  searchState.searchHistory = [];
  // 清除持久化存储
  try {
    await getStorageService().setString(SEARCH_HISTORY_KEY, '');
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'clearHistoryList save failed: %{public}s', (err as Error).message);
  }
}

// 音乐搜索结果项
export interface MusicSearchResult {
  id: string;
  songmid?: string;
  name: string;
  singer: string;
  album: string;
  pic: string;
  duration: number;
  source: string;
  albumId?: string;
  hash?: string;
  strMediaMid?: string;
  songId?: number;
  copyrightId?: string;
}

// 歌单搜索结果项
export interface SonglistSearchResult {
  id: string;
  name: string;
  desc: string;
  pic: string;
  source: string;
  playCount: number;
  author: string;
}

// 热门搜索项
export interface HotSearchItem {
  index: number;
  title: string;
  source: MusicSource;
  url: string | null;
  hot: number | null;
}

// SetListInfoResult 接口定义
interface SetListInfoResult {
  list: MusicInfoItem[];
  source: string;
  total: number;
}

function isBuiltinSource(source: string): boolean {
  return source === 'kw' || source === 'kg' || source === 'tx' || source === 'wy' || source === 'mg';
}

function getDefaultHotSearch(source: string): HotSearchItem[] {
  return [
    { index: 1, title: '周杰伦', source: source as MusicSource, url: null, hot: 1000000 },
    { index: 2, title: '林俊杰', source: source as MusicSource, url: null, hot: 800000 },
    { index: 3, title: '邓紫棋', source: source as MusicSource, url: null, hot: 700000 },
    { index: 4, title: '薛之谦', source: source as MusicSource, url: null, hot: 600000 },
    { index: 5, title: '陈奕迅', source: source as MusicSource, url: null, hot: 500000 },
  ];
}

// 转换 MusicInfoItem 到 MusicSearchResult
function convertToMusicSearchResult(items: MusicInfoItem[]): MusicSearchResult[] {
  const results: MusicSearchResult[] = [];
  for (const item of items) {
    const result: MusicSearchResult = {
      id: item.id,
      songmid: item.songmid,
      name: item.name,
      singer: item.singer,
      album: item.album,
      pic: item.pic,
      duration: item.duration,
      source: item.source,
      albumId: item.albumId || undefined,
      hash: item.hash,
      strMediaMid: item.strMediaMid,
      songId: item.songId,
      copyrightId: item.copyrightId,
    };
    results.push(result);
  }
  return results;
}

/** SDK 搜索结果项 → 搜索状态里的歌曲项（全源聚合与单源搜索共用，避免 15 个字段抄两遍） */
function toMusicInfoItem(item: SearchResultItem): MusicInfoItem {
  const musicInfoItem: MusicInfoItem = {
    id: item.id,
    songmid: item.songmid,
    name: item.name,
    singer: item.singer,
    album: item.album,
    albumId: item.albumId || null,
    duration: item.duration || 0,
    source: item.source,
    pic: item.pic ?? '',
    hash: item.hash,
    strMediaMid: item.strMediaMid,
    songId: item.songId,
    copyrightId: item.copyrightId,
    lrc: null,
    interval: item.interval,
  };
  return musicInfoItem;
}

/**
 * 全源聚合搜索：逐个源串行拉取（并发会让小水管音源直接限流），
 * 单个源失败只跳过它，不影响其它源的结果。
 */
async function searchAllSources(text: string, page: number, limit: number): Promise<MusicInfoItem[]> {
  const allResults: MusicInfoItem[] = [];
  for (let i = 0; i < SUPPORTED_SOURCES.length; i++) {
    const src = SUPPORTED_SOURCES[i];
    try {
      const result: SearchResultItem[] = await searchMusicApi({
        name: text,
        singer: null,
        source: src,
        page: page,
        limit: limit,
      });
      for (let j = 0; j < result.length; j++) {
        allResults.push(toMusicInfoItem(result[j]));
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'searchMusic source %{public}s failed: %{public}s', src, (err as Error).message);
    }
  }
  return allResults;
}

// 音乐搜索
export async function searchMusic(text: string, page: number, sourceId: Source): Promise<MusicSearchResult[]> {
  if (!text) {
    return [];
  }

  const listInfo = musicSearchState.listInfos.get(sourceId);
  if (!listInfo) {
    hilog.warn(DOMAIN, TAG, 'searchMusic: no listInfo for source=%{public}s', sourceId);
    return [];
  }

  const key = `${page}__${text}`;

  if (sourceId === 'all') {
    listInfo.key = key;
    const allResults: MusicInfoItem[] = await searchAllSources(text, page, listInfo.limit);
    listInfo.list = allResults;
    listInfo.total = allResults.length;
    return convertToMusicSearchResult(allResults);
  } else {
    if (listInfo.key === key && listInfo.list.length > 0) {
      return convertToMusicSearchResult(listInfo.list);
    }
    listInfo.key = key;

    try {
      // 内置源必须固定走内置 SDK，避免插件返回的 songmid/id 与内置解析链不兼容导致“可搜不可播”。
      // 插件搜索仅用于非内置源（该分支在上方已处理）。
      const result: SearchResultItem[] = await searchMusicApi({
        name: text,
        singer: null,
        source: sourceId,
        page: page,
        limit: listInfo.limit
      });

      // 转换搜索结果格式
      const convertedResults: MusicInfoItem[] = [];
      for (const item of result) {
        // item 为 SearchResultItem（MusicFeatureEntry）
        convertedResults.push(toMusicInfoItem(item));
      }

      // 更新搜索结果状态
      musicSearchAction.setListInfo({
        list: convertedResults,
        source: sourceId,
        total: convertedResults.length
      }, page, text);
      return convertToMusicSearchResult(convertedResults);
    } catch (error) {
      const msg: string = error instanceof Error ? error.message : JSON.stringify(error);
      hilog.error(DOMAIN, TAG, 'searchMusic failed: %{public}s', msg);
      return [];
    }
  }
}

/**
 * 歌单搜索。
 * 数据来自各音乐源的 songList.searchList（当前网易云 / QQ音乐可用），
 * 未实现该能力的源会被自动跳过。
 */
export async function searchSonglist(text: string, page: number, sourceId: Source): Promise<SonglistSearchResult[]> {
  const keyword = (text ?? '').trim();
  if (keyword.length === 0) {
    return [];
  }

  songlistSearchState.isSearching = true;
  songlistSearchState.source = sourceId;
  songlistSearchState.page = page;
  try {
    let results = await searchSongLists(keyword, page, 20, sourceId);
    // 当前源不支持歌单搜索（如酷我/酷狗/咪咕）时，自动回退为全源聚合
    if (results.length === 0 && sourceId !== 'all') {
      results = await searchSongLists(keyword, page, 20, 'all');
    }
    const list: SonglistSearchResult[] = [];
    for (let i = 0; i < results.length; i++) {
      const sourceResult = results[i];
      for (let j = 0; j < sourceResult.list.length; j++) {
        const item = sourceResult.list[j];
        list.push({
          id: item.id,
          name: item.name,
          desc: item.desc,
          pic: item.img,
          source: item.source,
          playCount: parseInt(item.play_count) || 0,
          author: item.author,
        });
      }
    }
    songlistSearchState.list = list;
    songlistSearchState.hasMore = list.length > 0;
    hilog.info(DOMAIN, TAG, 'searchSonglist: keyword=%{public}s, count=%{public}d', keyword, list.length);
    return list;
  } catch (error) {
    const msg: string = error instanceof Error ? error.message : JSON.stringify(error);
    hilog.error(DOMAIN, TAG, 'searchSonglist failed: %{public}s', msg);
    return [];
  } finally {
    songlistSearchState.isSearching = false;
  }
}

// 获取热门搜索
export async function getHotSearch(source: string = 'kw'): Promise<HotSearchItem[]> {
  try {
    const plugin = pluginManager.getActivePlugin();
    if (plugin && plugin.onGetHotSearch) {
      try {
        const pluginHotSearch = await plugin.onGetHotSearch();
        if (pluginHotSearch && pluginHotSearch.length > 0) {
          return pluginHotSearch.map((item, idx): HotSearchItem => ({
            index: item.index > 0 ? item.index : idx + 1,
            title: item.title || '',
            source: source as MusicSource,
            url: item.url || null,
            hot: null,
          }));
        }
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'Plugin hot search failed, fallback to builtin source: %{public}s', (err as Error).message);
      }
    }

    if (!isBuiltinSource(source)) {
      hilog.warn(DOMAIN, TAG, 'Source %{public}s is not builtin and plugin has no hot search, using default list', source);
      return getDefaultHotSearch(source);
    }

    let hotResult: SdkHotSearchResult | null = null;
    switch (source) {
      case 'kw':
        hotResult = await musicSdk.kw.hotSearch.search();
        break;
      case 'kg':
        hotResult = await musicSdk.kg.hotSearch.search();
        break;
      case 'tx':
        hotResult = await musicSdk.tx.hotSearch.search();
        break;
      case 'wy':
        hotResult = await musicSdk.wy.hotSearch.search();
        break;
      case 'mg':
        hotResult = await musicSdk.mg.hotSearch.search();
        break;
      default:
        hotResult = null;
    }
    if (hotResult && hotResult.list && hotResult.list.length > 0) {
      return hotResult.list.map((item: SdkHotSearchItem): HotSearchItem => ({
        index: item.index,
        title: item.title,
        source: item.source as MusicSource,
        url: item.url,
        hot: item.hot,
      }));
    }
    hilog.warn(DOMAIN, TAG, 'Hot search empty for %{public}s, using default list', source);
    return getDefaultHotSearch(source);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'getHotSearch failed for %{public}s: %{public}s', source, (err as Error).message);
    return getDefaultHotSearch(source);
  }
}

/**
 * 获取搜索提示（联想词）
 *
 * 各源的实现在 core/music/sources/<源>/tipSearch.ets，经 AbstractMusicSource
 * 的 getSearchTipBinder 挂到 musicSearch.tip 上，这里只做分发与兜底。
 * 咪咕没有可用联想接口（返回 HTML 页面），直接返回空，不打扰用户。
 */
export async function getTipListInfo(keyword: string, source: string = 'kw'): Promise<string[]> {
  try {
    const trimmed = keyword.trim();
    if (trimmed.length === 0) {
      return [];
    }
    switch (source) {
      case 'kw':
        return await getSourceTips(musicSdk.kw.musicSearch.tip, trimmed);
      case 'kg':
        return await getSourceTips(musicSdk.kg.musicSearch.tip, trimmed);
      case 'tx':
        return await getSourceTips(musicSdk.tx.musicSearch.tip, trimmed);
      case 'wy':
        return await getSourceTips(musicSdk.wy.musicSearch.tip, trimmed);
      default:
        return [];
    }
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'getTipListInfo failed for %{public}s: %{public}s', source, (err as Error).message);
    return [];
  }
}

/** 源不支持联想（没有挂 binder）时返回空数组，避免调用方到处判空 */
async function getSourceTips(
  tipFn: ((keyword: string) => Promise<string[]>) | undefined, keyword: string
): Promise<string[]> {
  if (!tipFn) {
    return [];
  }
  const tips = await tipFn(keyword);
  return tips ?? [];
}
