/**
 * 歌单存储层（Preferences 读写）
 *
 * 从 ListService 抽出：默认/我喜欢/自建歌单的读写格式与键名规则集中在这里，
 * 业务层只关心内存里的列表状态。三种列表的存取结构一致（`{ info, music }`），
 * 自建歌单另有一个「索引」键（只存元信息）。
 */
import StorageService from '../StorageService';
import { LIST_IDS } from './ListIds';
import type { IMusicItem } from '../../core/interfaces/IMusicItem';
import type { ListInfo } from '../ListService';

/** 歌单项（与 ListService 的 MusicItem 同一类型） */
type MusicItem = IMusicItem;

/** 自建歌单的歌曲存储键 */
function userListMusicKey(listId: string): string {
  return `list.user.${listId}`;
}

/** 从存储读出的一份快照（业务层直接赋值到内存状态） */
export interface StoredListsSnapshot {
  defaultList: ListInfo | null;
  defaultListMusic: MusicItem[];
  loveList: ListInfo | null;
  loveListMusic: MusicItem[];
  userList: ListInfo[];
  userListMusic: Map<string, MusicItem[]>;
}

/** 创建列表元信息（默认/我喜欢初始化时用） */
export function createListInfo(id: string, name: string, type: string): ListInfo {
  const now: number = Date.now();
  const info: ListInfo = {
    id: id,
    name: name,
    source: type === 'user' ? 'local' : type,
    desc: '',
    pic: '',
    count: 0,
    createTime: now,
    updateTime: now,
  };
  return info;
}

/** 读取自建歌单的歌曲（兼容数组与 { music } 两种历史结构） */
async function loadUserListMusic(listId: string): Promise<MusicItem[]> {
  const raw = await StorageService.getString(userListMusicKey(listId), '');
  if (raw.length === 0) {
    return [];
  }
  try {
    const parsed = JSON.parse(raw) as Object;
    if (Array.isArray(parsed)) {
      return parsed as MusicItem[];
    }
    const record = parsed as Record<string, Object>;
    if (Array.isArray(record['music'])) {
      return record['music'] as MusicItem[];
    }
    return [];
  } catch (e) {
    return [];
  }
}

/** 读取全部列表（默认 / 我喜欢 / 自建 + 各自歌曲） */
export async function loadListsFromStorage(): Promise<StoredListsSnapshot> {
  const defaultRaw = await StorageService.getString(StorageService.StorageKeys.LIST_DEFAULT, '');
  let defaultList: ListInfo | null = null;
  let defaultListMusic: MusicItem[] = [];
  if (defaultRaw.length > 0) {
    try {
      const record = JSON.parse(defaultRaw) as Record<string, Object>;
      defaultList = record['info'] as ListInfo;
      defaultListMusic = (record['music'] as MusicItem[]) || [];
    } catch (e) {
      defaultList = null;
    }
  }
  if (!defaultList) {
    defaultList = createListInfo(LIST_IDS.DEFAULT, '默认列表', 'default');
    defaultListMusic = [];
  }

  const loveRaw = await StorageService.getString(StorageService.StorageKeys.LIST_LOVE, '');
  let loveList: ListInfo | null = null;
  let loveListMusic: MusicItem[] = [];
  if (loveRaw.length > 0) {
    try {
      const record = JSON.parse(loveRaw) as Record<string, Object>;
      loveList = record['info'] as ListInfo;
      loveListMusic = (record['music'] as MusicItem[]) || [];
    } catch (e) {
      loveList = null;
    }
  }
  if (!loveList) {
    loveList = createListInfo(LIST_IDS.LOVE, '我喜欢', 'love');
    loveListMusic = [];
  }

  const userRaw = await StorageService.getString(StorageService.StorageKeys.LIST_USER, '');
  let userList: ListInfo[] = [];
  const userListMusic: Map<string, MusicItem[]> = new Map();
  if (userRaw.length > 0) {
    try {
      const record = JSON.parse(userRaw) as Record<string, Object>;
      userList = (record['info'] as ListInfo[]) || [];
    } catch (e) {
      userList = [];
    }
  }
  for (let i = 0; i < userList.length; i++) {
    userListMusic.set(userList[i].id, await loadUserListMusic(userList[i].id));
  }

  return {
    defaultList: defaultList,
    defaultListMusic: defaultListMusic,
    loveList: loveList,
    loveListMusic: loveListMusic,
    userList: userList,
    userListMusic: userListMusic,
  };
}

/** 保存某个列表（info 计数与更新时间由调用方维护） */
export async function saveListItems(listId: string, info: ListInfo, items: MusicItem[]): Promise<void> {
  let key: string;
  if (listId === LIST_IDS.DEFAULT) {
    key = StorageService.StorageKeys.LIST_DEFAULT;
  } else if (listId === LIST_IDS.LOVE) {
    key = StorageService.StorageKeys.LIST_LOVE;
  } else {
    key = userListMusicKey(listId);
  }
  info.count = items.length;
  info.updateTime = Date.now();
  await StorageService.setString(key, JSON.stringify({ info: info, music: items }));
}

/** 保存自建歌单索引（只存元信息） */
export async function saveUserListIndex(userLists: ListInfo[]): Promise<void> {
  await StorageService.setString(StorageService.StorageKeys.LIST_USER, JSON.stringify({ info: userLists }));
}

/** 删除自建歌单的歌曲数据 */
export async function removeUserListItems(listId: string): Promise<void> {
  await StorageService.remove(userListMusicKey(listId));
}
