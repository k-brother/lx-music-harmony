/**
 * 「我的」页功能入口行（本地音乐等）
 *
 * 图标 + 标题 + 描述 + 右侧箭头，整行可点且带按压反馈。
 * 抽出来是为了让「本地音乐」以及后续新增入口（下载、日志…）保持同一样式。
 */
import { DesignTokens } from '../../../theme/DesignTokens';

@Component
export struct MylistEntryRow {
  @StorageProp('theme') theme: string = 'light';
  @Prop icon: Resource = $r('sys.symbol.folder');
  @Prop title: string = '';
  @Prop subtitle: string = '';
  onTap?: () => void;

  @Styles
  pressed() {
    .opacity(DesignTokens.pressedOpacity())
  }

  build() {
    Row({ space: 10 }) {
      SymbolGlyph(this.icon)
        .fontSize(DesignTokens.fontIconXl())
        .fontColor([DesignTokens.labelSecondary(this.theme)])

      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(DesignTokens.fontSubhead())
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .maxLines(1)
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .maxLines(1)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(DesignTokens.fontHeadline())
        .fontColor([DesignTokens.labelTertiary(this.theme)])
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 13, bottom: 13 })
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .shadow(DesignTokens.cardShadow(this.theme))
    .alignItems(VerticalAlign.Center)
    .stateStyles({ pressed: this.pressed })
    .onClick(() => {
      if (this.onTap) {
        this.onTap();
      }
    })
  }
}
