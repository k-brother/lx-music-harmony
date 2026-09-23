/**
 * 列表管理服务
 * 管理播放列表、我喜欢列表、用户列表
 */
import hilog from '@ohos.hilog';
import { emitListUpdated } from './EventBus';
import { settingsService } from './SettingsService';
import type { IMusicItem } from '../core/interfaces/IMusicItem';
import {
  createListInfo,
  loadListsFromStorage,
  saveListItems,
  saveUserListIndex,
  removeUserListItems,
  type StoredListsSnapshot,
} from './list/ListStorage';
import { LIST_IDS, type ListIdsInterface } from './list/ListIds';

// Re-export IMusicItem as MusicItem for consumers
export type MusicItem = IMusicItem;

const TAG = 'ListService';
const DOMAIN = 0x0005;

// 列表 ID 与存储层在 service/list/ 下（这里 re-export，调用方 import 路径不变）
export { LIST_IDS };
export type { ListIdsInterface } from './list/ListIds';
// 用户列表接口
interface UserList {
  id: string;
  name: string;
}

// 播放列表返回值接口
interface PlayListResult {
  listId: string | null;
  list: MusicItem[];
  index: number;
}

// 列表信息接口
export interface ListInfo {
  id: string;
  name: string;
  source: string;
  desc: string;
  pic: string;
  count: number;
  createTime: number;
  updateTime: number;
  /** 绑定的在线音源（收藏的在线歌单才有），安卓版对应 UserListInfo.source */
  bindingSource?: string;
  /** 绑定的在线歌单/排行榜 id，安卓版对应 UserListInfo.sourceListId */
  bindingListId?: string;
  /** 最近一次从在线同步的时间 */
  syncedAt?: number;
}

// 列表状态
class ListState {
  defaultList: ListInfo | null = null;
  loveList: ListInfo | null = null;
  userList: ListInfo[] = [];

  defaultListMusic: MusicItem[] = [];
  loveListMusic: MusicItem[] = [];
  userListMusic: Map<string, MusicItem[]> = new Map();

  playList: MusicItem[] = [];
  playListId: string | null = null;
  playIndex: number = -1;
}

// 单例
const listState = new ListState();

// 列表监听器
type ListChangeListener = (listId: string) => void;
const listeners: ListChangeListener[] = [];

/**
 * 初始化列表服务
 */
export async function initListService(): Promise<void> {
  try {
    // 从存储加载列表数据
    await loadLists();
    notifyListeners('__init__');
    hilog.info(DOMAIN, TAG, 'ListService initialized');
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to init list: %{public}s', JSON.stringify(err));
  }
}

/**
 * 加载所有列表
 */
/** 从存储层读快照并写入内存状态（读写细节在 service/list/ListStorage） */
async function loadLists(): Promise<void> {
  const snapshot: StoredListsSnapshot = await loadListsFromStorage();
  listState.defaultList = snapshot.defaultList;
  listState.defaultListMusic = snapshot.defaultListMusic;
  listState.loveList = snapshot.loveList;
  listState.loveListMusic = snapshot.loveListMusic;
  listState.userList = snapshot.userList;
  listState.userListMusic = snapshot.userListMusic;
}

/**
 * 获取默认列表
 */
export function getDefaultList(): MusicItem[] {
  return listState.defaultListMusic;
}

/**
 * 获取我喜欢列表
 */
export function getLoveList(): MusicItem[] {
  return listState.loveListMusic;
}

/**
 * 获取用户列表
 */
export function getUserList(): ListInfo[] {
  return listState.userList;
}

/**
 * 获取用户列表音乐
 */
export function getUserListMusic(listId: string): MusicItem[] {
  return listState.userListMusic.get(listId) || [];
}

/**
 * 解析列表容器
 *
 * 默认列表 / 我喜欢 / 用户列表三者的取用方式不同，之前 add / remove 各写一份 switch，
 * 加一个操作就要再抄一遍。这里统一成一处，新增列表操作只需调用它。
 */
function resolveListContainer(listId: string): MusicItem[] {
  switch (listId) {
    case LIST_IDS.DEFAULT:
      return listState.defaultListMusic;
    case LIST_IDS.LOVE:
      return listState.loveListMusic;
    default: {
      let list = listState.userListMusic.get(listId);
      if (!list) {
        list = [];
        listState.userListMusic.set(listId, list);
      }
      return list;
    }
  }
}

