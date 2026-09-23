/**
 * 设置分组渲染器（商业化分组卡片样式）
 *
 * 所有设置分组的视觉与交互都在这里定义一处：
 * - 分组标题（小号次级色）+ 圆角卡片容器
 * - 行内：标题/描述 + 右侧（开关 / 当前值+箭头 / 箭头 / 纯文本），行高 ≥ 44vp 且有按压反馈
 * - 分隔线在卡片内缩进（iOS 分组列表观感）
 * - 「select / input」行自带底部选择/输入面板，分组组件不需要再写弹层与回调透传
 *
 * 分组组件只需提供 items：
 *   SettingsSection({ title: t('settings_basic'), items: this.buildItems() })
 */
import { DesignTokens } from '../../theme/DesignTokens';
import type { SettingOption, SettingSectionItem } from './SettingsTypes';
import { hapticService } from '../../service/HapticService';
import { sheetService, type SheetOption } from '../../service/SheetService';

@Component
export struct SettingsSection {
  @StorageProp('theme') theme: string = 'light';
  @Prop title: string = '';
  @Prop items: SettingSectionItem[] = [];

  @Styles
  pressed() {
    .opacity(DesignTokens.pressedOpacity())
  }

  /** 取选项的展示文案 */
  private optionLabel(item: SettingSectionItem): string {
    const value = item.value as string;
    const options = item.options ?? [];
    for (let i = 0; i < options.length; i++) {
      if (options[i].value === value) {
        return options[i].label;
      }
    }
    return value;
  }

  private openSelect(item: SettingSectionItem): void {
    const options = item.options;
    const onChange = item.onChange;
    if (!options || options.length === 0 || !onChange) {
      return;
    }
    // 走全局面板：设置分组在 Scroll 内，自己挂浮层会被 BottomSheet 定位裁剪
    const sheetOptions: SheetOption[] = options.map((option: SettingOption): SheetOption => {
      const mapped: SheetOption = { label: option.label, value: option.value };
      return mapped;
    });
    sheetService.select(item.title, sheetOptions, item.value as string).then((value: string): void => {
      if (value.length > 0) {
        onChange(value);
      }
    });
  }

  private openInput(item: SettingSectionItem): void {
    const onChange = item.onChange;
    if (!onChange) {
      return;
    }
    // 数字类设置（并发数、历史条数、字号…）用数字键盘
    const numberOnly = this.isNumericValue(item.value);
    sheetService.input(item.title, item.value as string, item.title, numberOnly).then((value: string): void => {
      if (value.length > 0) {
        onChange(value);
      }
    });
  }

  private isNumericValue(value: string | boolean | undefined): boolean {
    if (typeof value !== 'string' || value.length === 0) {
      return false;
    }
    return !isNaN(Number(value));
  }

  build() {
    Stack() {
      Column() {
        this.SectionTitle()

        this.ItemList()
      }
      .width('100%')
    }
    .width('100%')
  }

  /** 分组标题（次级色小号字） */
  @Builder
  SectionTitle() {
    if (this.title.length > 0) {
      Text(this.title)
        .fontSize(DesignTokens.fontCaption())
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.labelTertiary(this.theme))
        .width('100%')
        .padding({ left: 4, top: 18, bottom: 8 })
    }
  }

  /** 分组卡片（行列表） */
  @Builder
  ItemList() {
    Column() {
      ForEach(this.items, (item: SettingSectionItem, index: number) => {
        Column() {
          this.ItemRow(item)

          if (index < this.items.length - 1) {
            Divider()
              .strokeWidth(0.5)
              .color(DesignTokens.cardBorder(this.theme))
              .margin({ left: 16, right: 16 })
          }
        }
        .width('100%')
        // key 必须带上当前值：只按 title+index 做 key 时，ForEach 会复用旧节点，
        // 真机上表现为「选完选项右侧文案不变（其实设置已生效）」。
      }, (item: SettingSectionItem, index: number): string =>
        `${index}_${item.type}_${item.title}_${String(item.value)}`)
    }
    .width('100%')
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .shadow(DesignTokens.cardShadow(this.theme))
  }

  /** 一行设置：左侧标题/描述 + 右侧控件/当前值 */
  @Builder
  ItemRow(item: SettingSectionItem) {
    Row() {
      this.ItemLabels(item)

      this.ItemTrailing(item)
    }
    .width('100%')
    .constraintSize({ minHeight: DesignTokens.touchTarget() })
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
    .stateStyles({ pressed: this.pressed })
    .onClick(() => {
      if (item.type === 'button' && item.onClick) {
        item.onClick();
      } else if (item.type === 'select') {
        this.openSelect(item);
      } else if (item.type === 'input') {
        this.openInput(item);
      }
    })
  }

  /** 行左侧：标题 + 描述（危险行用危险色） */
  @Builder
  ItemLabels(item: SettingSectionItem) {
    Column() {
      Text(item.title)
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(item.danger === true ? DesignTokens.danger() : DesignTokens.labelPrimary(this.theme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (item.description && item.description.length > 0) {
        Text(item.description)
          .fontSize(DesignTokens.fontMicro())
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  /** 行右侧：开关 / 当前值 + 箭头 / 只读信息 / 箭头 */
  @Builder
  ItemTrailing(item: SettingSectionItem) {
    if (item.type === 'toggle') {
      Toggle({ type: ToggleType.Switch, isOn: item.value as boolean })
        .selectedColor(DesignTokens.accent())
        .onChange((isOn: boolean) => {
          hapticService.light();
          if (item.onChangeToggle) {
            item.onChangeToggle(isOn);
          }
        })
    } else if (item.type === 'select') {
      Text(this.optionLabel(item))
        .fontSize(DesignTokens.fontBody())
        .fontColor(item.danger === true ? DesignTokens.danger() : DesignTokens.labelSecondary(this.theme))
        .maxLines(1)
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(DesignTokens.fontHeading())
        .fontColor([DesignTokens.labelTertiary(this.theme)])
        .margin({ left: 6 })
    } else if (item.type === 'input') {
      Text(item.value as string)
        .fontSize(DesignTokens.fontBody())
        .fontColor(DesignTokens.labelSecondary(this.theme))
        .maxLines(1)
    } else if (item.type === 'info') {
      // 只读信息行（同步状态、版本号等）：右侧显示当前值，不可点击
      Text(item.value as string)
        .fontSize(DesignTokens.fontCaption())
        .fontColor(DesignTokens.labelSecondary(this.theme))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .constraintSize({ maxWidth: 180 })
        .margin({ left: 12 })
    } else if (item.type === 'button') {
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(DesignTokens.fontHeading())
        .fontColor([DesignTokens.labelTertiary(this.theme)])
    }
  }

}
