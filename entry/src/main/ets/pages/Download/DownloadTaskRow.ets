/**
 * 下载任务行
 *
 * 从 DownloadPage 的 @Builder buildTaskItem 抽成独立组件：
 * 左侧状态色条 + 标题/歌手·专辑 + 状态·音质·体积 +（下载中/暂停）进度条 + 右侧操作。
 * 组件只接收「行模型 + 回调」，状态判断与文案在 DownloadView 里，改文案不会碰到布局。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { isConfirmKey } from '../../utils/KeyboardTools';
import { t } from '../../service/LocalizationService';
import type { DownloadRowModel } from './DownloadView';

@Component
export struct DownloadTaskRow {
  @StorageProp('theme') theme: string = 'light';
  @Prop row: DownloadRowModel;
  onToggleSelect?: () => void;
  onPrimaryAction?: () => void;
  onDelete?: () => void;
  onPlay?: () => void;

  /** 多选态下点整行即勾选：给按压反馈，避免点了没反应的感觉 */
  @Styles
  pressed() {
    .opacity(DesignTokens.pressedOpacity())
  }

  /** 主操作图标：等待/暂停 → 播放，下载中 → 暂停，失败 → 重试，完成 → 播放 */
  private primaryIcon(): Resource {
    if (this.row.actionKind === 'pause') {
      return $r('sys.symbol.pause');
    }
    if (this.row.actionKind === 'retry') {
      return $r('sys.symbol.arrow_clockwise');
    }
    return $r('sys.symbol.play');
  }

  @Builder
  StatusStripe() {
    Column()
      .width(4)
      .constraintSize({ minHeight: 88 })
      .backgroundColor(this.row.statusColor)
  }

  @Builder
  TrailingActions() {
    Column() {
      if (this.row.actionKind !== 'none') {
        SymbolGlyph(this.primaryIcon())
          .fontSize(DesignTokens.fontDisplayLarge())
          .fontColor([DesignTokens.accent()])
          .responseRegion(DesignTokens.touchRegion(22))
          .accessibilityText(t('a11y_play'))
          .onClick(() => {
            if (this.row.actionKind === 'play') {
              if (this.onPlay) {
                this.onPlay();
              }
            } else if (this.onPrimaryAction) {
              this.onPrimaryAction();
            }
          })
      }

      if (this.row.canDelete) {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(DesignTokens.fontDisplayLarge())
          .fontColor([DesignTokens.danger()])
          .margin({ top: 14 })
          .responseRegion(DesignTokens.touchRegion(22))
          .accessibilityText(t('a11y_delete'))
          .onClick(() => {
            if (this.onDelete) {
              this.onDelete();
            }
          })
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 8 })
  }

  build() {
    Row() {
      this.StatusStripe()

      Row() {
        if (this.row.selectMode) {
          SymbolGlyph(this.row.selected ? $r('sys.symbol.checkmark_square_fill') : $r('sys.symbol.square'))
            .fontSize(DesignTokens.fontDisplay())
            .fontColor([DesignTokens.accent()])
            .margin({ right: 12 })
        }

        Column() {
          Text(this.row.title)
            .fontSize(DesignTokens.fontTitle())
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.row.subtitle)
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row() {
            Text(this.row.statusText)
              .fontSize(DesignTokens.fontMicro())
              .fontColor(this.row.statusColor)
              .fontWeight(FontWeight.Medium)
            Text(` · ${this.row.metaText}`)
              .fontSize(DesignTokens.fontMicro())
              .fontColor(DesignTokens.labelTertiary(this.theme))
          }
          .margin({ top: 8 })

          if (this.row.showProgress) {
            Progress({ value: this.row.progress, total: 100 })
              .width('100%')
              .height(4)
              .color(this.row.statusColor)
              .backgroundColor(DesignTokens.mutedFill(this.theme))
              .margin({ top: 10 })
          }

          if (this.row.errorText.length > 0) {
            Text(this.row.errorText)
              .fontSize(DesignTokens.fontMicro())
              .fontColor(DesignTokens.danger())
              .margin({ top: 6 })
              .maxLines(2)
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (!this.row.selectMode) {
          this.TrailingActions()
        }
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .padding({ top: 14, bottom: 14, left: 12, right: 14 })
    }
    .width('100%')
    .borderRadius(DesignTokens.radiusCard())
    .clip(true)
    .backgroundColor(DesignTokens.card(this.theme))
    .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
    .alignItems(VerticalAlign.Center)
    // 2in1（PC/平板接鼠标）下的悬停反馈：系统标准高亮，触屏设备无副作用
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ pressed: this.pressed })
    .onClick(() => {
      if (this.row.selectMode && this.onToggleSelect) {
        this.onToggleSelect();
      }
    })
    // 2in1（PC 接键盘）：多选态下回车/空格=勾选/取消勾选
    .focusable(true)
    .onKeyEvent((event: KeyEvent): void => {
      if (isConfirmKey(event) && this.row.selectMode && this.onToggleSelect) {
        this.onToggleSelect();
      }
    })
  }
}
