/**
 * 咪咕音乐 - 评论
 *
 * 由 CommentService 拆分而来：本文件只关心该平台的接口差异与字段映射。
 */
import { t } from '../../LocalizationService';
import { appLog as hilog } from '../../../core/log/AppLogger';
import type { MusicInfo } from '../../../types/MusicTypes';
import type { CommentSourceAdapter } from '../CommentSourceAdapter';
import type { Comment, CommentResponse, CommentJsonObject } from '../CommentTypes';
import {
  commentHttpRequest,
  buildCommentReply,
  asCommentTimeInput,
  formatCommentTime,
} from '../CommentShared';

const DOMAIN: number = 0x0001;
const TAG: string = 'MgCommentSource';

  export async function fetchComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
    try {
      hilog.info(DOMAIN, TAG, 'Getting MG comments for: %{public}s', musicInfo.name);
      
      // 咪咕音乐评论API需要contentId
      const contentId = musicInfo.id;
      if (!contentId) {
        throw new Error('Missing content ID for MG comments');
      }
      
      // 咪咕音乐评论API URL
      const url = `https://music.migu.cn/v3/api/comment/list?contentId=${contentId}&page=${page}&pageSize=${limit}&type=1`;
      
      // 发送HTTP请求
      const mgResponse: CommentJsonObject = await commentHttpRequest(url);
      if (String(mgResponse['code']) !== '000000') {
        throw new Error(`MG API error: ${mgResponse['code']}`);
      }
      
      const mgData = mgResponse['data'] as CommentJsonObject | undefined;
      let mgList: Object[] = [];
      if (mgData !== undefined && mgData !== null) {
        const lst = mgData['list'];
        if (Array.isArray(lst)) {
          mgList = lst as Object[];
        }
      }
      const comments = filterComments(mgList);
      const total = mgData !== undefined && mgData !== null ? Number(mgData['totalCount'] ?? 0) : 0;
      const maxPage = Math.ceil(total / limit);
      
      return {
        source: 'mg',
        comments,
        total,
        page,
        limit,
        maxPage
      };
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get MG comments: %{public}s', JSON.stringify(err));
      throw new Error(`Failed to get MG comments: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  export async function fetchHotComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
    try {
      hilog.info(DOMAIN, TAG, 'Getting MG hot comments for: %{public}s', musicInfo.name);
      
      // 咪咕音乐热门评论API
      const contentId = musicInfo.id;
      if (!contentId) {
        throw new Error('Missing content ID for MG hot comments');
      }
      
      // 咪咕音乐热门评论API URL
      const url = `https://music.migu.cn/v3/api/comment/hot?contentId=${contentId}&pageSize=${limit}&type=1`;
      
      // 发送HTTP请求
      const mgResponse: CommentJsonObject = await commentHttpRequest(url);
      if (String(mgResponse['code']) !== '000000') {
        throw new Error(`MG hot API error: ${mgResponse['code']}`);
      }
      
      const mgData = mgResponse['data'] as CommentJsonObject | undefined;
      let mgHotList: Object[] = [];
      if (mgData !== undefined && mgData !== null) {
        const lst = mgData['list'];
        if (Array.isArray(lst)) {
          mgHotList = lst as Object[];
        }
      }
      const comments = filterComments(mgHotList);
      const total = comments.length;
      const maxPage = 1; // 热门评论通常只有一页
      
      return {
        source: 'mg',
        comments,
        total,
        page: 1,
        limit,
        maxPage
      };
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get MG hot comments: %{public}s', JSON.stringify(err));
      throw new Error(`Failed to get MG hot comments: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  function filterComments(mgComments: Object[]): Comment[] {
    const out: Comment[] = [];
    for (let i = 0; i < mgComments.length; i++) {
      const comment = mgComments[i] as CommentJsonObject;
      const user = comment['user'] as CommentJsonObject | undefined;
      const nick = user !== undefined && user !== null ? user['nickName'] : undefined;
      // 咪咕：replyComments 就是楼层回复
      const replies: Comment[] = [];
      const replyComments = comment['replyComments'];
      if (Array.isArray(replyComments)) {
        for (let j = 0; j < replyComments.length; j++) {
          const reply = replyComments[j] as CommentJsonObject;
          const replyUser = reply['user'] as CommentJsonObject | undefined;
          replies.push(buildCommentReply(
            String(reply['replyId'] ?? `mg_reply_${j}`),
            String(reply['replyInfo'] ?? ''),
            replyUser !== undefined && replyUser !== null ? String(replyUser['nickName'] ?? t('comment_anonymous')) : t('comment_anonymous'),
            replyUser !== undefined && replyUser !== null
              ? String(replyUser['middleIcon'] ?? replyUser['bigIcon'] ?? replyUser['smallIcon'] ?? '')
              : '',
            formatCommentTime(asCommentTimeInput(reply['replyTime'])),
            0,
            'mg',
            []
          ));
        }
      }
      const commentObj: Comment = {
        id: String(comment['commentId'] ?? `mg_${Date.now()}_${Math.random()}`),
        content: String(comment['content'] ?? ''),
        userName: nick !== undefined && nick !== null ? String(nick) : t('comment_anonymous'),
        userAvatar: user !== undefined && user !== null ? String(user['headUrl'] ?? '') : '',
        time: formatCommentTime(asCommentTimeInput(comment['createTime'])),
        likeCount: Number(comment['likeCount'] ?? 0),
        replyCount: Number(comment['replyCount'] ?? 0),
        isLiked: Boolean(comment['isLiked']),
        isHot: Boolean(comment['isHot']),
        source: 'mg',
        images: [],
        location: '',
        replies
      };
      out.push(commentObj);
    }
    return out;
  }

/** 适配器：CommentService 通过它分发（新增平台只需再写一个这样的文件） */
export const mgCommentSource: CommentSourceAdapter = {
  fetch: fetchComments,
  fetchHot: fetchHotComments,
};
