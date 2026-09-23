/**
 * 面板标题行：左标题 + 右上角关闭。
 *
 * 统一规则（真机反馈定的）：底部面板不再给「取消」单独留一行/一个按钮，
 * 一律收成右上角的圆底 × 图标；表单类面板只保留一个主操作按钮。
 * 各面板此前各写一份标题行 + CloseButton，这里收口成一处。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { isConfirmKey } from '../../utils/KeyboardTools';

@Component
export struct SheetHeader {
  @StorageProp('theme') theme: string = 'light';
  @Prop title: string = '';
  /** 右侧附加动作（可空）：例如「清空」「定位当前」 */
  @BuilderParam trailing?: () => void;
  onClose?: () => void;

  build() {
    Row() {
      Text(this.title)
        .fontSize(DesignTokens.fontSubhead())
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.Start)

      if (this.trailing) {
        this.trailing()
      }

      Stack() {
        Circle({ width: 28, height: 28 })
          .fill(DesignTokens.mutedFill(this.theme))
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(DesignTokens.iconLg())
          .fontColor([DesignTokens.labelSecondary(this.theme)])
      }
      .width(DesignTokens.touchTarget())
      .height(DesignTokens.touchTarget())
      .align(Alignment.Center)
      .accessibilityText(t('close'))
      .hoverEffect(HoverEffect.Highlight)
      .focusable(true)
      .onKeyEvent((event: KeyEvent): void => {
        if (isConfirmKey(event) && this.onClose) {
          this.onClose();
        }
      })
      .onClick(() => {
        if (this.onClose) {
          this.onClose();
        }
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
