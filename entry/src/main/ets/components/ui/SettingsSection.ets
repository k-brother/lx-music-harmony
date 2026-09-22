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
import { SelectSheet } from './SelectSheet';
import { InputSheet } from './InputSheet';
import type { SettingOption, SettingSectionItem } from './SettingsTypes';
import { hapticService } from '../../service/HapticService';

@Component
export struct SettingsSection {
  @StorageProp('theme') theme: string = 'light';
  @Prop title: string = '';
  @Prop items: SettingSectionItem[] = [];

  // select / input 的弹层状态（分组组件无需感知）
  @State showSelect: boolean = false;
  @State selectTitle: string = '';
  @State selectOptions: SettingOption[] = [];
  @State selectValue: string = '';
  @State showInput: boolean = false;
  @State inputTitle: string = '';
  @State inputValue: string = '';
  @State inputNumberOnly: boolean = false;
  private pendingChange: ((value: string) => void) | null = null;

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
    if (!item.options || item.options.length === 0 || !item.onChange) {
      return;
    }
    this.pendingChange = item.onChange;
    this.selectTitle = item.title;
    this.selectOptions = item.options;
    this.selectValue = item.value as string;
    this.showSelect = true;
  }

  private openInput(item: SettingSectionItem): void {
    if (!item.onChange) {
      return;
    }
    this.pendingChange = item.onChange;
    this.inputTitle = item.title;
    this.inputValue = item.value as string;
    // 数字类设置（并发数、历史条数、字号…）用数字键盘
    this.inputNumberOnly = this.isNumericValue(item.value);
    this.showInput = true;
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
        if (this.title.length > 0) {
          Text(this.title)
            .fontSize(DesignTokens.fontCaption())
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .width('100%')
            .padding({ left: 4, top: 18, bottom: 8 })
        }

        Column() {
          ForEach(this.items, (item: SettingSectionItem, index: number) => {
            Column() {
              Row() {
                Column() {
                  Text(item.title)
                    .fontSize(15)
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
                    .fontSize(14)
                    .fontColor(item.danger === true ? DesignTokens.danger() : DesignTokens.labelSecondary(this.theme))
                    .maxLines(1)
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(18)
                    .fontColor([DesignTokens.labelTertiary(this.theme)])
                    .margin({ left: 6 })
                } else if (item.type === 'input') {
                  Text(item.value as string)
                    .fontSize(14)
                    .fontColor(DesignTokens.labelSecondary(this.theme))
                    .maxLines(1)
                } else if (item.type === 'button') {
                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(18)
                    .fontColor([DesignTokens.labelTertiary(this.theme)])
                }
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

              if (index < this.items.length - 1) {
                Divider()
                  .strokeWidth(0.5)
                  .color(DesignTokens.cardBorder(this.theme))
                  .margin({ left: 16, right: 16 })
              }
            }
            .width('100%')
          }, (item: SettingSectionItem, index: number) => `${item.title}_${index}`)
        }
        .width('100%')
        .backgroundColor(DesignTokens.card(this.theme))
        .borderRadius(DesignTokens.radiusCard())
        .shadow(DesignTokens.cardShadow(this.theme))
      }
      .width('100%')

      if (this.showSelect) {
        SelectSheet({
          visible: $showSelect,
          title: this.selectTitle,
          options: this.selectOptions,
          value: this.selectValue,
          onPick: (value: string): void => {
            if (this.pendingChange) {
              this.pendingChange(value);
            }
          },
        })
      }

      if (this.showInput) {
        InputSheet({
          visible: $showInput,
          title: this.inputTitle,
          placeholder: this.inputTitle,
          value: this.inputValue,
          numberOnly: this.inputNumberOnly,
          onSubmit: (value: string): void => {
            if (this.pendingChange) {
              this.pendingChange(value);
            }
          },
        })
      }
    }
    .width('100%')
  }
}
