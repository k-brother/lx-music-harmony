/**
 * 评论相关的数据结构与各源原始响应类型
 *
 * 从 CommentService 拆出：页面、各源适配器都要用，集中一处避免结构漂移。
 */

/** 通用 JSON 对象（ArkTS 里 JSON.parse 结果的形状） */
export type CommentJsonObject = Record<string, Object>;

export interface Comment {
  id: string;
  content: string;
  userName: string;
  userAvatar: string;
  time: string;
  likeCount: number;
  replyCount: number;
  isLiked: boolean;
  isHot: boolean;
  source: string;
  /** 评论图片（可能多张），点击可查看大图 */
  images: string[];
  /** IP 归属地（部分源返回） */
  location: string;
  /** 楼层回复（子评论），按源是否返回子评论决定 */
  replies: Comment[];
}

export interface CommentResponse {
  source: string;
  comments: Comment[];
  total: number;
  page: number;
  limit: number;
  maxPage: number;
}

export interface KwCommentApiResponse {
  code: string;
  comments_counts?: number;
  hot_comments_counts?: number;
  comments?: KwCommentItem[];
  hot_comments?: KwCommentItem[];
}

export interface KwCommentItem {
  cid?: string;
  msg?: string;
  u_name?: string;
  u_pic?: string;
  u_id?: string;
  time?: string | number;
  like_num?: string;
  reply_num?: string;
  is_hot?: string;
  /** 评论图片（URL 编码） */
  mpic?: string;
  /** 楼层回复 */
  child_comments?: KwCommentItem[];
}
