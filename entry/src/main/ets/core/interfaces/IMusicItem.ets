/**
 * 音乐项接口定义
 * core层通过此接口定义音乐数据结构，避免直接依赖service层
 */

/**
 * 音乐项接口
 */
export interface IMusicItem {
  id: string;
  name: string;
  singer: string;
  album: string;
  albumId: string | null;
  duration: number;
  source: string;
  pic: string;
  lrc: string | null;
}
