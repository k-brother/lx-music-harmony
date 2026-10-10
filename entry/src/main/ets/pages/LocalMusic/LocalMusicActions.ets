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
  /** 播放全部（有曲目时显示） */
  onPlayAll?: () => void;
  /** 全部匹配在线歌词/封面（有曲目时显示） */
  onMatchAll?: () => void;

  build() {
    Row({ space: 4 }) {
      if (this.hasTracks) {
        IconActionButton({
          icon: $r('sys.symbol.play_circle'),
          glyphColor: DesignTokens.accent(),
          bgFill: DesignTokens.accentSoft(this.theme),
          a11yLabel: t('play_all'),
          onTap: (): void => {
            if (this.onPlayAll) {
              this.onPlayAll();
            }
          },
        })
      }
      if (this.hasTracks) {
        IconActionButton({
          icon: $r('sys.symbol.arrow_clockwise'),
          glyphColor: DesignTokens.labelSecondary(this.theme),
          bgFill: DesignTokens.mutedFill(this.theme),
          a11yLabel: t('a11y_refresh'),
          onTap: (): void => {
            if (this.onRescan) {
              this.onRescan();
            }
          },
        })
      }
      if (this.hasTracks) {
        IconActionButton({
          icon: $r('sys.symbol.wand_and_stars'),
          glyphColor: DesignTokens.labelSecondary(this.theme),
          bgFill: DesignTokens.mutedFill(this.theme),
          a11yLabel: t('match_all'),
          onTap: (): void => {
            if (this.onMatchAll) {
              this.onMatchAll();
            }
          },
        })
      }
      IconActionButton({
        icon: $r('sys.symbol.plus'),
        glyphColor: DesignTokens.accent(),
        bgFill: DesignTokens.accentSoft(this.theme),
        a11yLabel: t('a11y_import'),
        onTap: (): void => {
          if (this.onImport) {
            this.onImport();
          }
        },
      })
    }
    .alignItems(VerticalAlign.Center)
  }
}

/**
 * 圆底图标按钮：统一 34vp 视觉 + 44vp 热区。
 *
 * 独立成组件（而不是页面的 @Builder）：颜色随主题变化，@Builder 参数在本工程里
 * 出现过「状态变了样式不刷新」的问题，@Prop 才可靠。
 */
@Component
struct IconActionButton {
  @Prop icon: Resource;
  @Prop glyphColor: string = '';
  @Prop bgFill: string = '';
  /** 无障碍朗读文案（纯图标按钮必须有） */
  @Prop a11yLabel: string = '';
  onTap?: () => void;

  build() {
    Row() {
      SymbolGlyph(this.icon)
        .fontSize(DesignTokens.iconLg())
        .fontColor([this.glyphColor])
    }
    .width(34)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.bgFill)
    .borderRadius(17)
    .responseRegion(DesignTokens.touchRegion(34))
    .accessibilityText(this.a11yLabel)
    .onClick(() => {
      hapticService.light();
      if (this.onTap) {
        this.onTap();
      }
    })
  }
}
