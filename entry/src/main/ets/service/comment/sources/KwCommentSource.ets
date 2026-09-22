/**
 * 酷我音乐 - 评论
 *
 * 由 CommentService 拆分而来：本文件只关心该平台的接口差异与字段映射。
 */
import { appLog as hilog } from '../../../core/log/AppLogger';
import type { MusicInfo } from '../../../types/MusicTypes';
import type { CommentSourceAdapter } from '../CommentSourceAdapter';
import type { Comment, CommentResponse, CommentJsonObject, KwCommentApiResponse, KwCommentItem } from '../CommentTypes';
import {
  commentHttpRequest,
  buildCommentReply,
  formatCommentTime,
} from '../CommentShared';

const DOMAIN: number = 0x0001;
const TAG: string = 'KwCommentSource';

  function parseKwCommentResponse(raw: CommentJsonObject): KwCommentApiResponse {
    const commentsRaw = raw['comments'];
    const hotRaw = raw['hot_comments'];
    let comments: KwCommentItem[] | undefined = undefined;
    if (Array.isArray(commentsRaw)) {
      comments = commentsRaw as KwCommentItem[];
    }
    let hot_comments: KwCommentItem[] | undefined = undefined;
    if (Array.isArray(hotRaw)) {
      hot_comments = hotRaw as KwCommentItem[];
    }
    return {
      code: String(raw['code'] ?? ''),
      comments_counts: Number(raw['comments_counts'] ?? 0),
      hot_comments_counts: Number(raw['hot_comments_counts'] ?? 0),
      comments,
      hot_comments
    };
  }

  export async function fetchComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
    try {
      const songmid = musicInfo.songmid;
      if (!songmid) {
        throw new Error('Songmid is required for KW comments');
      }

      const start = limit * (page - 1);
      const url = `http://ncomment.kuwo.cn/com.s?f=web&type=get_comment&aapiver=1&prod=kwplayer_ar_10.5.2.0&digest=15&sid=${songmid}&start=${start}&msgflag=1&count=${limit}&newver=3&uid=0`;
      
      const response: KwCommentApiResponse = parseKwCommentResponse(await commentHttpRequest(url));
      
      if (response.code !== '200') {
        throw new Error(`KW API error: ${response.code}`);
      }

      const total = response.comments_counts || 0;
      const comments = filterComments(response.comments || []);
      
      return {
        source: 'kw',
        comments,
        total,
        page,
        limit,
        maxPage: Math.ceil(total / limit) || 1
      };
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get KW comments: %{public}s', JSON.stringify(err));
      throw new Error(`Failed to get KW comments: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  export async function fetchHotComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
    try {
      const songmid = musicInfo.songmid;
      if (!songmid) {
        throw new Error('Songmid is required for KW hot comments');
      }

      const start = limit * (page - 1);
      const url = `http://ncomment.kuwo.cn/com.s?f=web&type=get_rec_comment&aapiver=1&prod=kwplayer_ar_10.5.2.0&digest=15&sid=${songmid}&start=${start}&msgflag=1&count=${limit}&newver=3&uid=0`;
      
      const response: KwCommentApiResponse = parseKwCommentResponse(await commentHttpRequest(url));
      
      if (response.code !== '200') {
        throw new Error(`KW hot API error: ${response.code}`);
      }

      const total = response.hot_comments_counts || 0;
      const comments = filterComments(response.hot_comments || []);
      
      return {
        source: 'kw',
        comments,
        total,
        page,
        limit,
        maxPage: Math.ceil(total / limit) || 1
      };
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get KW hot comments: %{public}s', JSON.stringify(err));
      throw new Error(`Failed to get KW hot comments: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  function filterComments(kwComments: KwCommentItem[]): Comment[] {
    return kwComments.map((comment: KwCommentItem) => {
      // 解析时间戳 - 确保类型安全
      const time = formatCommentTime(comment.time ?? undefined);

      const replies: Comment[] = [];
      const children = comment.child_comments;
      if (children) {
        for (let i = 0; i < children.length; i++) {
          const child = children[i];
          replies.push(buildCommentReply(
            String(child.cid ?? `kw_reply_${i}`),
            child.msg || '',
            child.u_name || '匿名用户',
            child.u_pic || '',
            formatCommentTime(child.time ?? undefined),
            parseInt(child.like_num || '0') || 0,
            'kw',
            parseKwImages(child.mpic)
          ));
        }
      }

      const commentObj: Comment = {
        id: comment.cid || `kw_${Date.now()}_${Math.random()}`,
        content: comment.msg || '',
        userName: comment.u_name || '匿名用户',
        userAvatar: comment.u_pic || '',
        time,
        likeCount: parseInt(comment.like_num || '0') || 0,
        replyCount: parseInt(comment.reply_num || '0') || 0,
        isLiked: false,
        isHot: comment.is_hot === '1',
        source: 'kw',
        images: parseKwImages(comment.mpic),
        location: '',
        replies
      };
      return commentObj;
    });
  }

  function parseKwImages(mpic: string | undefined): string[] {
    if (!mpic || mpic.length === 0) {
      return [];
    }
    try {
      return [decodeURIComponent(mpic)];
    } catch (err) {
      return [mpic];
    }
  }

/** 适配器：CommentService 通过它分发（新增平台只需再写一个这样的文件） */
export const kwCommentSource: CommentSourceAdapter = {
  fetch: fetchComments,
  fetchHot: fetchHotComments,
};
