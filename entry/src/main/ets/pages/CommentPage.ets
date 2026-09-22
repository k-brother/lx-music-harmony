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
import { NavBar } from '../components/ui/NavBar';
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

  /** 按压反馈：列表行/按钮变淡 */
  @Styles
  pressDim() {
    .opacity(0.65)
  }

  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State comments: Comment[] = [];
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
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(comment.time)
              .fontSize(12)
              .fontColor(DesignTokens.labelTertiary(this.theme))
              .margin({ left: 8 })

            // IP 归属地（部分音源返回）
            if (comment.location.length > 0) {
              Text(comment.location)
                .fontSize(11)
                .fontColor(DesignTokens.labelTertiary(this.theme))
                .margin({ left: 8 })
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            } else {
              Blank()
            }
          }
          .width('100%')
          .margin({ bottom: 4 })

          // 评论内容
          Text(comment.content)
            .fontSize(14)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .lineHeight(20)

          // 评论图片：缩略图点击查看大图
          if (comment.images.length > 0) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(comment.images, (url: string) => {
                Image(url)
                  .width(96)
                  .height(96)
                  .borderRadius(8)
                  .objectFit(ImageFit.Cover)
                  .margin({ top: 8, right: 8 })
                  .onClick(() => {
                    this.previewImage = url;
                  })
              }, (url: string) => url)
            }
            .width('100%')
          }

          // 楼层回复：整块浅底，与主评论视觉分层
          if (comment.replies.length > 0) {
            Column() {
              ForEach(comment.replies, (reply: Comment) => {
                this.buildReplyFloor(reply)
              }, (reply: Comment) => reply.id)
            }
            .width('100%')
            .margin({ top: 10 })
            .padding({ left: 10, right: 10, top: 8, bottom: 2 })
            .backgroundColor(DesignTokens.pageBg(this.theme))
            .borderRadius(8)
          }

          // 点赞和回复信息
          Row() {
            // 点赞按钮
            Row() {
              SymbolGlyph(comment.isLiked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                .fontSize(18)
                .fontColor([comment.isLiked ? DesignTokens.accent() : DesignTokens.labelSecondary(this.theme)])
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
              SymbolGlyph($r('sys.symbol.music_note_list'))
                .fontSize(19)
                .fontColor([DesignTokens.labelSecondary(this.theme)])
                .margin({ left: 16, right: 4 })
              
              Text(comment.replyCount > 0 ? comment.replyCount.toString() : t('comment_new'))
                .fontSize(12)
                .fontColor(DesignTokens.labelSecondary(this.theme))
            }
            .margin({ left: 16 })
            
            // 热门标签
            if (comment.isHot) {
              Text(t('comment_hot_tag'))
                .fontSize(10)
                .fontColor(DesignTokens.accent())
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(2)
                .border({ width: 1, color: DesignTokens.accent() })
                .margin({ left: 16 })
            }
          }
          .width('100%')
          .margin({ top: 8 })
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
  buildReplyFloor(reply: Comment) {
    Column() {
      Row() {
        Text(reply.userName)
          .fontSize(13)
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(reply.time)
          .fontSize(11)
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .margin({ left: 8 })
          .layoutWeight(1)
          .maxLines(1)
      }
      .width('100%')

      Text(reply.content)
        .fontSize(13)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .lineHeight(19)
        .width('100%')
        .margin({ top: 2, bottom: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 全屏图片预览：点击任意处关闭 */
  @Builder
  buildImagePreview() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')
        .onClick(() => {
          this.previewImage = '';
        })

      Image(this.previewImage)
        .width('100%')
        .objectFit(ImageFit.Contain)

      Column() {
        Text(t('comment_image_close'))
          .fontSize(14)
          .fontColor('#FFFFFF')
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor('#33FFFFFF')
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
            ForEach(this.comments, (comment: Comment, index: number) => {
              ListItem() {
                this.buildCommentItem(comment, index)
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
