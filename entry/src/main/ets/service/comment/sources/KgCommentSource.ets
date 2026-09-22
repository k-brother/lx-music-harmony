/**
 * 酷狗音乐 - 评论
 *
 * 由 CommentService 拆分而来：本文件只关心该平台的接口差异与字段映射。
 */
import { appLog as hilog } from '../../../core/log/AppLogger';
import type { MusicInfo } from '../../../types/MusicTypes';
import type { CommentSourceAdapter } from '../CommentSourceAdapter';
import type { Comment, CommentResponse, CommentJsonObject } from '../CommentTypes';
import {
  commentHttpRequest,
  extractCommentImages,
  asCommentTimeInput,
  formatCommentTime,
} from '../CommentShared';

const DOMAIN: number = 0x0001;
const TAG: string = 'KgCommentSource';

  export async function fetchComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
    try {
      hilog.info(DOMAIN, TAG, 'Getting KG comments for: %{public}s', musicInfo.name);
      
      // 酷狗音乐评论API需要hash或musicId
      const hash = musicInfo.hash;
      const musicId = musicInfo.id;
      if (!hash && !musicId) {
        throw new Error('Missing hash or music ID for KG comments');
      }
      
      // 酷狗音乐评论API URL
      const url = `https://comment.service.kugou.com/index.php?r=comments/getCommentsWithLike&code=fc4be23b4e972707f36b8a828a93ba8a&clientver=2000&clienttime=${Date.now()}&mid=${hash || musicId}&page=${page}&pagesize=${limit}&sort=0&type=1&cmd=0&grade=0`;
      
      // 发送HTTP请求
      const kgResponse: CommentJsonObject = await commentHttpRequest(url);
      if (Number(kgResponse['status']) !== 1) {
        throw new Error(`KG API error: ${kgResponse['status']}`);
      }
      
      const dataObj = kgResponse['data'] as CommentJsonObject | undefined;
      let kgList: Object[] = [];
      if (dataObj !== undefined && dataObj !== null) {
        const lst = dataObj['list'];
        if (Array.isArray(lst)) {
          kgList = lst as Object[];
        }
      }
      const comments = filterComments(kgList);
      const total = dataObj !== undefined && dataObj !== null ? Number(dataObj['total'] ?? 0) : 0;
      const maxPage = Math.ceil(total / limit);
      
      return {
        source: 'kg',
        comments,
        total,
        page,
        limit,
        maxPage
      };
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get KG comments: %{public}s', JSON.stringify(err));
      throw new Error(`Failed to get KG comments: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  export async function fetchHotComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
    try {
      hilog.info(DOMAIN, TAG, 'Getting KG hot comments for: %{public}s', musicInfo.name);
      
      // 酷狗音乐热门评论API
      const hash = musicInfo.hash;
      const musicId = musicInfo.id;
      if (!hash && !musicId) {
        throw new Error('Missing hash or music ID for KG hot comments');
      }
      
      // 酷狗音乐热门评论API URL
      const url = `https://comment.service.kugou.com/index.php?r=comments/getCommentsWithLike&code=fc4be23b4e972707f36b8a828a93ba8a&clientver=2000&clienttime=${Date.now()}&mid=${hash || musicId}&page=1&pagesize=${limit}&sort=1&type=1&cmd=0&grade=0`;
      
      // 发送HTTP请求
      const kgResponse: CommentJsonObject = await commentHttpRequest(url);
      if (Number(kgResponse['status']) !== 1) {
        throw new Error(`KG hot API error: ${kgResponse['status']}`);
      }
      
      const dataObj = kgResponse['data'] as CommentJsonObject | undefined;
      let kgHotList: Object[] = [];
      if (dataObj !== undefined && dataObj !== null) {
        const lst = dataObj['list'];
        if (Array.isArray(lst)) {
          kgHotList = lst as Object[];
        }
      }
      const comments = filterComments(kgHotList);
      const total = comments.length;
      const maxPage = 1; // 热门评论通常只有一页
      
      return {
        source: 'kg',
        comments,
        total,
        page: 1,
        limit,
        maxPage
      };
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get KG hot comments: %{public}s', JSON.stringify(err));
      throw new Error(`Failed to get KG hot comments: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  function filterComments(kgComments: Object[]): Comment[] {
    const out: Comment[] = [];
    for (let i = 0; i < kgComments.length; i++) {
      const comment = kgComments[i] as CommentJsonObject;
      const commentObj: Comment = {
        id: String(comment['commentid'] ?? `kg_${Date.now()}_${Math.random()}`),
        content: String(comment['content'] ?? ''),
        userName: String(comment['nickname'] ?? '匿名用户'),
        userAvatar: String(comment['userpic'] ?? ''),
        time: formatCommentTime(asCommentTimeInput(comment['addtime'])),
        likeCount: Number(comment['like_num'] ?? 0),
        replyCount: Number(comment['reply_num'] ?? 0),
        isLiked: comment['is_like'] === 1,
        isHot: comment['is_hot'] === 1,
        source: 'kg',
        images: extractCommentImages(comment['images']),
        location: String(comment['location'] ?? ''),
        replies: []
      };
      out.push(commentObj);
    }
    return out;
  }

/** 适配器：CommentService 通过它分发（新增平台只需再写一个这样的文件） */
export const kgCommentSource: CommentSourceAdapter = {
  fetch: fetchComments,
  fetchHot: fetchHotComments,
};
