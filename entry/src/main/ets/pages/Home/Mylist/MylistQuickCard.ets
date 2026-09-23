/**
 * 「我的」页快捷入口卡（我喜欢 / 播放历史）
 *
 * 商业化 App 的常用做法：两列等宽卡片，图标 + 标题 + 数量，按压有反馈。
 */
import { DesignTokens } from '../../../theme/DesignTokens';

@Component
export struct MylistQuickCard {
  @StorageProp('theme') theme: string = 'light';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop icon: Resource = $r('sys.symbol.heart_fill');
  @Prop iconColor: string = DesignTokens.accent();
  onTap?: () => void;

  @Styles
  pressed() {
    .opacity(DesignTokens.pressedOpacity())
  }

  build() {
    Column({ space: 8 }) {
      SymbolGlyph(this.icon)
        .fontSize(DesignTokens.fontDisplay())
        .fontColor([this.iconColor])
      Text(this.title)
        .fontSize(DesignTokens.fontSubhead())
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .maxLines(1)
      Text(this.subtitle)
        .fontSize(DesignTokens.fontCaption())
        .fontColor(DesignTokens.labelTertiary(this.theme))
        .maxLines(1)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .shadow(DesignTokens.cardShadow(this.theme))
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .stateStyles({ pressed: this.pressed })
    .onClick(() => {
      if (this.onTap) {
        this.onTap();
      }
    })
  }
}
