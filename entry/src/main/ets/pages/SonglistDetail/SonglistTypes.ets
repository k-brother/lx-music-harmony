import type { SongRowLike } from '../../core/list/SongMappers';

/**
 * 歌单详情页的类型定义
 *
 * 抽到独立文件：页面与头部/批量栏/排序面板等组件共用，避免类型散落在页面尾部。
 */

/**
 * 列表中的一首歌
 *
 * 继承 core/list/SongMappers 的 SongRowLike：这样既可以复用统一转换器
 * （ArkTS 不支持结构化类型，必须显式继承才能传参），又保证字段口径一致。
 */
export interface SongItem extends SongRowLike {
  isPlaying: boolean;
}

/** 歌单信息 */
export interface SonglistInfo {
  source: string;
  id: string;
  name: string;
  creator: string;
  pic: string;
  desc: string;
  playCount: number;
}
