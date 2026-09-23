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
import { SkeletonCommentItem } from '../components/common/SkeletonView';
import { RefreshContainer } from '../components/ui/RefreshContainer';
import { hapticService } from '../service/HapticService';
import { StateView } from '../components/ui/StateView';
import { SegmentedBar } from '../components/ui/SegmentedBar';
import { PlayerBar } from '../components/player/PlayerBar';
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
  /** 图片预览：整组图片 + 当前下标（支持左右滑动切换，与主流评论区一致） */
  @State previewImages: string[] = [];
  @State previewIndex: number = 0;

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

    if (!this.beginLoad(isRefresh)) {
      return;
    }

    try {
      const response: CommentResponse = await this.fetchCommentsByType(this.currentPage);
      this.applyLoadedComments(response, isRefresh);
    } catch (err) {
      const errorMsg: string = JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to load comments: %{public}s', errorMsg);
      // 失败也要收回加载态，否则下拉刷新一直转、上拉加载再也不触发
      this.endLoad(isRefresh);
    }
  }

  /**
   * 开始一次加载。
   * 下拉刷新：回到第一页并重置「还有更多」；上拉加载：没有更多或正在加载时不重复发请求。
   * 返回 false 表示这次调用不需要发请求。
   */
  private beginLoad(isRefresh: boolean): boolean {
    if (isRefresh) {
      this.isRefreshing = true;
      this.currentPage = 1;
      this.hasMore = true;
      return true;
    }
    if (!this.hasMore || this.isLoading) {
      return false;
    }
    this.isLoading = true;
    return true;
  }

  /** 按当前「热门 / 最新」向对应接口取评论 */
  private async fetchCommentsByType(page: number): Promise<CommentResponse> {
    const info = this.musicInfo as MusicInfo;
    if (this.commentType === 'hot') {
      const hotResult = await commentService.getHotComments(info, page, 20);
      return hotResult as CommentResponse;
    }
    const commentResult = await commentService.getComments(info, page, 20);
    return commentResult as CommentResponse;
  }

  /** 应用结果：刷新是替换、加载更多是追加；两种情况都要把加载态收回 */
  private applyLoadedComments(response: CommentResponse, isRefresh: boolean): void {
    const newComments = response.comments;
    this.comments = isRefresh ? newComments : [...this.comments, ...newComments];
    this.commentSource.reload(this.comments);
    this.currentPage++;
    this.hasMore = this.currentPage <= response.maxPage;
    this.totalComments = response.total;
    this.endLoad(isRefresh);
    hilog.info(DOMAIN, TAG, 'Comments loaded: %{public}d, total: %{public}d, hasMore: %{public}s',
      newComments.length, response.total, this.hasMore.toString());
  }

  /** 收回加载态（成功与失败共用一条路，状态不会漏置） */
  private endLoad(isRefresh: boolean): void {
    if (isRefresh) {
      this.isRefreshing = false;
    } else {
      this.isLoading = false;
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
      
      // 单行变化用 notifyChanged：LazyForEach 只重建这一项
      // （reload 会走整表 diff，用在这里没必要）
      this.commentSource.notifyChanged(commentIndex);
      
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

  /** 全屏图片预览：支持多图左右滑动、点击任意处关闭（遮罩用纯黑，仅预览场景） */
  @Builder
  buildImagePreview() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)
        .onClick(() => {
          this.closeImagePreview();
        })

      Swiper() {
        ForEach(this.previewImages, (url: string, index: number) => {
          Image(url)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            // 点图即关闭（读屏也要能知道这个动作）
            .accessibilityText(t('a11y_close'))
            .onClick(() => {
              this.closeImagePreview();
            })
        }, (url: string, index: number) => `${url}_${index}`)
      }
      .index(this.previewIndex)
      .loop(false)
      .indicator(this.previewImages.length > 1)
      .width('100%')
      .height('100%')

      // 多图时右上角显示「当前 / 总数」，并保留关闭按钮
      Column({ space: 8 }) {
        if (this.previewImages.length > 1) {
          Text(`${this.previewIndex + 1} / ${this.previewImages.length}`)
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.onAccent())
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(DesignTokens.translucentOnImage())
            .borderRadius(16)
        }
        Text(t('comment_image_close'))
          .fontSize(DesignTokens.fontBody())
          .fontColor(DesignTokens.onAccent())
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor(DesignTokens.translucentOnImage())
          .borderRadius(18)
          .accessibilityText(t('a11y_close'))
          .onClick(() => {
            this.closeImagePreview();
          })
      }
      .align(Alignment.TopEnd)
      .margin({ top: 60, right: 20 })
    }
    .width('100%')
    .height('100%')
  }

  /** 关闭图片预览 */
  private closeImagePreview(): void {
    this.previewImages = [];
    this.previewIndex = 0;
  }

  /** 加载更多评论时的骨架（占位 3 行，避免转圈） */
  @Builder
  buildLoadingState() {
    Column() {
      ForEach([0, 1, 2], (index: number) => {
        SkeletonCommentItem()
      }, (index: number) => `comment_skeleton_${index}`)
    }
    .width('100%')
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

  build() {
    Stack() {
      Column() {
        // 头部
        this.buildHeader()

        // 评论类型标签
        this.buildCommentTypeTabs()

        if (this.comments.length > 0) {
          // 下拉刷新：重新拉第一页（onRefresh/isRefreshing 此前定义了却没有入口）
          // 自定义组件后面不能直接挂 layoutWeight，用一层 Column 承担剩余高度
          Column() {
            RefreshContainer({
              refreshing: $isRefreshing,
              onRefresh: (): void => {
                hapticService.selection();
                this.onRefresh();
              },
            }) {
              this.CommentList()
            }
          }
          .layoutWeight(1)
          .width('100%')
        } else if (this.isLoading || this.isRefreshing) {
          this.buildLoadingState()
        } else {
          this.buildEmptyState()
        }

        // 迷你播放条：看评论时也能看见当前播放并一键回播放页（与首页/本地音乐一致）
        PlayerBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(DesignTokens.pageBg(this.theme))

      // 全屏图片预览
      if (this.previewImages.length > 0) {
        this.buildImagePreview()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }

  /** 评论列表（分页 + 大屏内容列居中） */
  @Builder
  CommentList() {
          // 用 List + onReachEnd 做分页：滑到底自动加载下一页
          List() {
            LazyForEach(this.commentSource, (comment: Comment, index: number) => {
              ListItem() {
                CommentRow({
                  comment: comment,
                  isLast: index >= this.comments.length - 1,
                  onToggleLike: (commentId: string): void => this.toggleLikeComment(commentId),
                  onPreviewImages: (urls: string[], index: number): void => {
                    this.previewImages = urls;
                    this.previewIndex = Math.max(0, Math.min(index, urls.length - 1));
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
                  .fontSize(DesignTokens.fontCaption())
                  .fontColor(DesignTokens.labelSecondary(this.theme))
                  .textAlign(TextAlign.Center)
                  .width('100%')
                  .padding({ top: 20, bottom: 20 })
              }
            }
          }
          .layoutWeight(1)
          .width('100%')
          // 预建可视区外的若干行，滚动更顺（LazyForEach 配套）
          .cachedCount(6)
          .scrollBar(BarState.Off)
          // 大屏内容列居中：评论正文在 PC 上不该横跨整屏
          .padding({
            left: Breakpoints.contentInset(this.windowWidthVp),
            right: Breakpoints.contentInset(this.windowWidthVp),
          })
          .onReachEnd(() => {
            this.onLoadMore();
          })
  }
}
