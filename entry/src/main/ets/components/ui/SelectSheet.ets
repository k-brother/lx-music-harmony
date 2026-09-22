/**
 * 选择面板（单选）
 *
 * 取代设置页里手写的「居中弹窗 + ForEach 列表 + 回调透传」：
 * 底部面板、当前项打勾、点击即回传并关闭。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { BottomSheet } from './BottomSheet';
import type { SettingOption } from './SettingsTypes';

@Component
export struct SelectSheet {
  @StorageProp('theme') theme: string = 'light';
  @Link visible: boolean;
  @Prop title: string = '';
  @Prop options: SettingOption[] = [];
  @Prop value: string = '';
  onPick?: (value: string) => void;

  build() {
    BottomSheet({
      visible: $visible,
      title: this.title,
      content: (): void => {
        this.Options();
      },
    })
  }

  @Builder
  Options() {
    List() {
      ForEach(this.options, (option: SettingOption) => {
        ListItem() {
          Row() {
            Text(option.label)
              .fontSize(16)
              .fontColor(option.value === this.value ? DesignTokens.accent() : DesignTokens.labelPrimary(this.theme))
              .fontWeight(option.value === this.value ? FontWeight.Medium : FontWeight.Normal)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (option.value === this.value) {
              SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                .fontSize(22)
                .fontColor([DesignTokens.accent()])
            }
          }
          .width('100%')
          .height(DesignTokens.touchTarget())
          .alignItems(VerticalAlign.Center)
        }
        .onClick(() => {
          this.visible = false;
          if (this.onPick) {
            this.onPick(option.value);
          }
        })
      }, (option: SettingOption) => option.value)
    }
    .width('100%')
    .constraintSize({ maxHeight: '50%' })
    .scrollBar(BarState.Off)
    .margin({ top: 4 })

    Button(t('cancel'))
      .type(ButtonType.Capsule)
      .width('100%')
      .height(DesignTokens.touchTarget())
      .fontSize(16)
      .fontColor(DesignTokens.labelPrimary(this.theme))
      .backgroundColor(DesignTokens.mutedFill(this.theme))
      .margin({ top: 12 })
      .onClick(() => {
        this.visible = false;
      })
  }
}
