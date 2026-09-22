/**
 * 在线歌单 ↔ 自建歌单 的绑定与同步
 *
 * 对齐安卓版「收藏歌单 / 列表级同步」：
 * - 收藏在线歌单 = 创建一个绑定 `source + sourceListId` 的自建歌单（全量拉取歌曲），
 *   在「我的列表」里可见、可播放；
 * - 再次收藏或点「同步」时，重新从在线拉取并覆盖本地内容（安卓 syncSourceList）；
 * - 旧版本只写了 `collection.songlists` 标记、既不可见也无法同步，这里做一次性迁移。
 */
import hilog from '@ohos.hilog';
import { getSongListDetail } from '../core/music/MusicFeatureEntry';
import type { MusicInfo } from '../types/MusicTypes';
import {
  createUserListWithSongs,
  findUserListByBinding,
  getUserListMusic,
  markUserListSynced,
  replaceUserListMusic,
  getUserList,
  deleteUserList,
  type ListInfo,
  type MusicItem,
} from './ListService';
import StorageService, { StorageKeys } from './StorageService';

const TAG = 'UserListSync';
const DOMAIN = 0x0005;
/** 单页条数（与歌单详情一致） */
const PAGE_LIMIT = 100;
/** 最多拉取的页数，避免异常数据导致死循环 */
const MAX_PAGES = 30;

/** 旧版本收藏标记 */
interface LegacyCollectionEntry {
  id: string;
  source: string;
  name: string;
  creator: string;
  pic: string;
  desc: string;
  playCount: number;
  collectTime: number;
}

/** 把在线歌曲转换成列表项 */
function toMusicItem(music: MusicInfo): MusicItem {
  return {
    id: music.songmid || music.id || '',
    name: music.name || '',
    singer: music.singer || '',
    album: music.albumName || music.album || '',
    albumId: music.albumId ?? null,
    duration: parseDuration(music.interval),
    source: music.source as string,
    pic: music.img || music.pic || '',
    lrc: null,
  };
}

/** 'mm:ss' -> 秒 */
function parseDuration(interval: string | null | undefined): number {
  if (!interval) {
    return 0;
  }
  const parts = interval.split(':');
  let seconds = 0;
  for (let i = 0; i < parts.length; i++) {
    const value = parseInt(parts[i], 10);
    if (!isNaN(value)) {
      seconds = seconds * 60 + value;
    }
  }
  return seconds;
}

/**
 * 全量拉取在线歌单歌曲（按 total/limit 翻页，直到拉完或达到上限）
 */
export async function fetchAllOnlineSongs(source: string, listId: string): Promise<MusicItem[]> {
  const result: MusicItem[] = [];
  let page = 1;
  let total = -1;
  while (page <= MAX_PAGES) {
    const detail = await getSongListDetail(listId, page, source);
    const pageList = detail.list ?? [];
    for (let i = 0; i < pageList.length; i++) {
      result.push(toMusicItem(pageList[i]));
    }
    if (total < 0) {
      total = detail.total ?? 0;
    }
    // 拉完或本页不足一页即结束
    if (pageList.length === 0 || pageList.length < PAGE_LIMIT) {
      break;
    }
    if (total > 0 && result.length >= total) {
      break;
    }
    page += 1;
  }
  hilog.info(DOMAIN, TAG, 'Fetched online songs: source=%{public}s id=%{public}s count=%{public}d',
    source, listId, result.length);
  return result;
}

/** 收藏结果 */
export interface CollectResult {
  /** created = 新建绑定列表；已存在时返回 existing */
  status: 'created' | 'existing';
  list?: ListInfo;
  /** 已存在时，本地已有多少首 */
  localCount?: number;
}

/**
 * 收藏在线歌单：不存在绑定列表时创建（全量拉取），已存在时返回 existing 交给调用方决定是否同步
 */
export async function collectOnlineSonglist(
  source: string,
  listId: string,
  name: string,
  pic: string = ''
): Promise<CollectResult> {
  const existing = findUserListByBinding(source, listId);
  if (existing) {
    return { status: 'existing', list: existing, localCount: getUserListMusic(existing.id).length };
  }
  const songs = await fetchAllOnlineSongs(source, listId);
  const created = await createUserListWithSongs(name, songs, source, listId, pic);
  return { status: 'created', list: created, localCount: songs.length };
}

/** 同步结果 */
export interface SyncResult {
  ok: boolean;
  /** 同步后的歌曲数 */
  count: number;
  listName: string;
}

/**
 * 列表级同步：把绑定的在线歌单内容重新拉取并覆盖本地（安卓 syncSourceList）
 */
export async function syncUserListFromOnline(listId: string): Promise<SyncResult> {
  const info = findBoundListInfo(listId);
  if (!info || !info.bindingSource || !info.bindingListId) {
    return { ok: false, count: 0, listName: info?.name ?? '' };
  }
  const songs = await fetchAllOnlineSongs(info.bindingSource, info.bindingListId);
  await replaceUserListMusic(listId, songs);
  await markUserListSynced(listId);
  return { ok: true, count: songs.length, listName: info.name };
}

/** 从用户列表里取一条（同步入口只传 listId） */
function findBoundListInfo(listId: string): ListInfo | null {
  const list = getUserList();
  for (let i = 0; i < list.length; i++) {
    if (list[i].id === listId) {
      return list[i];
    }
  }
  return null;
}

/** 该在线歌单是否已收藏（存在绑定列表） */
export function isOnlineSonglistCollected(source: string, listId: string): boolean {
  return findUserListByBinding(source, listId) !== undefined;
}

/** 取消收藏：删除对应的绑定列表 */
export async function uncollectOnlineSonglist(source: string, listId: string): Promise<boolean> {
  const existing = findUserListByBinding(source, listId);
  if (!existing) {
    return false;
  }
  await deleteUserList(existing.id);
  return true;
}

/**
 * 一次性迁移：旧版本把「收藏歌单」只写进 collection.songlists 标记，
 * 这里转成绑定列表（歌曲留待用户点同步时拉取），迁移后清掉旧标记。
 */
export async function migrateLegacyCollections(): Promise<void> {
  try {
    const raw = await StorageService.getString(StorageKeys.COLLECTION_SONGLISTS, '');
    if (raw.length === 0) {
      return;
    }
    const entries = JSON.parse(raw) as LegacyCollectionEntry[];
    if (!Array.isArray(entries) || entries.length === 0) {
      return;
    }
    let migrated = 0;
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      if (!entry || !entry.id || !entry.source) {
        continue;
      }
      if (findUserListByBinding(entry.source, entry.id)) {
        continue;
      }
      await createUserListWithSongs(entry.name || entry.id, [], entry.source, entry.id, entry.pic ?? '');
      migrated++;
    }
    // 清掉旧标记，之后以「绑定列表是否存在」作为收藏状态
    await StorageService.setString(StorageKeys.COLLECTION_SONGLISTS, '');
    hilog.info(DOMAIN, TAG, 'Legacy collections migrated: %{public}d', migrated);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'migrateLegacyCollections failed: %{public}s', JSON.stringify(err));
  }
}
