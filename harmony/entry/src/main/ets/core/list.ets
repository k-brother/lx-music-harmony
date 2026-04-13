// List - 对应 src/core/list.ts
// 播放列表管理

import { stateEvent } from '../event/StateEvent';

// 列表状态接口
interface ListStateInterface {
  lists: ListItem[];
  defaultList: ListInfo | null;
  loveList: ListInfo | null;
  userList: ListInfo[];
  userListMusic: Record<string, MusicItem[]>;
}

// 临时实例
const listState: ListStateInterface = {
  lists: [],
  defaultList: null,
  loveList: null,
  userList: [],
  userListMusic: {},
};

// 列表ID接口
interface ListIds {
  LOVE: string;
  DEFAULT: string;
  DOWNLOAD: string;
  HISTORY: string;
}

// 列表ID常量 - 使用明确的类型声明
export const LIST_IDS: ListIds = {
  LOVE: 'love',
  DEFAULT: 'default',
  DOWNLOAD: 'download',
  HISTORY: 'history',
};

// 音乐项接口
interface MusicItem {
  id: string;
  name: string;
  singer: string;
  album: string;
  pic: string;
  duration: number;
  url: string;
}

// 列表项接口
interface ListItem {
  id: string;
  name: string;
  desc: string;
  list: MusicItem[];
}

// 列表信息接口
interface ListInfo {
  id: string;
  name: string;
  count: number;
  desc: string | null;
  pic: string | null;
  type: string | null;
  createTime: number | null;
  updateTime: number | null;
}

// 更新信息接口
interface UpdateInfo {
  name: string | null;
  desc: string | null;
  pic: string | null;
  count: number | null;
}

// 添加歌曲到列表
export function addListMusics(listId: string, musics: MusicItem[], addLocationType: string = 'top'): number {
  const list = getList(listId);
  if (!list) return 0;

  const musicItems: MusicItem[] = [];
  for (const m of musics) {
    const musicItem: MusicItem = {
      id: m.id || generateMusicId(),
      name: m.name,
      singer: m.singer,
      album: m.album,
      pic: m.pic,
      duration: m.duration,
      url: m.url,
    };
    musicItems.push(musicItem);
  }

  if (addLocationType === 'top') {
    for (let i = musicItems.length - 1; i >= 0; i--) {
      list.unshift(musicItems[i]);
    }
  } else {
    for (const item of musicItems) {
      list.push(item);
    }
  }

  stateEvent.mylistUpdated(getMyLists());
  return musicItems.length;
}

// 从列表移除歌曲
export function removeListMusics(listId: string, musicIds: string[]): number {
  const list = getList(listId);
  if (!list) return 0;

  let removedCount = 0;
  for (const id of musicIds) {
    const index = list.findIndex(m => m.id === id);
    if (index !== -1) {
      list.splice(index, 1);
      removedCount++;
    }
  }

  stateEvent.mylistUpdated(getMyLists());
  return removedCount;
}

// 获取列表
export function getList(listId: string): MusicItem[] {
  const list = listState.lists.find(l => l.id === listId);
  return list ? list.list : [];
}

// 获取我的所有列表
export function getMyLists(): ListInfo[] {
  const lists: ListInfo[] = [];

  if (listState.defaultList) {
    lists.push(listState.defaultList);
  }
  if (listState.loveList) {
    lists.push(listState.loveList);
  }

  for (const userList of listState.userList) {
    lists.push(userList);
  }

  return lists;
}

// 更新列表
export function updateList(listId: string, updateInfo: UpdateInfo): void {
  switch (listId) {
    case LIST_IDS.LOVE:
      if (listState.loveList) {
        if (updateInfo.name !== null) listState.loveList.name = updateInfo.name;
        if (updateInfo.desc !== null) listState.loveList.desc = updateInfo.desc;
        if (updateInfo.pic !== null) listState.loveList.pic = updateInfo.pic;
        if (updateInfo.count !== null) listState.loveList.count = updateInfo.count;
      }
      break;
    case LIST_IDS.DEFAULT:
      if (listState.defaultList) {
        if (updateInfo.name !== null) listState.defaultList.name = updateInfo.name;
        if (updateInfo.desc !== null) listState.defaultList.desc = updateInfo.desc;
        if (updateInfo.pic !== null) listState.defaultList.pic = updateInfo.pic;
        if (updateInfo.count !== null) listState.defaultList.count = updateInfo.count;
      }
      break;
    default:
      const userListIndex = listState.userList.findIndex(l => l.id === listId);
      if (userListIndex !== -1) {
        const userList = listState.userList[userListIndex];
        if (updateInfo.name !== null) userList.name = updateInfo.name;
        if (updateInfo.desc !== null) userList.desc = updateInfo.desc;
        if (updateInfo.pic !== null) userList.pic = updateInfo.pic;
        if (updateInfo.count !== null) userList.count = updateInfo.count;
      }
  }
  stateEvent.mylistUpdated(getMyLists());
}

// 创建用户列表
export function createUserList(name: string, desc: string = ''): ListInfo {
  const newList: ListInfo = {
    id: `user_${Date.now()}`,
    name,
    desc: desc || '',
    pic: '',
    count: 0,
    type: 'user',
    createTime: Date.now(),
    updateTime: Date.now(),
  };

  listState.userList.push(newList);
  stateEvent.mylistUpdated(getMyLists());
  return newList;
}

// 删除用户列表
export function removeUserList(listId: string): boolean {
  const index = listState.userList.findIndex(l => l.id === listId);
  if (index === -1) return false;

  listState.userList.splice(index, 1);

  // 移除对应的音乐数据
  const musicKey = listId.replace('user_', '');
  if (listState.userListMusic[musicKey]) {
    listState.userListMusic[musicKey] = [];
  }

  stateEvent.mylistUpdated(getMyLists());
  return true;
}

// 生成音乐ID
function generateMusicId(): string {
  const timestamp = Date.now().toString(36);
  const randomStr = Math.floor(Math.random() * 1000000).toString(36);
  return timestamp + randomStr;
}
