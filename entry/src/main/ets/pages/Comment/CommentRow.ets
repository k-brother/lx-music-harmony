/**
 * 评论行
 *
 * 从 CommentPage 的 @Builder 抽成组件：头像、昵称/时间、内容、图片、楼层回复、点赞。
 * 用 @Component + @Prop 而不是 @Builder 参数 —— 实测 @Builder 的参数不会随状态刷新，
 * 点赞态与点赞数会停在旧值；@Prop 在父组件重渲染时会更新。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t, tf } from '../../service/LocalizationService';
import type { Comment } from '../../service/comment/CommentTypes';

/** 楼层回复默认展开条数：超出部分折叠为「展开全部 N 条回复」 */
const REPLY_PREVIEW_COUNT: number = 2;

@Component
export struct CommentRow {
  @StorageProp('theme') theme: string = 'light';
  @Prop comment: Comment;
  /** 楼层回复是否已展开（默认只展示前两条） */
  @State expandedReplies: boolean = false;
  /** 最后一行不画分割线 */
  @Prop isLast: boolean = false;
  onToggleLike?: (commentId: string) => void;
  /** 预览图片：回传整条评论的图片与其下标，页面侧可左右滑动切换 */
  onPreviewImages?: (urls: string[], index: number) => void;

  /** 按压反馈：与页面其它列表行一致（变淡） */
  @Styles
  pressed() {
    .opacity(DesignTokens.pressedOpacity())
  }

  /** 折叠态只给前两条，展开后给全部 */
  private visibleReplies(): Comment[] {
    if (this.expandedReplies || this.comment.replies.length <= REPLY_PREVIEW_COUNT) {
      return this.comment.replies;
    }
    return this.comment.replies.slice(0, REPLY_PREVIEW_COUNT);
  }

  @Builder
  ReplyFloor(reply: Comment) {

    Column() {
      Row() {
        Text(reply.userName)
          .fontSize(DesignTokens.fontCallout())
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(reply.time)
          .fontSize(DesignTokens.fontMicro())
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .margin({ left: 8 })
          .layoutWeight(1)
          .maxLines(1)
      }
      .width('100%')

      Text(reply.content)
        .fontSize(DesignTokens.fontCallout())
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .lineHeight(19)
        .width('100%')
        .margin({ top: 2, bottom: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  
  }

  build() {
    Column() {
      Row() {
        // 用户头像
        if (this.comment.userAvatar) {
          Image(this.comment.userAvatar)
            .width(36)
            .height(36)
            .borderRadius(18)
        } else {
          // 默认头像
          Column() {
            Text(this.comment.userName.substring(0, 1))
              .fontSize(DesignTokens.fontTitle())
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
            Text(this.comment.userName)
              .fontSize(DesignTokens.fontBody())
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .fontWeight(FontWeight.Medium)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.comment.time)
              .fontSize(DesignTokens.fontCaption())
              .fontColor(DesignTokens.labelTertiary(this.theme))
              .margin({ left: 8 })

            // IP 归属地（部分音源返回）
            if (this.comment.location.length > 0) {
              Text(this.comment.location)
                .fontSize(DesignTokens.fontMicro())
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
          Text(this.comment.content)
            .fontSize(DesignTokens.fontBody())
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .lineHeight(20)

          // 评论图片：缩略图点击查看大图
          if (this.comment.images.length > 0) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.comment.images, (url: string, imageIndex: number) => {
                Image(url)
                  .width(96)
                  .height(96)
                  .borderRadius(8)
                  .objectFit(ImageFit.Cover)
                  .margin({ top: 8, right: 8 })
                  .accessibilityText(t('a11y_expand'))
                  // 2in1（PC/平板接鼠标）下的悬停反馈
                  .hoverEffect(HoverEffect.Highlight)
                  .onClick(() => {
                    if (this.onPreviewImages) {
                      this.onPreviewImages(this.comment.images, imageIndex);
                    }
                  })
              }, (url: string) => url)
            }
            .width('100%')
          }

          // 楼层回复：整块浅底，与主评论视觉分层
          if (this.comment.replies.length > 0) {
            Column() {
              // 主流评论区的做法：默认只展开前两条，其余折叠成「展开全部 N 条回复」
              ForEach(this.visibleReplies(), (reply: Comment) => {
                this.ReplyFloor(reply)
              }, (reply: Comment) => reply.id)

              if (this.comment.replies.length > REPLY_PREVIEW_COUNT) {
                Text(this.expandedReplies
                  ? t('comment_collapse_replies')
                  : tf('comment_expand_replies', [(this.comment.replies.length - REPLY_PREVIEW_COUNT).toString()]))
                  .fontSize(DesignTokens.fontCaption())
                  .fontColor(DesignTokens.accent())
                  .width('100%')
                  .textAlign(TextAlign.Start)
                  .padding({ top: 2, bottom: 8 })
                  .accessibilityText(this.expandedReplies
                    ? t('comment_collapse_replies')
                    : tf('comment_expand_replies', [(this.comment.replies.length - REPLY_PREVIEW_COUNT).toString()]))
                  .onClick(() => {
                    this.expandedReplies = !this.expandedReplies;
                  })
              }
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
              SymbolGlyph(this.comment.isLiked ? $r('sys.symbol.heart_fill') : $r('sys.symbol.heart'))
                .fontSize(DesignTokens.fontHeading())
                .fontColor([this.comment.isLiked ? DesignTokens.accent() : DesignTokens.labelSecondary(this.theme)])
                .margin({ right: 4 })
              
              Text(this.comment.likeCount.toString())
                .fontSize(DesignTokens.fontCaption())
                .fontColor(this.comment.isLiked ? DesignTokens.accent() : DesignTokens.labelSecondary(this.theme))
            }
            .stateStyles({ pressed: this.pressed })
            .onClick(() => {
              if (this.onToggleLike) { this.onToggleLike(this.comment.id); }
            })
            
            // 回复按钮
            Row() {
              // 气泡图标才是「回复」的语义（此前误用了音符列表图标）
              SymbolGlyph($r('sys.symbol.text_bubble_left_2'))
                .fontSize(DesignTokens.fontIconLg())
                .fontColor([DesignTokens.labelSecondary(this.theme)])
                .margin({ left: 16, right: 4 })
              
              // 没有回复时不再塞一个「最新」占位（那是评论类型标签，不是数量）
              Text(this.comment.replyCount > 0
                ? this.comment.replyCount.toString()
                : t('comment_reply'))
                .fontSize(DesignTokens.fontCaption())
                .fontColor(DesignTokens.labelSecondary(this.theme))
            }
            .margin({ left: 16 })
            
            // 热门标签
            if (this.comment.isHot) {
              Text(t('comment_hot_tag'))
                .fontSize(DesignTokens.fontBadge())
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
      // 2in1（PC/平板接鼠标）下的悬停反馈：整条评论高亮
      .hoverEffect(HoverEffect.Highlight)
      
      // 分隔线
      if (!this.isLast) {
        Divider()
          .strokeWidth(0.5)
          .color(DesignTokens.hairlineSeparator(this.theme))
          .margin({ left: 64, right: 16 })
      }
    }
    .width('100%')
    .backgroundColor(DesignTokens.card(this.theme))
  
  }
}
