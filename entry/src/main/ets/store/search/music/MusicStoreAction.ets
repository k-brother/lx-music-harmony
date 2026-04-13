// Music Search Action - 对应 src/store/search/music/action.ts
// 音乐搜索状态操作

import { musicSearchState, MusicInfoItem, ListInfo, Source } from './MusicStoreState';

// 设置搜索来源
export function setSource(source: Source): void {
  musicSearchState.source = source;
}

// 设置搜索关键字
export function setSearchText(text: string): void {
  musicSearchState.searchText = text;
}

// 设置列表信息结果接口
interface SetListInfoResult {
  list: MusicInfoItem[];
  source: string;
  total: number;
}

// 设置列表信息
export function setListInfo(result: SetListInfoResult, page: number, text: string): MusicInfoItem[] {
  const listInfo = musicSearchState.listInfos.get(result.source);
  if (!listInfo) return [];

  if (page === 1) {
    listInfo.list = result.list;
  } else {
    // 使用 concat 替代展开操作符
    listInfo.list = listInfo.list.concat(result.list);
  }

  listInfo.page = page;
  listInfo.total = result.total;
  listInfo.key = `${page}__${text}`;

  return listInfo.list;
}

// 清除列表信息
export function clearListInfo(source: Source): void {
  const listInfo = musicSearchState.listInfos.get(source);
  if (!listInfo) return;

  listInfo.list = [];
  listInfo.page = 1;
  listInfo.total = 0;
  listInfo.key = null;
}

// 获取列表信息
export function getListInfo(source: Source): ListInfo | null {
  return musicSearchState.listInfos.get(source) || null;
}

// 创建 musicSearchAction 对象
export class MusicSearchAction {
  setSource(source: Source): void {
    setSource(source);
  }

  setSearchText(text: string): void {
    setSearchText(text);
  }

  setListInfo(result: SetListInfoResult, page: number, text: string): MusicInfoItem[] {
    return setListInfo(result, page, text);
  }

  clearListInfo(source: Source): void {
    clearListInfo(source);
  }

  getListInfo(source: Source): ListInfo | null {
    return getListInfo(source);
  }
}

// 导出单例实例
export const musicSearchAction = new MusicSearchAction();
