// Songlist Core Module - 对应 src/core/songlist.ts
// 歌单核心模块

import { songlistState, SonglistInfo, Source, TagInfo } from '../store/songlist/SonglistStoreState';
import {
  musicSdk,
  type SongListTagsResult,
  type SongListResult,
  type SongListDetailResult,
  type SongListDetailInfo as SdkDetailInfo,
} from './music/MusicFeatureEntry';
import { pluginManager } from './plugin/PluginManager';

// 歌曲信息接口
export interface SongInfoItem {
  id: string;
  name: string;
  singer: string;
  album: string;
  pic: string;
  duration: number;
  source: string;
}

// 歌单详情信息
export interface ListDetailInfo {
  id: string;
  name: string;
  desc: string;
  pic: string;
  author: string;
  playCount: number;
  total: number;
  page: number;
  limit: number;
  list: SongInfoItem[];
}

// 列表信息
export interface ListInfo {
  list: SonglistInfo[];
  total: number;
  page: number;
  limit: number;
  key: string | null;
}

// 缓存
export interface CacheItem {
  type: 'list' | 'detail';
  data: ListInfo | ListDetailInfo;
}

// 列表设置结果
export interface ListResult {
  list: SonglistInfo[];
  total: number;
}

const cache: Map<string, CacheItem> = new Map();
const LIST_LOAD_LIMIT = 30;

// 获取排序列表
export function getSortList(source: Source): TagInfo[] {
  // 默认排序选项
  const defaultSortList: TagInfo[] = [];
  const item1: TagInfo = { id: '0', name: '推荐', tagId: '', type: 0 };
  const item2: TagInfo = { id: '1', name: '最新', tagId: '', type: 0 };
  const item3: TagInfo = { id: '2', name: '最热', tagId: '', type: 0 };
  defaultSortList.push(item1);
  defaultSortList.push(item2);
  defaultSortList.push(item3);
  return defaultSortList;
}

// 获取标签列表
export async function getTags(source: Source): Promise<TagInfo[]> {
  if (songlistState.tagList && songlistState.tagList.length > 0) {
    return songlistState.tagList;
  }
  try {
    let result: SongListTagsResult | null = null;
    switch (source) {
      case 'kw':
        result = await musicSdk.kw.songList.getTags();
        break;
      case 'kg':
        result = await musicSdk.kg.songList.getTags();
        break;
      case 'tx':
        result = await musicSdk.tx.songList.getTags();
        break;
      case 'wy':
        result = await musicSdk.wy.songList.getTags();
        break;
      case 'mg':
        result = await musicSdk.mg.songList.getTags();
        break;
      default:
        result = null;
    }
    if (result && result.tags) {
      const tagInfos: TagInfo[] = [];
      for (const tag of result.tags) {
        const tagInfo: TagInfo = {
          id: tag.id,
          name: tag.name,
          tagId: tag.id,
          type: 1,
        };
        tagInfos.push(tagInfo);
      }
      songlistState.tagList = tagInfos;
      return tagInfos;
    }
  } catch (e) {
    // 忽略错误
  }
  return [];
}

// 设置列表信息
export function setListInfo(source: Source, tagId: string, sortId: string): void {
  clearList();
  songlistState.activeSource = source;
  songlistState.activeTagId = tagId;
}

// 设置列表
export function setList(result: ListResult, tagId: string, sortId: string, page: number): void {
  songlistState.songList = result.list;
  songlistState.page = page;
  songlistState.hasMore = result.list.length >= 30;
}

// 清空列表
export function clearList(): void {
  songlistState.songList = [];
  songlistState.page = 1;
  songlistState.hasMore = true;
}

