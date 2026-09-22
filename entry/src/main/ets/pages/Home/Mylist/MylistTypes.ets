/**
 * 「我的」页的类型定义
 *
 * 抽到独立文件：页面与行/卡片/列表组件共用，避免类型散落在页面顶部。
 */

/** 歌曲行（我喜欢 / 播放历史共用） */
export interface MylistSongRow {
  id: string;
  name: string;
  singer: string;
  album?: string;
  pic?: string;
  duration: number;
  source: string;
  songmid?: string;
  albumId?: string;
  hash?: string;
}

/** 自建歌单行 */
export interface UserListRow {
  id: string;
  name: string;
  pic: string;
  count: number;
  musicList: MylistSongRow[];
  /** 绑定在线歌单时非空（显示来源角标 + 提供同步入口） */
  bindingSource: string;
  bindingListId: string;
}
