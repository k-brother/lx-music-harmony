/**
 * 下载页多选批量栏
 *
 * 交互对齐系统/主流 App 的批量选择：
 * 左「全选（勾选框 + 文案）」、中「已选 N 项」、右「批量暂停 / 批量继续 / 批量删除」。
 * 三个批量动作按「当前选中任务里有没有对应状态」出现，避免出现点了没反应的按钮
 * （此前无条件渲染，且把「全选」写成了「播放全部」）。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t, tf } from '../../service/LocalizationService';

@Component
export struct DownloadSelectionBar {
  @StorageProp('theme') theme: string = 'light';
  @Prop selectedCount: number = 0;
  @Prop allSelected: boolean = false;
  /** 选中项里是否有「下载中」（可批量暂停） */
  @Prop hasDownloading: boolean = false;
  /** 选中项里是否有「等待中/已暂停」（可批量继续） */
  @Prop hasResumable: boolean = false;
  onToggleSelectAll?: () => void;
  onPauseAll?: () => void;
  onResumeAll?: () => void;
  onDeleteAll?: () => void;

  @Builder
  SelectAllAffordance() {
    Row() {
      SymbolGlyph(this.allSelected ? $r('sys.symbol.checkmark_square_fill') : $r('sys.symbol.square'))
        .fontSize(DesignTokens.fontDisplay())
        .fontColor([DesignTokens.accent()])
      Text(this.allSelected ? t('list_deselect_all') : t('list_select_all'))
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(DesignTokens.accent())
        .fontWeight(FontWeight.Medium)
        .margin({ left: 8 })
    }
    .constraintSize({ minHeight: DesignTokens.touchTarget() })
    .padding({ right: 12 })
    .onClick(() => {
      if (this.onToggleSelectAll) {
        this.onToggleSelectAll();
      }
    })
  }

  build() {
    Column() {
      Row() {
        this.SelectAllAffordance()

        Text(this.selectedCount > 0
          ? tf('download_selected_count', [this.selectedCount.toString()])
          : t('download_select_hint'))
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.selectedCount > 0 && this.hasDownloading) {
          SymbolGlyph($r('sys.symbol.pause'))
            .fontSize(DesignTokens.fontDisplayLarge())
            .fontColor([DesignTokens.accent()])
            .margin({ left: 12 })
            .responseRegion(DesignTokens.touchRegion(22))
            .accessibilityText(t('a11y_pause'))
            .onClick(() => {
              if (this.onPauseAll) {
                this.onPauseAll();
              }
            })
        }

        if (this.selectedCount > 0 && this.hasResumable) {
          SymbolGlyph($r('sys.symbol.play'))
            .fontSize(DesignTokens.fontDisplayLarge())
            .fontColor([DesignTokens.accent()])
            .margin({ left: 12 })
            .responseRegion(DesignTokens.touchRegion(22))
            .accessibilityText(t('a11y_play'))
            .onClick(() => {
              if (this.onResumeAll) {
                this.onResumeAll();
              }
            })
        }

        if (this.selectedCount > 0) {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(DesignTokens.fontDisplayLarge())
            .fontColor([DesignTokens.danger()])
            .margin({ left: 12 })
            .responseRegion(DesignTokens.touchRegion(22))
            .accessibilityText(t('a11y_delete'))
            .onClick(() => {
              if (this.onDeleteAll) {
                this.onDeleteAll();
              }
            })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 52 })
      .padding({ left: DesignTokens.spaceGutter(), right: DesignTokens.spaceGutter() })
      .backgroundColor(DesignTokens.card(this.theme))
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .border({ width: { top: 0.5 }, color: DesignTokens.cardBorder(this.theme) })
    .backgroundColor(DesignTokens.chromeBar(this.theme))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
