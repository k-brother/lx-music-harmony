/**
 * 评论「点赞」的本地记录
 *
 * 各音乐源的评论接口都没有带登录态的点赞能力（我们也没做登录），所以点赞只能是
 * **本地标记**：这里把用户点过的评论 id 落盘，让状态在刷新、切歌、重启之后依然在，
 * 而不是像以前那样退出去再进来就变回未点赞（看起来像功能坏了）。
 *
 * 计数口径：界面上显示的是「服务端返回的点赞数 + 本地是否点过」，所以刷新后不会越加越多。
 */
import { getStorageService } from '../../core/interfaces/IStorageService';
import { appLog as hilog } from '../../core/log/AppLogger';
import type { Comment } from './CommentTypes';

const DOMAIN: number = 0x0001;
const TAG = 'CommentLike';
const LIKED_KEY = 'comment.likedIds';
/** 最多记住多少条（防止无限增长；超出后丢最早记录） */
const MAX_LIKED = 500;

/** 读取本地点赞集合 */
export async function loadLikedIds(): Promise<Set<string>> {
  try {
    const raw: string = await getStorageService().getString(LIKED_KEY, '');
    if (raw.length === 0) {
      return new Set<string>();
    }
    const ids = JSON.parse(raw) as string[];
    if (!Array.isArray(ids)) {
      return new Set<string>();
    }
    return new Set<string>(ids);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'load liked ids failed: %{public}s', JSON.stringify(err));
    return new Set<string>();
  }
}

/** 记录/取消一条点赞（返回写入后的完整集合，调用方直接拿来用） */
export async function persistLikedIds(ids: Set<string>): Promise<void> {
  try {
    let list: string[] = Array.from(ids);
    if (list.length > MAX_LIKED) {
      list = list.slice(list.length - MAX_LIKED);
    }
    await getStorageService().setString(LIKED_KEY, JSON.stringify(list));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'persist liked ids failed: %{public}s', JSON.stringify(err));
  }
}

/** 把本地点赞状态套用到刚拉回来的评论上（服务端没有 liked 字段，只能本地补） */
export function applyLikedState(comments: Comment[], likedIds: Set<string>): void {
  for (let i = 0; i < comments.length; i++) {
    const comment = comments[i];
    if (likedIds.has(comment.id)) {
      comment.isLiked = true;
      // 服务端的点赞数不含本地这一次，显示时补上（刷新后不会重复累加）
      comment.likeCount += 1;
    }
  }
}