/**
 * 添加歌曲到列表
 */
export async function addMusicToList(listId: string, music: MusicItem): Promise<void> {
  const list: MusicItem[] = resolveListContainer(listId);
  // 检查是否已存在
  if (findMusicIndex(list, music.id) > -1) {
    return;
  }

  // 添加位置由「设置 -> 列表设置 -> 添加歌曲位置」决定
  if (settingsService.get().addMusicLocation === 'bottom') {
    list.push(music);
  } else {
    list.unshift(music);
  }
  await saveList(listId);
  notifyListeners(listId);
}

/**
 * 从列表移除歌曲
 */
export async function removeMusicFromList(listId: string, musicId: string): Promise<void> {
  const list: MusicItem[] = resolveListContainer(listId);
  const index = findMusicIndex(list, musicId);
  if (index > -1) {
    list.splice(index, 1);
    await saveList(listId);
    notifyListeners(listId);
  }
}

/**
 * 调整歌曲在列表中的位置
 *
 * 对应安卓版「我的列表 → 歌曲右侧菜单 → 调整位置」。
 * @param targetPosition 目标位置，从 1 开始计数；越界会被收敛到列表首/尾
 * @returns 是否真的移动了（位置没变或歌曲不存在时返回 false）
 */
export async function moveMusicInList(
  listId: string, musicId: string, targetPosition: number
): Promise<boolean> {
  const list: MusicItem[] = resolveListContainer(listId);
  if (list.length < 2) {
    return false;
  }
  const from = findMusicIndex(list, musicId);
  if (from < 0) {
    return false;
  }

  const requested = Math.trunc(targetPosition);
  const to = Math.min(Math.max(requested - 1, 0), list.length - 1);
  if (to === from) {
    return false;
  }

  const moved = list.splice(from, 1)[0];
  list.splice(to, 0, moved);
  await saveList(listId);
  notifyListeners(listId);
  return true;
}

/**
 * 批量从列表移除歌曲（多选删除用）
 * 一次性落库并只广播一次，避免逐首删除造成的多次写盘与多次刷新
 * @returns 实际移除的数量
 */
export async function removeMusicsFromList(listId: string, musicIds: string[]): Promise<number> {
  if (musicIds.length === 0) {
    return 0;
  }
  let list: MusicItem[];
  switch (listId) {
    case LIST_IDS.DEFAULT:
      list = listState.defaultListMusic;
      break;
    case LIST_IDS.LOVE:
      list = listState.loveListMusic;
      break;
    default:
      list = listState.userListMusic.get(listId) || [];
  }
  const idSet = new Set<string>(musicIds);
  const kept: MusicItem[] = [];
  for (let i = 0; i < list.length; i++) {
    if (!idSet.has(list[i].id)) {
      kept.push(list[i]);
    }
  }
  const removed = list.length - kept.length;
  if (removed === 0) {
    return 0;
  }
  switch (listId) {
    case LIST_IDS.DEFAULT:
      listState.defaultListMusic = kept;
      break;
    case LIST_IDS.LOVE:
      listState.loveListMusic = kept;
      break;
    default:
      listState.userListMusic.set(listId, kept);
  }
  await saveList(listId);
  notifyListeners(listId);
  return removed;
}

function findMusicIndex(list: MusicItem[], musicId: string): number {
  for (let i = 0; i < list.length; i++) {
    if (list[i].id === musicId) {
      return i;
    }
  }
  return -1;
}

/**
 * 整体替换自建歌单内容（排序 / 去重 / 在线歌单同步成本地歌单都用它）
 *
 * 直接按传入顺序落库，不做"添加位置"处理，保证与用户看到的顺序一致。
 */
export async function replaceUserListMusic(listId: string, items: MusicItem[]): Promise<void> {
  if (listId === LIST_IDS.DEFAULT || listId === LIST_IDS.LOVE) {
    // 默认列表/我喜欢列表的排序走各自页面逻辑，这里只服务自建歌单
    hilog.warn(DOMAIN, TAG, 'replaceUserListMusic ignored for builtin list: %{public}s', listId);
    return;
  }
  listState.userListMusic.set(listId, items.slice());
  await saveList(listId);
  notifyListeners(listId);
}

/**
 * 保存列表到存储
 */
