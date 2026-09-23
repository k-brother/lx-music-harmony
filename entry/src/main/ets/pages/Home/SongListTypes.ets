/**
 * 歌单网格的数据结构
 *
 * 从 SongListView 抽出：卡片组件（pages/Home/SongList/SongListCard）与页面共用同一份字段口径，
 * 抽成独立文件后组件不必反向 import 页面。
 */

/** 歌单网格里的一张卡片 */
export interface SongListItemData {
  id: string;
  name: string;
  author: string;
  img: string;
  play_count: string;
  desc: string;
  total: number;
  source: string;
}
