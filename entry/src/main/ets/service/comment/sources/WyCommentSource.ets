/**
 * 网易云音乐 - 评论
 *
 * 由 CommentService 拆分而来：本文件只关心该平台的接口差异与字段映射。
 */
import { appLog as hilog } from '../../../core/log/AppLogger';
import type { MusicInfo } from '../../../types/MusicTypes';
import type { CommentSourceAdapter } from '../CommentSourceAdapter';
import type { Comment, CommentResponse, CommentJsonObject } from '../CommentTypes';
import {
  commentHttpRequest,
  buildCommentReply,
  extractCommentIpLocation,
  asCommentTimeInput,
  formatCommentTime,
} from '../CommentShared';

const DOMAIN: number = 0x0001;
const TAG: string = 'WyCommentSource';

  export async function fetchComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
    try {
      hilog.info(DOMAIN, TAG, 'Getting WY comments for: %{public}s', musicInfo.name);
      
      // 网易云音乐评论API需要音乐ID
      const musicId = musicInfo.id;
      if (!musicId) {
        throw new Error('Missing music ID for WY comments');
      }
      
      // 网易云音乐评论API URL
      const url = `https://music.163.com/api/v1/resource/comments/R_SO_4_${musicId}?limit=${limit}&offset=${(page - 1) * limit}`;
      
      // 发送HTTP请求
      const wyResponse: CommentJsonObject = await commentHttpRequest(url);
      if (Number(wyResponse['code']) !== 200) {
        throw new Error(`WY API error: ${wyResponse['code']}`);
      }
      
      let wyList: Object[] = [];
      const wc = wyResponse['comments'];
      if (Array.isArray(wc)) {
        wyList = wc as Object[];
      }
      const comments = filterComments(wyList);
      const total = Number(wyResponse['total'] ?? 0);
      const maxPage = Math.ceil(total / limit);
      
      return {
        source: 'wy',
        comments,
        total,
        page,
        limit,
        maxPage
      };
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get WY comments: %{public}s', JSON.stringify(err));
      throw new Error(`Failed to get WY comments: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  export async function fetchHotComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
    try {
      hilog.info(DOMAIN, TAG, 'Getting WY hot comments for: %{public}s', musicInfo.name);
      
      // 网易云音乐热门评论API
      const musicId = musicInfo.id;
      if (!musicId) {
        throw new Error('Missing music ID for WY hot comments');
      }
      
      // 网易云音乐热门评论API URL
      const url = `https://music.163.com/api/v1/resource/hotcomments/R_SO_4_${musicId}?limit=${limit}`;
      
      // 发送HTTP请求
      const wyResponse: CommentJsonObject = await commentHttpRequest(url);
      if (Number(wyResponse['code']) !== 200) {
        throw new Error(`WY hot API error: ${wyResponse['code']}`);
      }
      
      let hotWy: Object[] = [];
      const hc = wyResponse['hotComments'];
      const wc2 = wyResponse['comments'];
      if (Array.isArray(hc)) {
        hotWy = hc as Object[];
      } else if (Array.isArray(wc2)) {
        hotWy = wc2 as Object[];
      }
      const comments = filterComments(hotWy);
      const total = comments.length;
      const maxPage = 1; // 热门评论通常只有一页
      
      return {
        source: 'wy',
        comments,
        total,
        page: 1,
        limit,
        maxPage
      };
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get WY hot comments: %{public}s', JSON.stringify(err));
      throw new Error(`Failed to get WY hot comments: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  function filterComments(wyComments: Object[]): Comment[] {
    const out: Comment[] = [];
    for (let i = 0; i < wyComments.length; i++) {
      const comment = wyComments[i] as CommentJsonObject;
      const user = comment['user'] as CommentJsonObject | undefined;
      const nick = user !== undefined && user !== null ? user['nickname'] : undefined;
      // 网易云的楼层回复只有被回复的那一条（beReplied[0]），与安卓版一致
      const replies: Comment[] = [];
      const beReplied = comment['beReplied'];
      if (Array.isArray(beReplied) && beReplied.length > 0) {
        const reply = beReplied[0] as CommentJsonObject;
        const replyUser = reply['user'] as CommentJsonObject | undefined;
        replies.push(buildCommentReply(
          String(reply['beRepliedCommentId'] ?? `wy_reply_${i}`),
          String(reply['content'] ?? ''),
          replyUser !== undefined && replyUser !== null ? String(replyUser['nickname'] ?? '匿名用户') : '匿名用户',
          replyUser !== undefined && replyUser !== null ? String(replyUser['avatarUrl'] ?? '') : '',
          formatCommentTime(asCommentTimeInput(reply['time'])),
          0,
          'wy',
          []
        ));
      }
      const commentObj: Comment = {
        id: String(comment['commentId'] ?? `wy_${Date.now()}_${Math.random()}`),
        content: String(comment['content'] ?? ''),
        userName: nick !== undefined && nick !== null ? String(nick) : '匿名用户',
        userAvatar: user !== undefined && user !== null ? String(user['avatarUrl'] ?? '') : '',
        time: formatCommentTime(asCommentTimeInput(comment['time'])),
        likeCount: Number(comment['likedCount'] ?? 0),
        replyCount: Number(comment['replyCount'] ?? 0),
        isLiked: Boolean(comment['liked']),
        isHot: Boolean(comment['hot']),
        source: 'wy',
        images: [],
        location: extractCommentIpLocation(comment['ipLocation']),
        replies
      };
      out.push(commentObj);
    }
    return out;
  }

/** 适配器：CommentService 通过它分发（新增平台只需再写一个这样的文件） */
export const wyCommentSource: CommentSourceAdapter = {
  fetch: fetchComments,
  fetchHot: fetchHotComments,
};