/**
 * 持久化「用户歌单索引」（只剩元信息：id/名字/绑定关系/计数）
 *
 * 原来 5 处各写一遍 `JSON.stringify({ info: listState.userList })` + setString，
 * 字段结构一旦调整要改 5 个地方；这里收成一个入口。
 */
async function persistUserListIndex(): Promise<void> {
  await saveUserListIndex(listState.userList);
}

async function saveList(listId: string): Promise<void> {
  let info: ListInfo;
  let list: MusicItem[];
  if (listId === LIST_IDS.DEFAULT) {
    info = listState.defaultList!;
    list = listState.defaultListMusic;
  } else if (listId === LIST_IDS.LOVE) {
    info = listState.loveList!;
    list = listState.loveListMusic;
  } else {
    info = findListInfoById(listState.userList, listId);
    list = listState.userListMusic.get(listId) || [];
  }
  // 落盘细节（键名规则、计数与更新时间）在 service/list/ListStorage
  await saveListItems(listId, info, list);
}

/**
 * 创建新列表
 */
export async function createUserList(name: string): Promise<ListInfo> {
  const randomPart = Math.random().toString(36).substring(2, 8);
  const id = `user_${Date.now()}_${randomPart}`;
  const info = createListInfo(id, name, 'user');
  info.createTime = Date.now();
  info.updateTime = Date.now();

  listState.userList.push(info);
  listState.userListMusic.set(id, []);

  // 保存用户列表索引
  await persistUserListIndex();

  notifyListeners(id);
  return info;
}

/**
 * 创建「绑定在线歌单」的自建歌单（收藏歌单用，对齐安卓版 createList 的 source/sourceListId）
 *
 * @param name 列表名（一般是歌单名）
 * @param songs 初始歌曲（收藏时全量拉取）
 * @param bindingSource 在线音源
 * @param bindingListId 在线歌单 id
 */
export async function createUserListWithSongs(
  name: string,
  songs: MusicItem[],
  bindingSource: string,
  bindingListId: string,
  pic: string = ''
): Promise<ListInfo> {
  const randomPart = Math.random().toString(36).substring(2, 8);
  const id = `user_${Date.now()}_${randomPart}`;
  const info = createListInfo(id, name, 'user');
  info.createTime = Date.now();
  info.updateTime = Date.now();
  info.pic = pic;
  info.bindingSource = bindingSource;
  info.bindingListId = bindingListId;
  info.count = songs.length;

  listState.userList.push(info);
  listState.userListMusic.set(id, songs.slice());

  await persistUserListIndex();
  await saveList(id);

  notifyListeners(id);
  hilog.info(DOMAIN, TAG, 'Bound user list created: %{public}s -> %{public}s/%{public}s',
    name, bindingSource, bindingListId);
  return info;
}

/** 按在线歌单绑定关系查找自建歌单（安卓版 listState.userList.find(l => l.sourceListId == listId)） */
export function findUserListByBinding(source: string, listId: string): ListInfo | undefined {
  for (let i = 0; i < listState.userList.length; i++) {
    const info = listState.userList[i];
    if (info.bindingSource === source && info.bindingListId === listId) {
      return info;
    }
  }
  return undefined;
}

/** 记录一次在线同步的时间（列表菜单里据此显示"已同步"） */
export async function markUserListSynced(listId: string): Promise<void> {
  const info = findListInfoById(listState.userList, listId);
  if (!info) {
    return;
  }
  info.syncedAt = Date.now();
  info.updateTime = Date.now();
  await persistUserListIndex();
  notifyListeners(listId);
}

/**
 * 删除用户列表
 */
export async function deleteUserList(listId: string): Promise<void> {
  const index = findListIndexById(listState.userList, listId);
  if (index > -1) {
    listState.userList.splice(index, 1);
    listState.userListMusic.delete(listId);

    // 保存用户列表索引
    await persistUserListIndex();
    await removeUserListItems(listId);

    notifyListeners(listId);
  }
}

/**
 * 重命名用户列表
 */
export async function renameUserList(listId: string, newName: string): Promise<void> {
  const info = findListInfoById(listState.userList, listId);
  if (info) {
    info.name = newName;
    info.updateTime = Date.now();
    await persistUserListIndex();
    notifyListeners(listId);
  }
}

function findListIndexById(list: ListInfo[], id: string): number {
  for (let i = 0; i < list.length; i++) {
    if (list[i].id === id) {
      return i;
    }
  }
  return -1;
}

