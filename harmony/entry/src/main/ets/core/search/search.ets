 // Search Core Module - 对应 src/core/search/
// 搜索核心模块

import { searchState } from '../../store/search/SearchStoreState';
import { musicSearchState, MusicInfoItem } from '../../store/search/music/MusicStoreState';
import { musicSearchAction } from '../../store/search/music/MusicStoreAction';
import { songlistSearchState } from '../../store/search/songlist/SonglistStoreState';
import {
  searchMusic as searchMusicApi,
  musicSdk,
  type SearchResultItem,
  type HotSearchResult as SdkHotSearchResult,
  type HotSearchItem as SdkHotSearchItem,
  MusicSource,
} from '../music/MusicFeatureEntry';
import { getStorageService } from '../interfaces/IStorageService';
import hilog from '@ohos.hilog';

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

// 设置搜索类型
export function setSearchType(type: 'music' | 'songlist'): void {
  searchState.type = type;
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
  return searchState.searchHistory;
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
  if (searchState.searchHistory.length >= 15) {
    searchState.searchHistory.splice(14, searchState.searchHistory.length - 14);
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
  name: string;
  singer: string;
  album: string;
  pic: string;
  duration: number;
  source: string;
}

// 歌单搜索结果项
interface SonglistSearchResult {
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

// 转换 MusicInfoItem 到 MusicSearchResult
function convertToMusicSearchResult(items: MusicInfoItem[]): MusicSearchResult[] {
  const results: MusicSearchResult[] = [];
  for (const item of items) {
    console.log('convertToMusicSearchResult: item.pic =', item.pic, 'item.name =', item.name);
    const result: MusicSearchResult = {
      id: item.id,
      name: item.name,
      singer: item.singer,
      album: item.album,
      pic: item.pic,
      duration: item.duration,
      source: item.source
    };
    results.push(result);
  }
  return results;
}

// 音乐搜索
export async function searchMusic(text: string, page: number, sourceId: Source): Promise<MusicSearchResult[]> {
  if (!text) {
    console.log('Search: empty text, returning []');
    return [];
  }

  console.log(`Search: text="${text}", page=${page}, sourceId="${sourceId}"`);
  console.log(`Search: listInfos keys: ${JSON.stringify(Array.from(musicSearchState.listInfos.keys()))}`);

  const listInfo = musicSearchState.listInfos.get(sourceId);
  if (!listInfo) {
    console.error(`Search: listInfo not found for sourceId "${sourceId}"`);
    return [];
  }
  console.log(`Search: listInfo found, limit=${listInfo.limit}`);

  const key = `${page}__${text}`;

  if (sourceId === 'all') {
    listInfo.key = key;
    const sources = ['kw', 'kg', 'tx', 'wy', 'mg'];
    const allResults: MusicInfoItem[] = [];
    for (let i = 0; i < sources.length; i++) {
      const src = sources[i];
      try {
        const result: SearchResultItem[] = await searchMusicApi({
          name: text,
          singer: null,
          source: src,
          page: page,
          limit: listInfo.limit
        });
        for (let j = 0; j < result.length; j++) {
          const r = result[j];
          allResults.push({
            id: r.id,
            name: r.name,
            singer: r.singer,
            album: r.album,
            source: r.source,
            interval: r.interval,
            pic: r.pic,
            albumId: null,
            duration: 0,
            lrc: null,
          });
        }
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'searchMusic source %{public}s failed: %{public}s', src, (err as Error).message);
      }
    }
    listInfo.list = allResults;
    listInfo.total = allResults.length;
    return convertToMusicSearchResult(allResults);
  } else {
    if (listInfo.key === key && listInfo.list.length > 0) {
      return convertToMusicSearchResult(listInfo.list);
    }
    listInfo.key = key;

    try {
      // 调用音乐源API进行搜索
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
        console.log('searchMusic convert: item.pic =', item.pic, 'item.name =', item.name);
        const musicInfoItem: MusicInfoItem = {
          id: item.id,
          name: item.name,
          singer: item.singer,
          album: item.album,
          albumId: null,
          duration: item.duration,
          source: item.source,
          pic: item.pic ?? '',
          lrc: null,
          interval: null
        };
        convertedResults.push(musicInfoItem);
      }

      // 更新搜索结果状态
      musicSearchAction.setListInfo({
        list: convertedResults,
        source: sourceId,
        total: convertedResults.length
      }, page, text);
      return convertToMusicSearchResult(convertedResults);
    } catch (error) {
      console.error('搜索失败:', error);
      return [];
    }
  }
}

// 歌单搜索（当前SDK不支持歌单搜索，仅返回空数组）
export async function searchSonglist(text: string, page: number, sourceId: Source): Promise<SonglistSearchResult[]> {
  if (!text) return [];

  songlistSearchState.isSearching = true;

  try {
    // 各音乐源的SDK未提供歌单搜索API，暂不支持此功能
    return [];
  } finally {
    songlistSearchState.isSearching = false;
  }
}

// 获取热门搜索
export async function getHotSearch(source: string = 'kw'): Promise<HotSearchItem[]> {
  try {
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
    return [];
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'getHotSearch failed for %{public}s: %{public}s', source, (err as Error).message);
    return [];
  }
}

// 获取搜索提示
export async function getTipListInfo(keyword: string, source: string = 'kw'): Promise<string[]> {
  try {
    let tips: string[] = [];
    switch (source) {
      case 'kw':
        if (musicSdk.kw.musicSearch.tip) {
          tips = await musicSdk.kw.musicSearch.tip(keyword);
        }
        break;
      case 'kg':
        if (musicSdk.kg.musicSearch.tip) {
          tips = await musicSdk.kg.musicSearch.tip(keyword);
        }
        break;
      case 'tx':
        if (musicSdk.tx.musicSearch.tip) {
          tips = await musicSdk.tx.musicSearch.tip(keyword);
        }
        break;
      default:
        tips = [];
    }
    return tips;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'getTipListInfo failed for %{public}s: %{public}s', source, (err as Error).message);
    return [];
  }
}

// 清除搜索结果
export function clearSearchResult(): void {
  // 清除音乐搜索结果
  const sources: Source[] = ['kw', 'kg', 'tx', 'wy', 'mg', 'all'];
  for (const source of sources) {
    musicSearchAction.clearListInfo(source);
  }

  // 清除歌单搜索结果
  songlistSearchState.list = [];
  songlistSearchState.page = 1;
  songlistSearchState.hasMore = true;
}
