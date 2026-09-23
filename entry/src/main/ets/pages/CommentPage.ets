// 评论页面
// 对应安卓版的评论功能

import hilog from '@ohos.hilog';
import { navigationService } from '../service/NavigationService';
import { MusicInfo, MusicSource } from '../types/MusicTypes';
import { commentService } from '../service/CommentService';
// 评论数据结构由 CommentService 统一定义（含图片 / 楼层 / IP 归属地），避免两处结构漂移
import type { Comment } from '../service/CommentService';
import type { NavigationParams } from '../service/NavigationService';
import { DesignTokens } from '../theme/DesignTokens';
import { Breakpoints } from '../theme/Breakpoints';
import { LazyDataSource } from '../utils/LazyDataSource';
import { NavBar } from '../components/ui/NavBar';
import { CommentRow } from './Comment/CommentRow';
import { StateView } from '../components/ui/StateView';
import { SegmentedBar } from '../components/ui/SegmentedBar';
import { t } from '../service/LocalizationService';

const DOMAIN: number = 0x0001;
const TAG: string = 'CommentPage';

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
  /** 一多：窗口宽度（vp），大屏内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;

  /** 按压反馈：列表行/按钮变淡 */
  @Styles
  pressDim() {
    .opacity(0.65)
  }

  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State comments: Comment[] = [];
  /** LazyForEach 数据源：长列表只创建可视区的行 */
  private commentSource: LazyDataSource<Comment> = new LazyDataSource<Comment>();
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = true;
  @State currentPage: number = 1;
  @State totalComments: number = 0;
  @State musicInfo: MusicInfo | null = null;
  @State commentType: string = 'hot';
  /** 正在预览的大图（非空时显示全屏预览层） */
  @State previewImage: string = '';

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
        this.commentSource.reload(this.comments);
        this.isRefreshing = false;
      } else {
        this.comments = [...this.comments, ...newComments];
        this.commentSource.reload(this.comments);
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
    this.commentSource.reload(this.comments);
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
      this.commentSource.reload(this.comments);
      
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
    // 统一顶部栏（返回按钮热区、标题字号、沉底背景一处维护）
    NavBar({ title: t('comment_title') })
  }

  @Builder
  buildCommentTypeTabs() {
    // 热门/最新：统一分段控件（与其它页选中态一致）
    Row() {
      SegmentedBar({
        options: [
          { id: 'hot', label: t('comment_hot') },
          { id: 'new', label: t('comment_new') },
        ],
        activeId: this.commentType,
        fillWidth: false,
        fontSize: 14,
        onSelect: (id: string): void => {
          this.switchCommentType(id);
        },
      })
      Blank()
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(DesignTokens.card(this.theme))
    .stateStyles({ pressed: this.pressDim })
  }

  @Builder
  /** 全屏图片预览：点击任意处关闭（遮罩用纯黑，仅图片预览场景） */
  @Builder
  buildImagePreview() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        .onClick(() => {
          this.previewImage = '';
        })

      Image(this.previewImage)
        .width('100%')
        .objectFit(ImageFit.Contain)

      Column() {
        Text(t('comment_image_close'))
          .fontSize(14)
          .fontColor(DesignTokens.onAccent())
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor('rgba(255,255,255,0.20)')
          .borderRadius(18)
      }
      .align(Alignment.TopEnd)
      .margin({ top: 60, right: 20 })
      .onClick(() => {
        this.previewImage = '';
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildEmptyState() {
    Column() {
      StateView({
        state: 'empty',
        iconRes: $r('sys.symbol.music_note_list'),
        message: t('comment_no_data'),
      })
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
    Stack() {
      Column() {
        // 头部
        this.buildHeader()

        // 评论类型标签
        this.buildCommentTypeTabs()

        if (this.comments.length > 0) {
          // 用 List + onReachEnd 做分页：滑到底自动加载下一页
          List() {
            LazyForEach(this.commentSource, (comment: Comment, index: number) => {
              ListItem() {
                CommentRow({
                  comment: comment,
                  isLast: index >= this.comments.length - 1,
                  onToggleLike: (commentId: string): void => this.toggleLikeComment(commentId),
                  onPreviewImage: (url: string): void => {
                    this.previewImage = url;
                  },
                })
              }
            }, (comment: Comment) => comment.id)

            if (this.hasMore) {
              ListItem() {
                this.buildLoadingState()
              }
            } else {
              ListItem() {
                Text(t('comment_no_more'))
                  .fontSize(12)
                  .fontColor(DesignTokens.labelSecondary(this.theme))
                  .textAlign(TextAlign.Center)
                  .width('100%')
                  .padding({ top: 20, bottom: 20 })
              }
            }
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          // 大屏内容列居中：评论正文在 PC 上不该横跨整屏
          .padding({
            left: Breakpoints.contentInset(this.windowWidthVp),
            right: Breakpoints.contentInset(this.windowWidthVp),
          })
          .onReachEnd(() => {
            this.onLoadMore();
          })
        } else if (this.isLoading || this.isRefreshing) {
          this.buildLoadingState()
        } else {
          this.buildEmptyState()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(DesignTokens.pageBg(this.theme))

      // 全屏图片预览
      if (this.previewImage.length > 0) {
        this.buildImagePreview()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }
}