function findListInfoById(list: ListInfo[], id: string): ListInfo {
  for (let i = 0; i < list.length; i++) {
    if (list[i].id === id) {
      return list[i];
    }
  }
  return listState.defaultList!;
}

/**
 * 设置播放列表
 */
export function setPlayList(listId: string | null, music: MusicItem[]): void {
  listState.playListId = listId;
  listState.playList = music;
  listState.playIndex = music.length > 0 ? 0 : -1;
}

/**
 * 获取播放列表
 */
export function getPlayList(): PlayListResult {
  return {
    listId: listState.playListId,
    list: listState.playList,
    index: listState.playIndex,
  };
}

/**
 * 设置播放索引
 */
export function setPlayIndex(index: number): void {
  listState.playIndex = index;
}

/**
 * 获取当前播放歌曲
 */
export function getCurrentMusic(): MusicItem | null {
  if (listState.playIndex >= 0 && listState.playIndex < listState.playList.length) {
    return listState.playList[listState.playIndex];
  }
  return null;
}

/**
 * 播放下一曲
 */
export function playNext(): MusicItem | null {
  if (listState.playIndex < listState.playList.length - 1) {
    listState.playIndex++;
    return getCurrentMusic();
  }
  return null;
}

/**
 * 播放上一曲
 */
export function playPrev(): MusicItem | null {
  if (listState.playIndex > 0) {
    listState.playIndex--;
    return getCurrentMusic();
  }
  return null;
}

/**
 * 检查歌曲是否在我喜欢列表
 */
export function isInLoveList(musicId: string): boolean {
  for (let i = 0; i < listState.loveListMusic.length; i++) {
    if (listState.loveListMusic[i].id === musicId) {
      return true;
    }
  }
  return false;
}

/**
 * 切换我喜欢状态
 */
export async function toggleLoveList(music: MusicItem): Promise<boolean> {
  if (isInLoveList(music.id)) {
    await removeMusicFromList(LIST_IDS.LOVE, music.id);
    return false;
  } else {
    await addMusicToList(LIST_IDS.LOVE, music);
    return true;
  }
}

/**
 * 订阅列表变化
 */
export function onListChange(listener: ListChangeListener): () => void {
  listeners.push(listener);
  return () => {
    const index = listeners.indexOf(listener);
    if (index > -1) {
      listeners.splice(index, 1);
    }
  };
}

/**
 * 通知监听器
 */
function notifyListeners(listId: string): void {
  emitListUpdated(listId);
  for (let i = 0; i < listeners.length; i++) {
    listeners[i](listId);
  }
}

// 列表服务接口
export interface ListServiceInterface {
  LIST_IDS: ListIdsInterface;
  initListService: () => Promise<void>;
  getDefaultList: () => MusicItem[];
  getLoveList: () => MusicItem[];
  getUserList: () => ListInfo[];
  getUserListMusic: (listId: string) => MusicItem[];
  addMusicToList: (listId: string, music: MusicItem) => Promise<void>;
  removeMusicFromList: (listId: string, musicId: string) => Promise<void>;
  createUserList: (name: string) => Promise<ListInfo>;
  deleteUserList: (listId: string) => Promise<void>;
  renameUserList: (listId: string, newName: string) => Promise<void>;
  setPlayList: (listId: string | null, music: MusicItem[]) => void;
  getPlayList: () => PlayListResult;
  setPlayIndex: (index: number) => void;
  getCurrentMusic: () => MusicItem | null;
  playNext: () => MusicItem | null;
  playPrev: () => MusicItem | null;
  isInLoveList: (musicId: string) => boolean;
  toggleLoveList: (music: MusicItem) => Promise<boolean>;
  onListChange: (callback: (listId: string) => void) => () => void;
}

// 导出列表服务
const listService: ListServiceInterface = {
  LIST_IDS,
  initListService,
  getDefaultList,
  getLoveList,
  getUserList,
  getUserListMusic,
  addMusicToList,
  removeMusicFromList,
  createUserList,
  deleteUserList,
  renameUserList,
  setPlayList,
  getPlayList,
  setPlayIndex,
  getCurrentMusic,
  playNext,
  playPrev,
  isInLoveList,
  toggleLoveList,
  onListChange,
};

export default listService;
