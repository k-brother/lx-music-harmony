// 评论页面
// 对应安卓版的评论功能

import hilog from '@ohos.hilog';
import { navigationService, RouteName } from '../service/NavigationService';
import { MusicInfo } from '../types/MusicTypes';
import { commentService } from '../service/CommentService';

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
  musicInfo: MusicInfo;
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
    // 这里需要从导航参数中获取音乐信息
    // 实际实现中需要从NavDestinationContext获取
    return null;
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
      
      // 如果API调用失败，使用模拟数据作为降级方案
      if (isRefresh && this.comments.length === 0) {
        await this.loadMockComments(isRefresh);
      }
      
      if (isRefresh) {
        this.isRefreshing = false;
      } else {
        this.isLoading = false;
      }
    }
  }

  // 加载模拟评论（降级方案）
  async loadMockComments(isRefresh: boolean = false): Promise<void> {
    try {
      // 模拟加载延迟
      const delayPromise: Promise<void> = new Promise<void>((resolve: () => void) => setTimeout(resolve, 500));
      await delayPromise;
      
      const newComments = this.generateMockComments(
        isRefresh ? 1 : this.currentPage,
        this.commentType
      );
      
      if (isRefresh) {
        this.comments = newComments;
      } else {
        this.comments = [...this.comments, ...newComments];
      }
      
      this.currentPage++;
      this.hasMore = this.currentPage <= 3;
      this.totalComments = this.comments.length * 3;
      
      hilog.info(DOMAIN, TAG, 'Mock comments loaded: %{public}d', newComments.length);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to load mock comments: %{public}s', JSON.stringify(err));
    }
  }

  // 生成模拟评论数据
  private generateMockComments(page: number, type: string): Comment[] {
    const comments: Comment[] = [];
    const pageSize = 10;
    
    for (let i = 0; i < pageSize; i++) {
      const index = (page - 1) * pageSize + i + 1;
      const isHot = type === 'hot' && i < 3;
      
      comments.push({
        id: `comment_${page}_${i}`,
        content: `这是第${index}条评论内容，这是一段测试评论文字，用于展示评论功能。`,
        userName: `用户${index}`,
        userAvatar: '',
        time: `${index}小时前`,
        likeCount: Math.floor(Math.random() * 1000),
        replyCount: Math.floor(Math.random() * 100),
        isLiked: Math.random() > 0.8,
        isHot
      });
    }
    
    return comments;
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
      Text('评论')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
        .layoutWeight(1)
      
      Text('关闭')
        .fontSize(14)
        .fontColor('#2196F3')
        .onClick(() => {
          navigationService.back();
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildCommentTypeTabs() {
    Row() {
      // 热门评论标签
      Text('热门评论')
        .fontSize(14)
        .fontColor(this.commentType === 'hot' ? '#E63946' : (this.theme === 'dark' ? '#AAAAAA' : '#666666'))
        .fontWeight(this.commentType === 'hot' ? FontWeight.Medium : FontWeight.Normal)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .onClick(() => {
          this.switchCommentType('hot');
        })
      
      // 最新评论标签
      Text('最新评论')
        .fontSize(14)
        .fontColor(this.commentType === 'new' ? '#E63946' : (this.theme === 'dark' ? '#AAAAAA' : '#666666'))
        .fontWeight(this.commentType === 'new' ? FontWeight.Medium : FontWeight.Normal)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .onClick(() => {
          this.switchCommentType('new');
        })
    }
    .width('100%')
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
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
              .fontColor('#FFFFFF')
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor('#E63946')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        
        Column() {
          // 用户信息和时间
          Row() {
            Text(comment.userName)
              .fontSize(14)
              .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
              .fontWeight(FontWeight.Medium)
            
            Text(comment.time)
              .fontSize(12)
              .fontColor('#999999')
              .margin({ left: 8 })
          }
          .width('100%')
          .margin({ bottom: 4 })
          
          // 评论内容
          Text(comment.content)
            .fontSize(14)
            .fontColor(this.theme === 'dark' ? '#E0E0E0' : '#444444')
            .lineHeight(20)
            .margin({ bottom: 8 })
          
          // 点赞和回复信息
          Row() {
            // 点赞按钮
            Row() {
              Image(comment.isLiked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                .width(16)
                .height(16)
                .fillColor(comment.isLiked ? '#E63946' : '#999999')
                .margin({ right: 4 })
              
              Text(comment.likeCount.toString())
                .fontSize(12)
                .fontColor(comment.isLiked ? '#E63946' : '#999999')
            }
            .onClick(() => {
              this.toggleLikeComment(comment.id);
            })
            
            // 回复按钮
            Row() {
              Text('💬')
                .fontSize(16)
                .fontColor('#999999')
                .margin({ left: 16, right: 4 })
              
              Text(comment.replyCount > 0 ? comment.replyCount.toString() : '回复')
                .fontSize(12)
                .fontColor('#999999')
            }
            .margin({ left: 16 })
            
            // 热门标签
            if (comment.isHot) {
              Text('热评')
                .fontSize(10)
                .fontColor('#E63946')
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(2)
                .border({ width: 1, color: '#E63946' })
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
          .color(this.theme === 'dark' ? '#2C2C2C' : '#E8E8E8')
          .margin({ left: 64, right: 16 })
      }
    }
    .width('100%')
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
  }

  @Builder
  buildEmptyState() {
    Column() {
      Text('💬')
        .fontSize(48)
        .fontColor('#CCCCCC')
        .margin({ bottom: 16 })
      
      Text('暂无评论')
        .fontSize(16)
        .fontColor(this.theme === 'dark' ? '#AAAAAA' : '#666666')
        .margin({ bottom: 8 })
      
      Text('快来发表第一条评论吧')
        .fontSize(12)
        .fontColor('#999999')
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
        .color('#E63946')
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
              Text('没有更多评论了')
                .fontSize(12)
                .fontColor('#999999')
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
      .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
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
    .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
  }
}