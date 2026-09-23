/**
 * 歌单 ID 常量
 *
 * 从 ListService 抽出：存储层（ListStorage）与业务层（ListService）都要用它，
 * 放在中立模块避免两边互相依赖。ListService 仍然 re-export，调用方 import 路径不变。
 */

/** 内置列表 id 集合 */
export interface ListIdsInterface {
  DEFAULT: string;
  LOVE: string;
  TEMP: string;
  DOWNLOAD: string;
  PLAY_LATER: string | null;
}

export const LIST_IDS: ListIdsInterface = {
  DEFAULT: 'default',
  LOVE: 'love',
  TEMP: 'temp',
  DOWNLOAD: 'download',
  PLAY_LATER: null,
};
