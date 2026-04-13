/**
 * 列表管理服务
 * 管理播放列表、我喜欢列表、用户列表
 */
import hilog from '@ohos.hilog';
import StorageService from './StorageService';
import type { IMusicItem } from '../core/interfaces/IMusicItem';

// Re-export IMusicItem as MusicItem for consumers
export type MusicItem = IMusicItem;

const TAG = 'ListService';
const DOMAIN = 0x0005;

// 列表ID接口
interface ListIdsInterface {
  DEFAULT: string;
  LOVE: string;
  TEMP: string;
  DOWNLOAD: string;
  PLAY_LATER: string | null;
}

// 列表ID常量
export const LIST_IDS: ListIdsInterface = {
  DEFAULT: 'default',
  LOVE: 'love',
  TEMP: 'temp',
  DOWNLOAD: 'download',
  PLAY_LATER: null,
};

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
    hilog.info(DOMAIN, TAG, 'ListService initialized');
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to init list: %{public}s', JSON.stringify(err));
  }
}

/**
 * 加载所有列表
 */
async function loadLists(): Promise<void> {
  // 加载默认列表
  const defaultListData = await StorageService.getString(StorageService.StorageKeys.LIST_DEFAULT, '');
  if (defaultListData) {
    try {
      const parsed: Object = JSON.parse(defaultListData) as Object;
      listState.defaultList = (parsed as Record<string, Object>)['info'] as ListInfo;
      listState.defaultListMusic = ((parsed as Record<string, Object>)['music'] as MusicItem[]) || [];
    } catch (e) {
      // 初始化默认列表
      listState.defaultList = createListInfo(LIST_IDS.DEFAULT, '默认列表', 'default');
      listState.defaultListMusic = [];
    }
  } else {
    listState.defaultList = createListInfo(LIST_IDS.DEFAULT, '默认列表', 'default');
    listState.defaultListMusic = [];
  }

  // 加载我喜欢列表
  const loveListData = await StorageService.getString(StorageService.StorageKeys.LIST_LOVE, '');
  if (loveListData) {
    try {
      const parsed: Object = JSON.parse(loveListData) as Object;
      listState.loveList = (parsed as Record<string, Object>)['info'] as ListInfo;
      listState.loveListMusic = ((parsed as Record<string, Object>)['music'] as MusicItem[]) || [];
    } catch (e) {
      listState.loveList = createListInfo(LIST_IDS.LOVE, '我喜欢', 'love');
      listState.loveListMusic = [];
    }
  } else {
    listState.loveList = createListInfo(LIST_IDS.LOVE, '我喜欢', 'love');
    listState.loveListMusic = [];
  }

  // 加载用户列表
  const userListData = await StorageService.getString(StorageService.StorageKeys.LIST_USER, '');
  if (userListData) {
    try {
      const parsed: Object = JSON.parse(userListData) as Object;
      listState.userList = ((parsed as Record<string, Object>)['info'] as ListInfo[]) || [];
      // 加载用户列表音乐
      for (let i = 0; i < listState.userList.length; i++) {
        const info = listState.userList[i];
        const key = `list.user.${info.id}`;
        const musicData = await StorageService.getString(key, '');
        if (musicData) {
          listState.userListMusic.set(info.id, JSON.parse(musicData) as MusicItem[]);
        }
      }
    } catch (e) {
      listState.userList = [];
    }
  } else {
    listState.userList = [];
  }
}

/**
 * 创建列表信息
 */
function createListInfo(id: string, name: string, type: string): ListInfo {
  return {
    id,
    name,
    source: type,
    desc: '',
    pic: '',
    count: 0,
    createTime: Date.now(),
    updateTime: Date.now(),
  };
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
 * 添加歌曲到列表
 */
export async function addMusicToList(listId: string, music: MusicItem): Promise<void> {
  let list: MusicItem[];
  let key: string;

  switch (listId) {
    case LIST_IDS.DEFAULT:
      list = listState.defaultListMusic;
      key = StorageService.StorageKeys.LIST_DEFAULT;
      break;
    case LIST_IDS.LOVE:
      list = listState.loveListMusic;
      key = StorageService.StorageKeys.LIST_LOVE;
      break;
    default:
      list = listState.userListMusic.get(listId) || [];
      listState.userListMusic.set(listId, list);
      key = `list.user.${listId}`;
  }

  // 检查是否已存在
  let exists = false;
  for (let i = 0; i < list.length; i++) {
    if (list[i].id === music.id) {
      exists = true;
      break;
    }
  }
  if (exists) {
    return;
  }

  list.push(music);
  await saveList(listId);
  notifyListeners(listId);
}

/**
 * 从列表移除歌曲
 */
export async function removeMusicFromList(listId: string, musicId: string): Promise<void> {
  let list: MusicItem[];
  let key: string;

  switch (listId) {
    case LIST_IDS.DEFAULT:
      list = listState.defaultListMusic;
      key = StorageService.StorageKeys.LIST_DEFAULT;
      break;
    case LIST_IDS.LOVE:
      list = listState.loveListMusic;
      key = StorageService.StorageKeys.LIST_LOVE;
      break;
    default:
      list = listState.userListMusic.get(listId) || [];
      key = `list.user.${listId}`;
  }

  const index = findMusicIndex(list, musicId);
  if (index > -1) {
    list.splice(index, 1);
    await saveList(listId);
    notifyListeners(listId);
  }
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
 * 保存列表到存储
 */
async function saveList(listId: string): Promise<void> {
  let info: ListInfo;
  let list: MusicItem[];
  let key: string;

  switch (listId) {
    case LIST_IDS.DEFAULT:
      info = listState.defaultList!;
      list = listState.defaultListMusic;
      key = StorageService.StorageKeys.LIST_DEFAULT;
      break;
    case LIST_IDS.LOVE:
      info = listState.loveList!;
      list = listState.loveListMusic;
      key = StorageService.StorageKeys.LIST_LOVE;
      break;
    default:
      info = findListInfoById(listState.userList, listId);
      list = listState.userListMusic.get(listId) || [];
      key = `list.user.${listId}`;
  }

  info.count = list.length;
  info.updateTime = Date.now();

  const data = JSON.stringify({ info, music: list });
  await StorageService.setString(key, data);
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
  const data = JSON.stringify({
    info: listState.userList,
  });
  await StorageService.setString(StorageService.StorageKeys.LIST_USER, data);

  notifyListeners(id);
  return info;
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
    const data = JSON.stringify({
      info: listState.userList,
    });
    await StorageService.setString(StorageService.StorageKeys.LIST_USER, data);
    await StorageService.remove(`list.user.${listId}`);

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
