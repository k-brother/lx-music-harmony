/**
 * 「我的」页区块标题（大标题 + 描述 + 右侧动作）
 *
 * 统一「我喜欢 / 播放历史 / 自建歌单」三处的标题样式，
 * 右侧动作要么是「查看全部」，要么是自定义按钮（新建歌单）。
 */
import { DesignTokens } from '../../../theme/DesignTokens';

@Component
export struct MylistSectionHeader {
  @StorageProp('theme') theme: string = 'light';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  /** 右侧「查看全部」文案；为空则不显示 */
  @Prop actionText: string = '';
  /** 是否显示右侧主按钮（新建歌单） */
  @Prop showPrimaryAction: boolean = false;
  @Prop primaryText: string = '';
  /** 顶部/底部内边距（不同区块间距略有差异） */
  @Prop topPadding: number = 16;
  @Prop bottomPadding: number = 8;
  onAction?: () => void;
  onPrimaryAction?: () => void;

  build() {
    Row() {
      Column({ space: 4 }) {
        Text(this.title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(DesignTokens.labelPrimary(this.theme))
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .maxLines(1)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: 8 }) {
        if (this.actionText.length > 0) {
          Text(this.actionText)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.accent())
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .onClick(() => {
              if (this.onAction) {
                this.onAction();
              }
            })
        }
        if (this.showPrimaryAction) {
          Row({ space: 4 }) {
            Image($r('app.media.ic_common_create'))
              .width(14)
              .height(14)
              .fillColor(Color.White)
            Text(this.primaryText)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
          }
          .height(30)
          .padding({ left: 12, right: 12 })
          .backgroundColor(DesignTokens.accent())
          .borderRadius(DesignTokens.radiusPill())
          .onClick(() => {
            if (this.onPrimaryAction) {
              this.onPrimaryAction();
            }
          })
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: this.topPadding, bottom: this.bottomPadding })
    .alignItems(VerticalAlign.Center)
  }
}
