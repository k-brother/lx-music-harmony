// 评论服务
// 对应安卓版的评论功能

import hilog from '@ohos.hilog';
import { http } from '@kit.NetworkKit';
import { MusicInfo } from '../types/MusicTypes';

const DOMAIN: number = 0x0001;
const TAG: string = 'CommentService';

type JsonObject = Record<string, Object>;

// 评论类型
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
}

// 评论响应
export interface CommentResponse {
  source: string;
  comments: Comment[];
  total: number;
  page: number;
  limit: number;
  maxPage: number;
}

// 酷我评论API响应
interface KwCommentApiResponse {
  code: string;
  comments_counts?: number;
  hot_comments_counts?: number;
  comments?: KwCommentItem[];
  hot_comments?: KwCommentItem[];
}

// 酷我评论项
interface KwCommentItem {
  cid?: string;
  msg?: string;
  u_name?: string;
  u_pic?: string;
  time?: string | number;
  like_num?: string;
  reply_num?: string;
  is_hot?: string;
}

// 评论服务类
export class CommentService {
  private static instance: CommentService;

  private constructor() {}

  private parseKwCommentResponse(raw: JsonObject): KwCommentApiResponse {
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

  // 单例获取
  static getInstance(): CommentService {
    if (!CommentService.instance) {
      CommentService.instance = new CommentService();
    }
    return CommentService.instance;
  }

  // 获取评论
  async getComments(musicInfo: MusicInfo, page: number = 1, limit: number = 20): Promise<CommentResponse> {
    try {
      hilog.info(DOMAIN, TAG, 'Getting comments for: %{public}s, page: %{public}d', musicInfo.name, page);
      
      // 根据音乐源调用不同的API
      switch (musicInfo.source) {
        case 'kw':
          return await this.getKwComments(musicInfo, page, limit);
        case 'tx':
          return await this.getTxComments(musicInfo, page, limit);
        case 'wy':
          return await this.getWyComments(musicInfo, page, limit);
        case 'kg':
          return await this.getKgComments(musicInfo, page, limit);
        case 'mg':
          return await this.getMgComments(musicInfo, page, limit);
        default:
          throw new Error(`Unsupported music source: ${musicInfo.source}`);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get comments: %{public}s', JSON.stringify(err));
      throw new Error(`Failed to get comments: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  // 获取热门评论
  async getHotComments(musicInfo: MusicInfo, page: number = 1, limit: number = 100): Promise<CommentResponse> {
    try {
      hilog.info(DOMAIN, TAG, 'Getting hot comments for: %{public}s, page: %{public}d', musicInfo.name, page);
      
      // 根据音乐源调用不同的API
      switch (musicInfo.source) {
        case 'kw':
          return await this.getKwHotComments(musicInfo, page, limit);
        case 'tx':
          return await this.getTxHotComments(musicInfo, page, limit);
        case 'wy':
          return await this.getWyHotComments(musicInfo, page, limit);
        case 'kg':
          return await this.getKgHotComments(musicInfo, page, limit);
        case 'mg':
          return await this.getMgHotComments(musicInfo, page, limit);
        default:
          throw new Error(`Unsupported music source: ${musicInfo.source}`);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to get hot comments: %{public}s', JSON.stringify(err));
      throw new Error(`Failed to get hot comments: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  // 获取酷我评论
  private async getKwComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
    try {
      const songmid = musicInfo.songmid;
      if (!songmid) {
        throw new Error('Songmid is required for KW comments');
      }

      const start = limit * (page - 1);
      const url = `http://ncomment.kuwo.cn/com.s?f=web&type=get_comment&aapiver=1&prod=kwplayer_ar_10.5.2.0&digest=15&sid=${songmid}&start=${start}&msgflag=1&count=${limit}&newver=3&uid=0`;
      
      const response: KwCommentApiResponse = this.parseKwCommentResponse(await this.httpRequest(url));
      
      if (response.code !== '200') {
        throw new Error(`KW API error: ${response.code}`);
      }

      const total = response.comments_counts || 0;
      const comments = this.filterKwComments(response.comments || []);
      
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

  // 获取酷我热门评论
  private async getKwHotComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
    try {
      const songmid = musicInfo.songmid;
      if (!songmid) {
        throw new Error('Songmid is required for KW hot comments');
      }

      const start = limit * (page - 1);
      const url = `http://ncomment.kuwo.cn/com.s?f=web&type=get_rec_comment&aapiver=1&prod=kwplayer_ar_10.5.2.0&digest=15&sid=${songmid}&start=${start}&msgflag=1&count=${limit}&newver=3&uid=0`;
      
      const response: KwCommentApiResponse = this.parseKwCommentResponse(await this.httpRequest(url));
      
      if (response.code !== '200') {
        throw new Error(`KW hot API error: ${response.code}`);
      }

      const total = response.hot_comments_counts || 0;
      const comments = this.filterKwComments(response.hot_comments || []);
      
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

  // 获取QQ音乐评论
  private async getTxComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
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
      const txResponse: JsonObject = await this.httpRequest(url);
      if (Number(txResponse['code']) !== 0) {
        throw new Error(`TX API error: ${txResponse['code']}`);
      }
      
      const commentRoot = txResponse['comment'] as JsonObject | undefined;
      let txList: Object[] = [];
      if (commentRoot !== undefined && commentRoot !== null) {
        const cl = commentRoot['commentlist'];
        if (Array.isArray(cl)) {
          txList = cl as Object[];
        }
      }
      const comments = this.filterTxComments(txList);
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

  // 获取QQ音乐热门评论
  private async getTxHotComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
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
      const txResponse: JsonObject = await this.httpRequest(url);
      if (Number(txResponse['code']) !== 0) {
        throw new Error(`TX hot API error: ${txResponse['code']}`);
      }
      
      const hotRoot = txResponse['hot_comment'] as JsonObject | undefined;
      let hotList: Object[] = [];
      if (hotRoot !== undefined && hotRoot !== null) {
        const cl = hotRoot['commentlist'];
        if (Array.isArray(cl)) {
          hotList = cl as Object[];
        }
      }
      const comments = this.filterTxComments(hotList);
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

  // 过滤QQ音乐评论
  private filterTxComments(txComments: Object[]): Comment[] {
    const out: Comment[] = [];
    for (let i = 0; i < txComments.length; i++) {
      const comment = txComments[i] as JsonObject;
      const commentObj: Comment = {
        id: String(comment['commentid'] ?? `tx_${Date.now()}_${Math.random()}`),
        content: String(comment['rootcommentcontent'] ?? comment['content'] ?? ''),
        userName: String(comment['nick'] ?? '匿名用户'),
        userAvatar: String(comment['avatarurl'] ?? ''),
        time: this.formatTime(this.asTimeInput(comment['time'] ?? comment['pubtime'])),
        likeCount: parseInt(String(comment['praisenum'] ?? '0')) || 0,
        replyCount: parseInt(String(comment['replynum'] ?? '0')) || 0,
        isLiked: false,
        isHot: comment['ismanlike'] === 1 || comment['is_hot'] === 1,
        source: 'tx'
      };
      out.push(commentObj);
    }
    return out;
  }

  // 获取网易云音乐评论
  private async getWyComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
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
      const wyResponse: JsonObject = await this.httpRequest(url);
      if (Number(wyResponse['code']) !== 200) {
        throw new Error(`WY API error: ${wyResponse['code']}`);
      }
      
      let wyList: Object[] = [];
      const wc = wyResponse['comments'];
      if (Array.isArray(wc)) {
        wyList = wc as Object[];
      }
      const comments = this.filterWyComments(wyList);
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

  // 获取网易云音乐热门评论
  private async getWyHotComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
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
      const wyResponse: JsonObject = await this.httpRequest(url);
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
      const comments = this.filterWyComments(hotWy);
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

  // 过滤网易云音乐评论
  private filterWyComments(wyComments: Object[]): Comment[] {
    const out: Comment[] = [];
    for (let i = 0; i < wyComments.length; i++) {
      const comment = wyComments[i] as JsonObject;
      const user = comment['user'] as JsonObject | undefined;
      const nick = user !== undefined && user !== null ? user['nickname'] : undefined;
      const commentObj: Comment = {
        id: String(comment['commentId'] ?? `wy_${Date.now()}_${Math.random()}`),
        content: String(comment['content'] ?? ''),
        userName: nick !== undefined && nick !== null ? String(nick) : '匿名用户',
        userAvatar: user !== undefined && user !== null ? String(user['avatarUrl'] ?? '') : '',
        time: this.formatTime(this.asTimeInput(comment['time'])),
        likeCount: Number(comment['likedCount'] ?? 0),
        replyCount: Number(comment['replyCount'] ?? 0),
        isLiked: Boolean(comment['liked']),
        isHot: Boolean(comment['hot']),
        source: 'wy'
      };
      out.push(commentObj);
    }
    return out;
  }

  // 获取酷狗音乐评论
  private async getKgComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
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
      const kgResponse: JsonObject = await this.httpRequest(url);
      if (Number(kgResponse['status']) !== 1) {
        throw new Error(`KG API error: ${kgResponse['status']}`);
      }
      
      const dataObj = kgResponse['data'] as JsonObject | undefined;
      let kgList: Object[] = [];
      if (dataObj !== undefined && dataObj !== null) {
        const lst = dataObj['list'];
        if (Array.isArray(lst)) {
          kgList = lst as Object[];
        }
      }
      const comments = this.filterKgComments(kgList);
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

  // 获取酷狗音乐热门评论
  private async getKgHotComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
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
      const kgResponse: JsonObject = await this.httpRequest(url);
      if (Number(kgResponse['status']) !== 1) {
        throw new Error(`KG hot API error: ${kgResponse['status']}`);
      }
      
      const dataObj = kgResponse['data'] as JsonObject | undefined;
      let kgHotList: Object[] = [];
      if (dataObj !== undefined && dataObj !== null) {
        const lst = dataObj['list'];
        if (Array.isArray(lst)) {
          kgHotList = lst as Object[];
        }
      }
      const comments = this.filterKgComments(kgHotList);
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

  // 过滤酷狗音乐评论
  private filterKgComments(kgComments: Object[]): Comment[] {
    const out: Comment[] = [];
    for (let i = 0; i < kgComments.length; i++) {
      const comment = kgComments[i] as JsonObject;
      const commentObj: Comment = {
        id: String(comment['commentid'] ?? `kg_${Date.now()}_${Math.random()}`),
        content: String(comment['content'] ?? ''),
        userName: String(comment['nickname'] ?? '匿名用户'),
        userAvatar: String(comment['userpic'] ?? ''),
        time: this.formatTime(this.asTimeInput(comment['addtime'])),
        likeCount: Number(comment['like_num'] ?? 0),
        replyCount: Number(comment['reply_num'] ?? 0),
        isLiked: comment['is_like'] === 1,
        isHot: comment['is_hot'] === 1,
        source: 'kg'
      };
      out.push(commentObj);
    }
    return out;
  }

  // 获取咪咕音乐评论
  private async getMgComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
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
      const mgResponse: JsonObject = await this.httpRequest(url);
      if (String(mgResponse['code']) !== '000000') {
        throw new Error(`MG API error: ${mgResponse['code']}`);
      }
      
      const mgData = mgResponse['data'] as JsonObject | undefined;
      let mgList: Object[] = [];
      if (mgData !== undefined && mgData !== null) {
        const lst = mgData['list'];
        if (Array.isArray(lst)) {
          mgList = lst as Object[];
        }
      }
      const comments = this.filterMgComments(mgList);
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

  // 获取咪咕音乐热门评论
  private async getMgHotComments(musicInfo: MusicInfo, page: number, limit: number): Promise<CommentResponse> {
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
      const mgResponse: JsonObject = await this.httpRequest(url);
      if (String(mgResponse['code']) !== '000000') {
        throw new Error(`MG hot API error: ${mgResponse['code']}`);
      }
      
      const mgData = mgResponse['data'] as JsonObject | undefined;
      let mgHotList: Object[] = [];
      if (mgData !== undefined && mgData !== null) {
        const lst = mgData['list'];
        if (Array.isArray(lst)) {
          mgHotList = lst as Object[];
        }
      }
      const comments = this.filterMgComments(mgHotList);
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

  // 过滤咪咕音乐评论
  private filterMgComments(mgComments: Object[]): Comment[] {
    const out: Comment[] = [];
    for (let i = 0; i < mgComments.length; i++) {
      const comment = mgComments[i] as JsonObject;
      const user = comment['user'] as JsonObject | undefined;
      const nick = user !== undefined && user !== null ? user['nickName'] : undefined;
      const commentObj: Comment = {
        id: String(comment['commentId'] ?? `mg_${Date.now()}_${Math.random()}`),
        content: String(comment['content'] ?? ''),
        userName: nick !== undefined && nick !== null ? String(nick) : '匿名用户',
        userAvatar: user !== undefined && user !== null ? String(user['headUrl'] ?? '') : '',
        time: this.formatTime(this.asTimeInput(comment['createTime'])),
        likeCount: Number(comment['likeCount'] ?? 0),
        replyCount: Number(comment['replyCount'] ?? 0),
        isLiked: Boolean(comment['isLiked']),
        isHot: Boolean(comment['isHot']),
        source: 'mg'
      };
      out.push(commentObj);
    }
    return out;
  }

  // HTTP请求
  private async httpRequest(url: string): Promise<JsonObject> {
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
        const parsedResult: JsonObject = JSON.parse(resultStr) as JsonObject;
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

  // 过滤酷我评论
  private filterKwComments(kwComments: KwCommentItem[]): Comment[] {
    return kwComments.map((comment: KwCommentItem) => {
      // 解析时间戳 - 确保类型安全
      const time = this.formatTime(comment.time ?? undefined);
      
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
        source: 'kw'
      };
      return commentObj;
    });
  }

  private asTimeInput(v: Object | undefined | null): string | number | undefined {
    if (v === undefined || v === null) {
      return undefined;
    }
    if (typeof v === 'string' || typeof v === 'number') {
      return v;
    }
    return undefined;
  }

  // 格式化时间
  private formatTime(timestamp: string | number | undefined): string {
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
      hilog.warn(DOMAIN, TAG, 'formatTime failed: %{public}s', (e as Error)?.message);
      return '未知时间';
    }
  }

}

// 导出单例
export const commentService = CommentService.getInstance();