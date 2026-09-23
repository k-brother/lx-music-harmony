/**
 * 本地音乐页 - 顶部两个动作按钮（重新扫描 / 导入）
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { hapticService } from '../../service/HapticService';

@Component
export struct LocalMusicActions {
  @StorageProp('theme') theme: string = 'light';
  /** 有曲目时才显示「重新扫描」 */
  @Prop hasTracks: boolean = false;
  onRescan?: () => void;
  onImport?: () => void;

  /** 圆底图标按钮：统一 34vp 视觉 + 44vp 热区 */
  @Builder
  IconAction(icon: Resource, color: string, background: string, action: () => void) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(DesignTokens.iconLg())
        .fontColor([color])
    }
    .width(34)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(background)
    .borderRadius(17)
    .responseRegion(DesignTokens.touchRegion(34))
    .accessibilityText(t('a11y_more'))
    .onClick(() => {
      hapticService.light();
      action();
    })
  }

  build() {
    Row({ space: 4 }) {
      if (this.hasTracks) {
        this.IconAction($r('sys.symbol.arrow_clockwise'),
          DesignTokens.labelSecondary(this.theme),
          DesignTokens.mutedFill(this.theme),
          (): void => {
            if (this.onRescan) {
              this.onRescan();
            }
          })
      }
      this.IconAction($r('sys.symbol.plus'),
        DesignTokens.accent(),
        DesignTokens.accentSoft(this.theme),
        (): void => {
          if (this.onImport) {
            this.onImport();
          }
        })
    }
    .alignItems(VerticalAlign.Center)
  }
}
