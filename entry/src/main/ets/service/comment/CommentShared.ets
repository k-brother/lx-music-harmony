/**
 * 评论模块共享工具
 *
 * 各源适配器共用的 HTTP 请求、时间格式化、图片/归属地提取等。
 * 从 CommentService 抽出，供 sources/* 复用。
 */
import { appLog as hilog } from '../../core/log/AppLogger';
import { http } from '@kit.NetworkKit';
import type { Comment, CommentJsonObject } from './CommentTypes';

const DOMAIN: number = 0x0001;
const TAG: string = 'CommentShared';

  export async function commentHttpRequest(url: string): Promise<CommentJsonObject> {
    const httpReq: http.HttpRequest = http.createHttp();
    try {
      const requestOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: {
          'User-Agent': 'Dalvik/2.1.0 (Linux; U; Android 9;)',
          'Referer': 'https://y.qq.com/',
          'Origin': 'https://y.qq.com'
        },
        connectTimeout: 10000,
        readTimeout: 10000
      };

      const response = await httpReq.request(url, requestOptions);

      if (response.responseCode === 200) {
        const resultStr: string = response.result as string;
        const parsedResult: CommentJsonObject = JSON.parse(resultStr) as CommentJsonObject;
        return parsedResult;
      } else {
        throw new Error(`HTTP error: ${response.responseCode}`);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'HTTP request failed: %{public}s', JSON.stringify(err));
      throw new Error(`HTTP request failed: ${err instanceof Error ? err.message : String(err)}`);
    } finally {
      httpReq.destroy();
    }
  }

  export function buildCommentReply(
    id: string,
    content: string,
    userName: string,
    avatar: string,
    time: string,
    likeCount: number,
    source: string,
    images: string[]
  ): Comment {
    return {
      id,
      content,
      userName,
      userAvatar: avatar,
      time,
      likeCount,
      replyCount: 0,
      isLiked: false,
      isHot: false,
      source,
      images,
      location: '',
      replies: [],
    };
  }

  export function extractCommentImages(value: Object | undefined | null): string[] {
    if (value === undefined || value === null) {
      return [];
    }
    if (typeof value === 'string') {
      return value.length > 0 ? [value] : [];
    }
    if (Array.isArray(value)) {
      const list: Object[] = value as Object[];
      const result: string[] = [];
      for (let i = 0; i < list.length; i++) {
        const item: Object = list[i];
        if (typeof item === 'string' && item.length > 0) {
          result.push(item as string);
        } else if (item !== null && typeof item === 'object') {
          const url = (item as CommentJsonObject)['url'];
          if (typeof url === 'string' && url.length > 0) {
            result.push(url);
          }
        }
      }
      return result;
    }
    return [];
  }

  export function extractCommentIpLocation(value: Object | undefined | null): string {
    if (value === undefined || value === null || typeof value !== 'object') {
      return '';
    }
    const location = (value as CommentJsonObject)['location'];
    return typeof location === 'string' ? location : '';
  }

  export function asCommentTimeInput(v: Object | undefined | null): string | number | undefined {
    if (v === undefined || v === null) {
      return undefined;
    }
    if (typeof v === 'string' || typeof v === 'number') {
      return v;
    }
    return undefined;
  }

  export function formatCommentTime(timestamp: string | number | undefined): string {
    try {
      if (timestamp === undefined) {
        return '未知时间';
      }
      const timeNum = typeof timestamp === 'string' ? parseInt(timestamp) : timestamp;
      const date = new Date(timeNum * 1000);
      
      const now = new Date();
      const diffMs = now.getTime() - date.getTime();
      const diffMins = Math.floor(diffMs / 60000);
      const diffHours = Math.floor(diffMs / 3600000);
      const diffDays = Math.floor(diffMs / 86400000);
      
      if (diffMins < 1) {
        return '刚刚';
      } else if (diffMins < 60) {
        return `${diffMins}分钟前`;
      } else if (diffHours < 24) {
        return `${diffHours}小时前`;
      } else if (diffDays < 30) {
        return `${diffDays}天前`;
      } else {
        return date.toLocaleDateString();
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'formatCommentTime failed: %{public}s', (e as Error)?.message);
      return '未知时间';
    }
  }
