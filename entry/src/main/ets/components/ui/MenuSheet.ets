/**
 * 动作菜单面板（原系统 showActionMenu 的替代）
 *
 * 系统 showActionMenu 每一行都是居中文字，且最多 6 项、超了还得折叠；
 * 商业化 App（华为音乐 / Apple Music / QQ 音乐）的做法是底部面板 + 左侧图标 + 右侧文案，
 * 行与行左对齐、上下等距。这里统一成一套：
 *
 * - 标题（如歌曲名）左对齐放在最上面，下面可选一行说明（确认框用）
 * - 每行：行首系统符号 + 文案；危险项用危险色，禁用项变淡且点击无效
 * - 底部固定一行「取消」，与动作行之间有分隔，避免误触
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { BottomSheet, dismissSheet } from './BottomSheet';
import { isConfirmKey } from '../../utils/KeyboardTools';
import type { SheetRow } from '../../service/SheetService';

@Component
export struct MenuSheet {
  @StorageProp('theme') theme: string = 'light';
  @Link visible: boolean;
  /** 面板标题（歌曲名 / 列表名），左对齐 */
  @Prop title: string = '';
  /** 确认框的说明文字（菜单为空） */
  @Prop message: string = '';
  @Prop rows: SheetRow[] = [];
  /** 是否展示底部「取消」行（确认框自带的动作行里已有取消，就不再重复） */
  @Prop showCancelRow: boolean = true;
  onPick?: (index: number) => void;
  onCancel?: () => void;

  private cancel(): void {
    this.visible = dismissSheet(this.onCancel);
  }

  /** 点某一行动作：禁用行忽略，其余回传原始下标 */
  private pick(row: SheetRow): void {
    if (row.disabled) {
      return;
    }
    if (this.onPick) {
      this.onPick(row.index);
    }
    this.visible = false;
  }

  private rowColor(row: SheetRow): string {
    if (row.disabled) {
      return DesignTokens.labelTertiary(this.theme);
    }
    return row.danger ? DesignTokens.danger() : DesignTokens.labelPrimary(this.theme);
  }

  build() {
    BottomSheet({
      visible: $visible,
      // 标题自己画（左对齐），不用 BottomSheet 的居中标题栏
      title: '',
      onDismiss: (): void => {
        this.cancel();
      },
      content: (): void => {
        this.Content()
      },
    })
  }

  @Builder
  Content() {
    Column() {
      if (this.title.length > 0) {
        Text(this.title)
          .fontSize(DesignTokens.fontSubhead())
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ bottom: this.message.length > 0 ? 4 : 8 })
      }
      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({ bottom: 8 })
      }

      List() {
        ForEach(this.rows, (row: SheetRow) => {
          ListItem() {
            this.ActionRow(row)
          }
        }, (row: SheetRow) => `menu_row_${row.index}`)

        if (this.showCancelRow) {
          ListItem() {
            Row({ space: 14 }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(DesignTokens.iconLg())
                .fontColor([DesignTokens.labelSecondary(this.theme)])
              Text(t('cancel'))
                .fontSize(DesignTokens.fontTitle())
                .fontColor(DesignTokens.labelSecondary(this.theme))
                .layoutWeight(1)
                .maxLines(1)
                .textAlign(TextAlign.Start)
            }
            .width('100%')
            .height(DesignTokens.touchTarget())
            .alignItems(VerticalAlign.Center)
            .hoverEffect(HoverEffect.Highlight)
            .focusable(true)
            .accessibilityText(t('cancel'))
            .onKeyEvent((event: KeyEvent): void => {
              if (isConfirmKey(event)) {
                this.cancel();
              }
            })
            .onClick(() => {
              this.cancel();
            })
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .divider({
        strokeWidth: 0.33,
        color: DesignTokens.hairlineSeparator(this.theme),
        startMargin: DesignTokens.spaceGutter(),
        endMargin: DesignTokens.spaceGutter(),
      })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 单个动作行：左图标 + 右文案（左对齐，行高统一） */
  @Builder
  ActionRow(row: SheetRow) {
    Row({ space: 14 }) {
      SymbolGlyph(row.icon)
        .fontSize(DesignTokens.iconLg())
        .fontColor([this.rowColor(row)])
      Text(row.label)
        .fontSize(DesignTokens.fontTitle())
        .fontColor(this.rowColor(row))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
    }
    .width('100%')
    .height(DesignTokens.touchTarget())
    .alignItems(VerticalAlign.Center)
    .opacity(row.disabled ? 0.5 : 1)
    .hoverEffect(HoverEffect.Highlight)
    .focusable(!row.disabled)
    .accessibilityText(row.label)
    .onKeyEvent((event: KeyEvent): void => {
      if (isConfirmKey(event)) {
        this.pick(row);
      }
    })
    .onClick(() => {
      this.pick(row);
    })
  }
}
