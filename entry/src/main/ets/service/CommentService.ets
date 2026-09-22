/**
 * 评论服务（分发层）
 *
 * 各平台的接口差异与字段映射在 service/comment/sources/*，
 * 这里只做「按音源分发 + 统一错误包装 + 单例出口」，
 * 页面继续用 commentService.getComments / getHotComments。
 */
// 日志经由应用日志门面，既输出 hilog 也进入「设置 → 运行日志」
import { appLog as hilog } from '../core/log/AppLogger';
import { MusicInfo } from '../types/MusicTypes';
import type { Comment, CommentResponse } from './comment/CommentTypes';
import type { CommentSourceAdapter } from './comment/CommentSourceAdapter';
import { kwCommentSource } from './comment/sources/KwCommentSource';
import { txCommentSource } from './comment/sources/TxCommentSource';
import { wyCommentSource } from './comment/sources/WyCommentSource';
import { kgCommentSource } from './comment/sources/KgCommentSource';
import { mgCommentSource } from './comment/sources/MgCommentSource';

const DOMAIN: number = 0x0001;
const TAG: string = 'CommentService';

// 评论数据结构对外仍从本模块导出，避免调用方改 import 路径
export type { Comment, CommentResponse } from './comment/CommentTypes';

/** 评论服务类 */
export class CommentService {
  private static instance: CommentService;

  private constructor() {}

  // 单例获取
  static getInstance(): CommentService {
    if (!CommentService.instance) {
      CommentService.instance = new CommentService();
    }
    return CommentService.instance;
  }

  /** 按音源取适配器；不支持的源返回 undefined */
  private resolveAdapter(source: string): CommentSourceAdapter | undefined {
    switch (source) {
      case 'kw':
        return kwCommentSource;
      case 'tx':
        return txCommentSource;
      case 'wy':
        return wyCommentSource;
      case 'kg':
        return kgCommentSource;
      case 'mg':
        return mgCommentSource;
      default:
        return undefined;
    }
  }

  private async fetch(
    musicInfo: MusicInfo, page: number, limit: number, hot: boolean
  ): Promise<CommentResponse> {
    const kind = hot ? 'hot comments' : 'comments';
    hilog.info(DOMAIN, TAG, 'Getting %{public}s for: %{public}s, page: %{public}d',
      kind, musicInfo.name, page);
    const adapter = this.resolveAdapter(musicInfo.source as string);
    if (!adapter) {
      throw new Error(`Unsupported music source: ${musicInfo.source}`);
    }
    try {
      return hot
        ? await adapter.fetchHot(musicInfo, page, limit)
        : await adapter.fetch(musicInfo, page, limit);
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      hilog.error(DOMAIN, TAG, 'Failed to get %{public}s: %{public}s', kind, message);
      throw new Error(`Failed to get ${kind}: ${message}`);
    }
  }

  // 获取评论
  async getComments(musicInfo: MusicInfo, page: number = 1, limit: number = 20): Promise<CommentResponse> {
    return this.fetch(musicInfo, page, limit, false);
  }

  // 获取热门评论
  async getHotComments(musicInfo: MusicInfo, page: number = 1, limit: number = 100): Promise<CommentResponse> {
    return this.fetch(musicInfo, page, limit, true);
  }
}

// 导出单例
export const commentService = CommentService.getInstance();
