// 评论页面
// 对应安卓版的评论功能

import hilog from '@ohos.hilog';
import { navigationService } from '../service/NavigationService';
import { MusicInfo, MusicSource } from '../types/MusicTypes';
import { commentService } from '../service/CommentService';
import type { NavigationParams } from '../service/NavigationService';
import { DesignTokens } from '../theme/DesignTokens';
import { EmptyView } from '../components/common/EmptyView';
import { NavBackButton } from '../components/common/NavBackButton';
import { t } from '../service/LocalizationService';

const DOMAIN: number = 0x0001;
const TAG: string = 'CommentPage';

// 评论类型
interface Comment {
  id: string;
  content: string;
  userName: string;
  userAvatar: string;
  time: string;
  likeCount: number;
  replyCount: number;
  isLiked: boolean;
  isHot: boolean;
}

// 评论参数
interface CommentParams {
  musicInfo: MusicInfo | null;
  commentType: 'hot' | 'new'; // 热门评论或最新评论
}

// 评论响应类型
interface CommentResponse {
  comments: Comment[];
  maxPage: number;
  total: number;
}

@Component
export struct CommentPage {
  @StorageProp('theme') theme: string = 'light';

  /** 按压反馈：列表行/按钮变淡 */
  @Styles
  pressDim() {
    .opacity(0.65)
  }

  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State renderKey: number = Date.now();
  @State comments: Comment[] = [];
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = true;
  @State currentPage: number = 1;
  @State totalComments: number = 0;
  @State musicInfo: MusicInfo | null = null;
  @State commentType: string = 'hot';

  aboutToAppear() {
    // 获取传递的参数
    const params = this.getParams();
    if (params) {
      this.musicInfo = params.musicInfo;
      this.commentType = params.commentType || 'hot';
      this.loadComments(true);
    }
  }

  private getParams(): CommentParams | null {
    const navParams = navigationService.getCurrentParams() as NavigationParams | null;
    if (!navParams || !navParams.musicName) {
      return null;
    }
    const musicInfo: MusicInfo = {
      id: navParams.musicId ?? '',
      songmid: navParams.musicId ?? '',
      name: navParams.musicName ?? '',
      singer: navParams.musicSinger ?? '',
      source: (navParams.musicSource as MusicSource) ?? 'kw',
      interval: null,
      img: navParams.musicPic ?? null,
      pic: navParams.musicPic ?? undefined,
      lrc: null,
      album: navParams.musicAlbum ?? '',
      albumName: navParams.musicAlbum ?? '',
    };
    const cp: CommentParams = {
      musicInfo,
      commentType: (navParams.commentType === 'new' ? 'new' : 'hot'),
    };
    return cp;
  }

  // 加载评论
  async loadComments(isRefresh: boolean = false): Promise<void> {
    if (!this.musicInfo) {
      hilog.error(DOMAIN, TAG, 'No music info available');
      return;
    }

    if (isRefresh) {
      this.isRefreshing = true;
      this.currentPage = 1;
      this.hasMore = true;
    } else {
      if (!this.hasMore || this.isLoading) {
        return;
      }
      this.isLoading = true;
    }

    try {
      let response: CommentResponse;
      
      if (this.commentType === 'hot') {
        // 获取热门评论
        const hotResult = await commentService.getHotComments(
          this.musicInfo,
          this.currentPage,
          20
        );
        response = hotResult as CommentResponse;
      } else {
        // 获取最新评论
        const commentResult = await commentService.getComments(
          this.musicInfo,
          this.currentPage,
          20
        );
        response = commentResult as CommentResponse;
      }
      
      const newComments = response.comments;
      
      if (isRefresh) {
        this.comments = newComments;
        this.isRefreshing = false;
      } else {
        this.comments = [...this.comments, ...newComments];
        this.isLoading = false;
      }
      
      this.currentPage++;
      this.hasMore = this.currentPage <= response.maxPage;
      this.totalComments = response.total;
      
      hilog.info(DOMAIN, TAG, 'Comments loaded: %{public}d, total: %{public}d, hasMore: %{public}s', 
        newComments.length, response.total, this.hasMore.toString());
    } catch (err) {
      const errorMsg: string = JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to load comments: %{public}s', errorMsg);

      if (isRefresh) {
        this.isRefreshing = false;
      } else {
        this.isLoading = false;
      }
    }
  }

  // 切换评论类型
  switchCommentType(type: string): void {
    if (this.commentType === type) {
      return;
    }
    
    this.commentType = type;
    this.comments = [];
    this.currentPage = 1;
    this.hasMore = true;
    this.loadComments(true);
  }

  // 点赞评论
  toggleLikeComment(commentId: string): void {
    const commentIndex = this.comments.findIndex(c => c.id === commentId);
    if (commentIndex !== -1) {
      const comment = this.comments[commentIndex];
      comment.isLiked = !comment.isLiked;
      comment.likeCount += comment.isLiked ? 1 : -1;
      
      // 更新数组以触发重新渲染
      this.comments = [...this.comments];
      
      hilog.info(DOMAIN, TAG, 'Comment %{public}s liked: %{public}s', commentId, comment.isLiked);
    }
  }

  // 刷新评论
  onRefresh(): void {
    this.loadComments(true);
  }

  // 加载更多评论
  onLoadMore(): void {
    this.loadComments(false);
  }

