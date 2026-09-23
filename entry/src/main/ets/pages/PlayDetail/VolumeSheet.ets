/**
 * 播放页音量面板（滑杆 + 静音）
 *
 * 对齐安卓版播放页设置弹窗里的音量项：拖动即时生效，一键静音/取消静音。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { BottomSheet } from '../../components/ui/BottomSheet';

@Component
export struct VolumeSheet {
  @StorageProp('theme') theme: string = 'light';
  @Link visible: boolean;
  @Prop volume: number = 60;
  onVolumeChange?: (value: number) => void;
  onToggleMute?: () => void;

  @Builder
  Content() {
    Column({ space: 14 }) {
      this.VolumeHeader()
      this.SliderRow()
      this.ActionsRow()
    }
    .width('100%')
  }

  /** 当前音量数值（面板标题已经写着「音量」，这里只显示百分比，不再重复标题） */
  @Builder
  VolumeHeader() {
    Row() {
      Text(`${this.volume}%`)
        .fontSize(DesignTokens.fontHeadline())
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .layoutWeight(1)
      if (this.volume === 0) {
        Text(t('volume_muted'))
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.accent())
      }
    }
    .width('100%')
  }

  /** 静音图标 + 音量滑杆 */
  @Builder
  SliderRow() {
    Row({ space: 12 }) {
      SymbolGlyph(this.volume === 0 ? $r('sys.symbol.xmark') : $r('sys.symbol.arrow_down_circle'))
        .fontSize(DesignTokens.fontLarge())
        .fontColor([DesignTokens.labelSecondary(this.theme)])
        .accessibilityText(this.volume === 0 ? t('a11y_unmute') : t('a11y_mute'))
        .onClick(() => {
          if (this.onToggleMute) {
            this.onToggleMute();
          }
        })

      Slider({
        value: this.volume,
        min: 0,
        max: 100,
        style: SliderStyle.OutSet,
      })
        .layoutWeight(1)
        .trackColor(DesignTokens.mutedFill(this.theme))
        .selectedColor(DesignTokens.accent())
        .blockColor(DesignTokens.accent())
        .onChange((value: number) => {
          // 音量是本地属性，拖动即生效（不需要等松手）
          if (this.onVolumeChange) {
            this.onVolumeChange(Math.round(value));
          }
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 静音切换 / 关闭 */
  @Builder
  ActionsRow() {
    Row({ space: 12 }) {
      Button(this.volume === 0 ? t('volume_unmute') : t('volume_mute'))
        .type(ButtonType.Capsule)
        .layoutWeight(1)
        .height(DesignTokens.touchTarget())
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .backgroundColor(DesignTokens.mutedFill(this.theme))
        .onClick(() => {
          if (this.onToggleMute) {
            this.onToggleMute();
          }
        })
      Button(t('close'))
        .type(ButtonType.Capsule)
        .layoutWeight(1)
        .height(DesignTokens.touchTarget())
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(DesignTokens.onAccent())
        .backgroundColor(DesignTokens.accent())
        .onClick(() => {
          this.visible = false;
        })
    }
    .width('100%')
  }

  build() {
    BottomSheet({
      visible: $visible,
      title: t('settings_volume'),
      content: (): void => {
        this.Content();
      },
    })
  }
}