// 获取歌单列表
export async function getSongList(
  source: Source,
  tagId: string,
  sortId: string,
  page: number,
  isRefresh: boolean = false
): Promise<ListInfo> {
  const pageKey = `slist__${source}__${sortId}__${tagId}__${page}`;

  let listCache = cache.get(pageKey);
  if (listCache && listCache.type === 'list') {
    if (isRefresh) cache.delete(pageKey);
    else return listCache.data as ListInfo;
  }

  try {
    let result: SongListResult | null = null;
    switch (source) {
      case 'kw':
        result = await musicSdk.kw.songList.getList(sortId, tagId, page);
        break;
      case 'kg':
        result = await musicSdk.kg.songList.getList(sortId, tagId, page);
        break;
      case 'tx':
        result = await musicSdk.tx.songList.getList(sortId, tagId, page);
        break;
      case 'wy':
        result = await musicSdk.wy.songList.getList(sortId, tagId, page);
        break;
      case 'mg':
        result = await musicSdk.mg.songList.getList(sortId, tagId, page);
        break;
      default:
        result = null;
    }
    if (result && result.list) {
      const songlistInfos: SonglistInfo[] = [];
      for (const item of result.list) {
        const songlistInfo: SonglistInfo = {
          id: item.id,
          name: item.name,
          author: item.author,
          img: item.img,
          playCount: parseInt(item.play_count) || 0,
          desc: item.desc,
          source: source as Source,
          total: item.total,
          pic: '',
          createTime: null,
          updateTime: null,
          count: null,
          shareCount: null,
          collectCount: null,
          tags: null,
        };
        songlistInfos.push(songlistInfo);
      }
      const listInfo: ListInfo = {
        list: songlistInfos,
        total: result.total || result.list.length,
        page: result.page || page,
        limit: result.limit || 30,
        key: pageKey,
      };
      // 缓存结果
      cache.set(pageKey, { type: 'list', data: listInfo });
      return listInfo;
    }
  } catch (e) {
    // 忽略错误
  }
  return { list: [], total: 0, page: 1, limit: 30, key: pageKey };
}

// 获取歌单列表（兼容性别名）
export { getSongList as getSonglist };

// 设置歌单详情信息
export function setListDetailInfo(source: Source, id: string): void {
  clearListDetail();
}

// 设置歌单详情
export function setListDetail(result: ListDetailInfo, id: string, page: number): void {
  songlistState.detailInfo = result;
  songlistState.detailList = result.list;
  songlistState.detailPage = page;
}

// 清空详情
export function clearListDetail(): void {
  songlistState.detailInfo = null;
  songlistState.detailList = [];
  songlistState.detailPage = 1;
}