  @Builder
  buildHeader() {
    Row() {
      NavBackButton()

      Text(t('comment_title'))
        .fontSize(DesignTokens.fontTitle())
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .margin({ left: 12 })
        .layoutWeight(1)

      Blank()
    }
    .width('100%')
    .height(60)
    .padding({ left: 14, right: 14, top: 8, bottom: 6 })
    .backgroundColor(DesignTokens.chromeBar(this.theme))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildCommentTypeTabs() {
    Row() {
      // 热门评论标签
      Text(t('comment_hot'))
        .fontSize(14)
        .fontColor(this.commentType === 'hot' ? DesignTokens.accent() : (this.theme === 'dark' ? DesignTokens.labelTertiary(this.theme) : DesignTokens.labelSecondary(this.theme)))
        .fontWeight(this.commentType === 'hot' ? FontWeight.Medium : FontWeight.Normal)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .onClick(() => {
          this.switchCommentType('hot');
        })

      // 最新评论标签
      Text(t('comment_new'))
        .fontSize(14)
        .fontColor(this.commentType === 'new' ? DesignTokens.accent() : (this.theme === 'dark' ? DesignTokens.labelTertiary(this.theme) : DesignTokens.labelSecondary(this.theme)))
        .fontWeight(this.commentType === 'new' ? FontWeight.Medium : FontWeight.Normal)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .onClick(() => {
          this.switchCommentType('new');
        })
    }
    .width('100%')
    .backgroundColor(DesignTokens.card(this.theme))
  }

  @Builder
  buildCommentItem(comment: Comment, index: number) {
    Column() {
      Row() {
        // 用户头像
        if (comment.userAvatar) {
          Image(comment.userAvatar)
            .width(36)
            .height(36)
            .borderRadius(18)
        } else {
          // 默认头像
          Column() {
            Text(comment.userName.substring(0, 1))
              .fontSize(16)
              .fontColor(DesignTokens.onAccent())
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(DesignTokens.accent())
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        
        Column() {
          // 用户信息和时间
          Row() {
            Text(comment.userName)
              .fontSize(14)
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .fontWeight(FontWeight.Medium)
            
            Text(comment.time)
              .fontSize(12)
              .fontColor(DesignTokens.labelSecondary(this.theme))
              .margin({ left: 8 })
          }
          .width('100%')
          .margin({ bottom: 4 })
          
          // 评论内容
          Text(comment.content)
            .fontSize(14)
            .fontColor(this.theme === 'dark' ? DesignTokens.mutedFill(this.theme) : '#444444')
            .lineHeight(20)
            .margin({ bottom: 8 })
          
          // 点赞和回复信息
          Row() {
            // 点赞按钮
            Row() {
              Image(comment.isLiked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                .width(16)
                .height(16)
                .fillColor(comment.isLiked ? DesignTokens.accent() : DesignTokens.labelSecondary(this.theme))
                .margin({ right: 4 })
              
              Text(comment.likeCount.toString())
                .fontSize(12)
                .fontColor(comment.isLiked ? DesignTokens.accent() : DesignTokens.labelSecondary(this.theme))
            }
            .stateStyles({ pressed: this.pressDim })
            .onClick(() => {
              this.toggleLikeComment(comment.id);
            })
            
            // 回复按钮
            Row() {
              Text('💬')
                .fontSize(16)
                .fontColor(DesignTokens.labelSecondary(this.theme))
                .margin({ left: 16, right: 4 })
              
              Text(comment.replyCount > 0 ? comment.replyCount.toString() : t('comment_new'))
                .fontSize(12)
                .fontColor(DesignTokens.labelSecondary(this.theme))
            }
            .margin({ left: 16 })
            
            // 热门标签
            if (comment.isHot) {
              Text('热评')
                .fontSize(10)
                .fontColor(DesignTokens.accent())
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(2)
                .border({ width: 1, color: DesignTokens.accent() })
                .margin({ left: 16 })
            }
          }
          .width('100%')
        }
        .margin({ left: 12 })
        .layoutWeight(1)
      }
      .width('100%')
      .padding({ top: 16, bottom: 16, left: 16, right: 16 })
      
      // 分隔线
      if (index < this.comments.length - 1) {
        Divider()
          .strokeWidth(0.5)
          .color(this.theme === 'dark' ? DesignTokens.mutedFill(this.theme) : '#E8E8E8')
          .margin({ left: 64, right: 16 })
      }
    }
    .width('100%')
    .backgroundColor(DesignTokens.card(this.theme))
  }

  @Builder
  buildEmptyState() {
    Column() {
      EmptyView({ icon: '💬', message: t('comment_no_data') })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildLoadingState(): void {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(DesignTokens.accent())
    }
    .width('100%')
    .height(80)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      // 头部
      this.buildHeader()
      
      // 评论类型标签
      this.buildCommentTypeTabs()
      
      Scroll() {
        Column() {
          if (this.comments.length > 0) {
            // 评论列表
            ForEach(this.comments, (comment: Comment, index: number) => {
              this.buildCommentItem(comment, index)
            })
            
            // 加载更多
            if (this.hasMore) {
              this.buildLoadingState()
            } else if (this.comments.length > 0) {
              Text(t('comment_no_data'))
                .fontSize(12)
                .fontColor(DesignTokens.labelSecondary(this.theme))
                .textAlign(TextAlign.Center)
                .width('100%')
                .padding({ top: 20, bottom: 20 })
            }
          } else if (this.isLoading || this.isRefreshing) {
            // 加载中
            this.buildLoadingState()
          } else {
            // 空状态
            this.buildEmptyState()
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .backgroundColor(DesignTokens.pageBg(this.theme))
      .onScrollFrameBegin((offset: number) => {
        // 下拉刷新
        if (offset > 100 && !this.isRefreshing) {
          this.onRefresh();
        }
        return { offsetRemain: offset };
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }
}
