/**
 * 选择面板（单选）
 *
 * 取代设置页里手写的「居中弹窗 + ForEach 列表 + 回调透传」：
 * 底部面板、当前项打勾、点击即回传并关闭。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { BottomSheet, dismissSheet } from './BottomSheet';
import type { SettingOption } from './SettingsTypes';
import { SheetHeader } from './SheetHeader';
import { isConfirmKey } from '../../utils/KeyboardTools';

@Component
export struct SelectSheet {
  @StorageProp('theme') theme: string = 'light';
  @Link visible: boolean;
  @Prop title: string = '';
  @Prop options: SettingOption[] = [];
  @Prop value: string = '';
  onPick?: (value: string) => void;
  /** 关闭（点遮罩/取消）：调用方据此按「未修改」处理 */
  onCancel?: () => void;

  /** 一屏最多展示多少行（更多则在面板内滚动） */
  private static readonly MAX_VISIBLE_ROWS: number = 8;

  /** 行区高度 */
  private listHeight(): number {
    const visible: number = Math.min(this.options.length, SelectSheet.MAX_VISIBLE_ROWS);
    return visible * DesignTokens.touchTarget();
  }

  /**
   * 面板高度 = 标题行 + 行区 + 上下留白。
   * 不写死高度：选项只有 2-4 个时（音质/主题/下载文件名格式…）下面不该留一大片空白。
   */
  private sheetHeightVp(): number {
    const titleHeight: number = this.title.length > 0 ? 40 : 8;
    return titleHeight + this.listHeight() + 34;
  }

  private cancel(): void {
    this.visible = dismissSheet(this.onCancel);
  }

  build() {
    BottomSheet({
      visible: $visible,
      // 标题自绘（左对齐 + 右上角关闭），不用 BottomSheet 的居中标题栏
      title: '',
      sheetHeightVp: this.sheetHeightVp(),
      onDismiss: (): void => {
        this.cancel();
      },
      content: (): void => {
        this.Options();
      },
    })
  }

  @Builder
  Options() {
    // 标题行：左标题 + 右上角关闭（取消不再单独占一行，与其他面板统一）
    SheetHeader({
      title: this.title,
      onClose: (): void => {
        this.cancel();
      },
    })

    List() {
      ForEach(this.options, (option: SettingOption) => {
        ListItem() {
          Row() {
            Text(option.label)
              .fontSize(DesignTokens.fontTitle())
              .fontColor(option.value === this.value ? DesignTokens.accent() : DesignTokens.labelPrimary(this.theme))
              .fontWeight(option.value === this.value ? FontWeight.Medium : FontWeight.Normal)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (option.value === this.value) {
              SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                .fontSize(DesignTokens.fontIconXl())
                .fontColor([DesignTokens.accent()])
            }
          }
          .width('100%')
          .height(DesignTokens.touchTarget())
          .alignItems(VerticalAlign.Center)
          // 2in1：选项行给悬停反馈 + 键盘可聚焦（PC 上没有电容按压）
          .hoverEffect(HoverEffect.Highlight)
          .focusable(true)
          .onKeyEvent((event: KeyEvent): void => {
            if (isConfirmKey(event)) {
              if (this.onPick) {
                this.onPick(option.value);
              }
              this.visible = false;
            }
          })
        }
        .accessibilityText(t('a11y_select_all'))
        .onClick(() => {
          // 先回调再关闭（同 InputSheet：关闭事件会把请求按取消处理）
          if (this.onPick) {
            this.onPick(option.value);
          }
          this.visible = false;
        })
      }, (option: SettingOption) => option.value)
    }
    .width('100%')
    .constraintSize({ maxHeight: '50%' })
    .scrollBar(BarState.Off)
    .margin({ top: 4 })

  }
}