// 获取歌单内单页歌曲
export async function getListDetail(
  id: string,
  source: Source,
  page: number,
  isRefresh: boolean = false
): Promise<ListDetailInfo> {
  const pageKey = `sdetail__${source}__${id}__${page}`;

  let pageCache = cache.get(pageKey);
  if (pageCache && pageCache.type === 'detail' && !isRefresh) {
    return pageCache.data as ListDetailInfo;
  }

  try {
    const activePlugin = pluginManager.getActivePlugin();
    if (source !== 'local' && activePlugin && activePlugin.onGetSongList) {
      try {
        const pluginResult = await activePlugin.onGetSongList(id, page);
        if (pluginResult && pluginResult.list && pluginResult.list.length > 0) {
          const pluginSongItems: SongInfoItem[] = pluginResult.list.map((item): SongInfoItem => ({
            id: item.songmid || '',
            name: item.name || '',
            singer: item.singer || '',
            album: item.albumName || '',
            pic: '',
            duration: 0,
            source: item.source || source,
          }));
          const pluginDetail: ListDetailInfo = {
            id: id,
            name: '',
            desc: '',
            pic: '',
            author: '',
            playCount: 0,
            total: pluginResult.total || pluginSongItems.length,
            page: pluginResult.page || page,
            limit: pluginResult.limit || 30,
            list: pluginSongItems,
          };
          cache.set(pageKey, { type: 'detail', data: pluginDetail });
          return pluginDetail;
        }
      } catch {
        // fallback to builtin source
      }
    }

    let result: SongListDetailResult | null = null;
    switch (source) {
      case 'kw':
        result = await musicSdk.kw.songList.getListDetail(id, page);
        break;
      case 'kg':
        result = await musicSdk.kg.songList.getListDetail(id, page);
        break;
      case 'tx':
        result = await musicSdk.tx.songList.getListDetail(id, page);
        break;
      case 'wy':
        result = await musicSdk.wy.songList.getListDetail(id, page);
        break;
      case 'mg':
        result = await musicSdk.mg.songList.getListDetail(id, page);
        break;
      default:
        result = null;
    }
    if (result) {
      const songInfoItems: SongInfoItem[] = [];
      for (const item of result.list) {
        const singerStr: string = item.singer || '';
        const songInfoItem: SongInfoItem = {
          id: item.songmid || item.id || '',
          name: item.name || '',
          singer: singerStr,
          album: item.albumName || item.album || '',
          pic: item.img || item.pic || '',
          duration: 0,
          source: item.source || source,
        };
        songInfoItems.push(songInfoItem);
      }
      const infoName: string = result.info?.name || '';
      const infoDesc: string = result.info?.desc || '';
      const infoImg: string = result.info?.img || '';
      const infoAuthor: string = result.info?.author || '';
      const rawPlay = result.info?.play_count ?? '';
      let infoPlayCount: number = parseInt(rawPlay, 10);
      if (Number.isNaN(infoPlayCount)) {
        infoPlayCount = 0;
      }
      const pageLimit: number = result.limit !== undefined && result.limit > 0 ? result.limit : 30;

      const detailInfo: ListDetailInfo = {
        id: id,
        name: infoName,
        desc: infoDesc,
        pic: infoImg,
        author: infoAuthor,
        playCount: infoPlayCount,
        total: result.total || result.list.length,
        page: page,
        limit: pageLimit,
        list: songInfoItems,
      };
      // 缓存结果
      cache.set(pageKey, { type: 'detail', data: detailInfo });
      return detailInfo;
    }
  } catch (e) {
    // 忽略错误
  }
  return {
    id,
    name: '',
    desc: '',
    pic: '',
    author: '',
    playCount: 0,
    total: 0,
    page: 1,
    limit: 30,
    list: [],
  };
}

// 获取歌单详情
export async function getSonglistDetail(source: Source, id: string): Promise<ListDetailInfo | null> {
  try {
    const result = await getListDetail(id, source, 1);
    return result;
  } catch (e) {
    return null;
  }
}

// 获取歌单内全部歌曲
export async function getListDetailAll(
  source: Source,
  id: string,
  isRefresh: boolean = false
): Promise<SongInfoItem[]> {
  const allSongs: SongInfoItem[] = [];
  let currentPage = 1;
  let hasMore = true;

  while (hasMore) {
    const detail = await getListDetail(id, source, currentPage, isRefresh);
    if (detail.list && detail.list.length > 0) {
      allSongs.push(...detail.list);
      const lim = detail.limit > 0 ? detail.limit : 30;
      hasMore = allSongs.length < detail.total && detail.list.length >= lim;
      currentPage++;
    } else {
      hasMore = false;
    }
  }

  return allSongs;
}

// 获取歌单标签
export async function getSonglistTags(source: Source = 'kw'): Promise<TagInfo[]> {
  return getTags(source);
}

// 收藏歌单（需用户账号支持，当前版本不支持）
export async function collectSonglist(source: Source, id: string): Promise<boolean> {
  hilog.warn(0x0001, 'Songlist', '收藏歌单功能需账号支持，当前版本不支持');
  return false;
}

// 取消收藏歌单（需用户账号支持，当前版本不支持）
export async function uncollectSonglist(id: string): Promise<boolean> {
  hilog.warn(0x0001, 'Songlist', '取消收藏歌单功能需账号支持，当前版本不支持');
  return false;
}
