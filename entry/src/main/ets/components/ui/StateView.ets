/**
 * 统一状态视图（加载中 / 空 / 失败）
 *
 * 之前每个页面各写一遍 Column + LoadingProgress 或 EmptyView + ErrorView，尺寸与文案不一。
 * 现在统一出口：
 *   StateView({ state: 'loading' })
 *   StateView({ state: 'empty', message: '暂无数据', iconRes: $r('sys.symbol.music_note_list') })
 *   StateView({ state: 'error', message: '加载失败', actionText: '重试', onAction: () => this.reload() })
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { isConfirmKey } from '../../utils/KeyboardTools';

export type ViewState = 'loading' | 'empty' | 'error';

@Component
export struct StateView {
  @StorageProp('theme') theme: string = 'light';
  @Prop state: ViewState = 'empty';
  @Prop message: string = '';
  @Prop iconRes: Resource = $r('sys.symbol.music_note_list');
  /** 可选行动按钮（错误态重试最常见） */
  @Prop actionText: string = '';
  onAction?: () => void;

  build() {
    Column() {
      if (this.state === 'loading') {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(DesignTokens.accent())
      } else {
        // 系统符号必须用 SymbolGlyph 渲染（Image 加载 sys.symbol.* 会空白）
        SymbolGlyph(this.state === 'error' ? $r('sys.symbol.xmark') : this.iconRes)
          .fontSize(this.state === 'error' ? 40 : 48)
          .fontColor([DesignTokens.labelTertiary(this.theme)])
          .opacity(0.6)
      }

      Text(this.resolveMessage())
        .fontSize(DesignTokens.fontBody())
        .fontColor(DesignTokens.labelSecondary(this.theme))
        .margin({ top: 12 })
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })

      if (this.actionText.length > 0) {
        Text(this.actionText)
          .fontSize(DesignTokens.fontBody())
          .fontColor(DesignTokens.accent())
          .border({ width: 1, color: DesignTokens.accent() })
          .borderRadius(DesignTokens.radiusPill())
          .padding({ left: 18, right: 18, top: 7, bottom: 7 })
          .margin({ top: 14 })
          // 2in1：行动按钮（重试/空态引导）也要能用键盘操作，PC 上没有电容按压
          .hoverEffect(HoverEffect.Highlight)
          .focusable(true)
          .onKeyEvent((event: KeyEvent): void => {
            if (isConfirmKey(event) && this.onAction) {
              this.onAction();
            }
          })
          .onClick(() => {
            if (this.onAction) {
              this.onAction();
            }
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private resolveMessage(): string {
    if (this.message.length > 0) {
      return this.message;
    }
    if (this.state === 'loading') {
      return t('loading');
    }
    if (this.state === 'error') {
      return t('load_failed');
    }
    return t('no_data');
  }
}
