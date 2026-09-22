/**
 * 评论源适配器接口
 *
 * 五个平台各实现一份（sources/*），CommentService 只做分发，
 * 新增平台时不需要再改一堆 if/else。
 */
import type { MusicInfo } from '../../types/MusicTypes';
import type { CommentResponse } from './CommentTypes';

export interface CommentSourceAdapter {
  /** 普通评论 */
  fetch: (musicInfo: MusicInfo, page: number, limit: number) => Promise<CommentResponse>;
  /** 热门评论 */
  fetchHot: (musicInfo: MusicInfo, page: number, limit: number) => Promise<CommentResponse>;
}
