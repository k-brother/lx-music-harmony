// Core 模块索引 - 对应 src/core/
// 统一导出所有核心模块

export {
  // 从 music 模块导出
  // 注意：如果有冲突的导出，需要显式指定
  type MusicInfo,
  type LyricInfo,
  type SearchResultItem,
  getMusicUrl,
  getLyricInfo,
  getPicPath,
  searchMusic,
  findMusic,
  musicSdk
} from './music/MusicFeatureEntry';

export {
  // 从 search/search 模块导出
  // 注意：如果有冲突的导出，需要显式指定
  setSearchType,
  setSearchText,
  getSearchHistory,
  addHistoryWord,
  removeHistoryWord,
  clearHistoryList,
  searchMusic as searchMusicFromSearch,
  searchSonglist,
  getHotSearch as getHotSearchFromSearch,
  getTipListInfo,
  clearSearchResult
} from './search/search';

// 导出 songlist 模块
export {
  getSortList,
  getTags,
  setListInfo,
  setList,
  clearList,
  getSongList,
  getSonglist,
  setListDetailInfo,
  setListDetail,
  clearListDetail,
  getListDetail,
  getSonglistDetail,
  getListDetailAll,
  getSonglistTags,
  collectSonglist,
  uncollectSonglist,
  type ListDetailInfo,
  type ListInfo,
  type ListResult
} from './songlist';

// 导出其他模块（这些模块没有冲突）
export * from './list';
export * from './leaderboard';
export * from './hotSearch';
export * from './lyric';
