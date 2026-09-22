/**
 * QQ 音乐 - 评论
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
  extractCommentImages,
  asCommentTimeInput,
  formatCommentTime,
} from '../CommentShared';

const DOMAIN: number = 0x0001;
const TAG: string = 'TxCommentSource';

  export async function fetchComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
    try {
      hilog.info(DOMAIN, TAG, 'Getting TX comments for: %{public}s', musicInfo.name);
      
      // QQ音乐评论API需要songmid
      const songmid = musicInfo.songmid || musicInfo.id;
      if (!songmid) {
        throw new Error('Missing songmid for TX comments');
      }
      
      // QQ音乐评论API URL
      const url = `https://c.y.qq.com/base/fcgi-bin/fcg_global_comment_h5.fcg?g_tk=5381&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0&cid=205360772&reqtype=2&biztype=1&topid=${songmid}&cmd=8&needmusiccrit=0&pagenum=${page - 1}&pagesize=${limit}&lasthotcommentid=&domain=qq.com&ct=24&cv=10101010`;
      
      // 发送HTTP请求
      const txResponse: CommentJsonObject = await commentHttpRequest(url);
      if (Number(txResponse['code']) !== 0) {
        throw new Error(`TX API error: ${txResponse['code']}`);
      }
      
      const commentRoot = txResponse['comment'] as CommentJsonObject | undefined;
      let txList: Object[] = [];
      if (commentRoot !== undefined && commentRoot !== null) {
        const cl = commentRoot['commentlist'];
        if (Array.isArray(cl)) {
          txList = cl as Object[];
        }
      }
      const comments = filterComments(txList);
      const total = commentRoot !== undefined && commentRoot !== null
        ? Number(commentRoot['commenttotal'] ?? 0)
        : 0;
      const maxPage = Math.ceil(total / limit);
      
      return {
        source: 'tx',
        comments,
        total,
        page,
        limit,
        maxPage
      };
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get TX comments: %{public}s', JSON.stringify(err));
      throw new Error(`Failed to get TX comments: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  export async function fetchHotComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
    try {
      hilog.info(DOMAIN, TAG, 'Getting TX hot comments for: %{public}s', musicInfo.name);
      
      // QQ音乐热门评论API
      const songmid = musicInfo.songmid || musicInfo.id;
      if (!songmid) {
        throw new Error('Missing songmid for TX hot comments');
      }
      
      // QQ音乐热门评论API URL
      const url = `https://c.y.qq.com/base/fcgi-bin/fcg_global_comment_h5.fcg?g_tk=5381&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0&cid=205360772&reqtype=2&biztype=1&topid=${songmid}&cmd=8&needmusiccrit=0&pagenum=0&pagesize=${limit}&lasthotcommentid=&domain=qq.com&ct=24&cv=10101010&hot=1`;
      
      // 发送HTTP请求
      const txResponse: CommentJsonObject = await commentHttpRequest(url);
      if (Number(txResponse['code']) !== 0) {
        throw new Error(`TX hot API error: ${txResponse['code']}`);
      }
      
      const hotRoot = txResponse['hot_comment'] as CommentJsonObject | undefined;
      let hotList: Object[] = [];
      if (hotRoot !== undefined && hotRoot !== null) {
        const cl = hotRoot['commentlist'];
        if (Array.isArray(cl)) {
          hotList = cl as Object[];
        }
      }
      const comments = filterComments(hotList);
      const total = hotRoot !== undefined && hotRoot !== null
        ? Number(hotRoot['commenttotal'] ?? comments.length)
        : comments.length;
      const maxPage = 1; // 热门评论通常只有一页
      
      return {
        source: 'tx',
        comments,
        total,
        page: 1,
        limit,
        maxPage
      };
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get TX hot comments: %{public}s', JSON.stringify(err));
      throw new Error(`Failed to get TX hot comments: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  function filterComments(txComments: Object[]): Comment[] {
    const out: Comment[] = [];
    for (let i = 0; i < txComments.length; i++) {
      const comment = txComments[i] as CommentJsonObject;
      // QQ 音乐的楼层回复：SubComments（旧版 middlecommentcontent 已并入正文）
      const replies: Comment[] = [];
      const subComments = comment['SubComments'];
      if (Array.isArray(subComments)) {
        for (let j = 0; j < subComments.length; j++) {
          const sub = subComments[j] as CommentJsonObject;
          const rawNick = String(sub['replynick'] ?? '');
          replies.push(buildCommentReply(
            String(sub['subcommentid'] ?? `tx_reply_${j}`),
            String(sub['replycontent'] ?? ''),
            rawNick.startsWith('@') ? rawNick.substring(1) : (rawNick.length > 0 ? rawNick : '匿名用户'),
            String(sub['avatarurl'] ?? ''),
            formatCommentTime(asCommentTimeInput(sub['time'] ?? sub['pubtime'])),
            parseInt(String(sub['praisenum'] ?? '0')) || 0,
            'tx',
            extractCommentImages(sub['Pic'])
          ));
        }
      }
      const commentObj: Comment = {
        id: String(comment['commentid'] ?? `tx_${Date.now()}_${Math.random()}`),
        content: String(comment['rootcommentcontent'] ?? comment['content'] ?? ''),
        userName: String(comment['nick'] ?? '匿名用户'),
        userAvatar: String(comment['avatarurl'] ?? ''),
        time: formatCommentTime(asCommentTimeInput(comment['time'] ?? comment['pubtime'])),
        likeCount: parseInt(String(comment['praisenum'] ?? '0')) || 0,
        replyCount: parseInt(String(comment['replynum'] ?? '0')) || 0,
        isLiked: false,
        isHot: comment['ismanlike'] === 1 || comment['is_hot'] === 1,
        source: 'tx',
        images: extractCommentImages(comment['Pic']),
        location: String(comment['Location'] ?? ''),
        replies
      };
      out.push(commentObj);
    }
    return out;
  }

/** 适配器：CommentService 通过它分发（新增平台只需再写一个这样的文件） */
export const txCommentSource: CommentSourceAdapter = {
  fetch: fetchComments,
  fetchHot: fetchHotComments,
};
