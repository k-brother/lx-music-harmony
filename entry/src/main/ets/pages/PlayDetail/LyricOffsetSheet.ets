/**
 * 播放页「歌词偏移」面板（滑杆 + 重置）
 *
 * 之前用的是 7 档动作菜单（-2s…+2s），而 `appActionMenu` 超过 5 项会自动折叠成
 * 「更多…」，用户最常用的 ±0.5s 反而要点两次；档位也只有固定几档。
 * 改成连续滑杆后：拖动即时生效（歌词立刻跟着走）、支持任意 0.1s 精度、一键重置，
 * 与华为音乐的「歌词校准」、Apple Music 的歌词偏移交互一致。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { BottomSheet } from '../../components/ui/BottomSheet';

/** 偏移范围 ±3 秒，步进 0.1 秒 */
const OFFSET_LIMIT_MS = 3000;

@Component
export struct LyricOffsetSheet {
  @StorageProp('theme') theme: string = 'light';
  @Link visible: boolean;
  /** 当前偏移（秒，正=歌词提前） */
  @Prop offsetSeconds: number = 0;
  onOffsetChange?: (value: number) => void;

  /** 秒 → `+0.5s` / `-1.2s` / `0.0s` */
  private formatOffset(seconds: number): string {
    if (Math.abs(seconds) < 0.05) {
      return '0.0s';
    }
    const sign = seconds > 0 ? '+' : '-';
    return `${sign}${Math.abs(seconds).toFixed(1)}s`;
  }

  @Builder
  Content() {
    Column({ space: 14 }) {
      Row() {
        Text(t('lyric_offset_hint'))
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .layoutWeight(1)
          .maxLines(2)
        Text(this.formatOffset(this.offsetSeconds))
          .fontSize(15)
          .fontColor(DesignTokens.accent())
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')

      Slider({
        value: this.offsetSeconds * 1000,
        min: -OFFSET_LIMIT_MS,
        max: OFFSET_LIMIT_MS,
        step: 100,
        style: SliderStyle.OutSet,
      })
        .width('100%')
        .trackColor(DesignTokens.mutedFill(this.theme))
        .selectedColor(DesignTokens.accent())
        .blockColor(DesignTokens.accent())
        .onChange((value: number, mode: SliderChangeMode) => {
          // 拖动即生效：歌词会跟着手指实时对齐（松手前也能听到/看到效果）
          if (this.onOffsetChange) {
            this.onOffsetChange(Math.round(value / 100) / 10);
          }
        })

      Row({ space: 12 }) {
        Button(t('reset'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(DesignTokens.touchTarget())
          .fontSize(15)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .backgroundColor(DesignTokens.mutedFill(this.theme))
          .onClick(() => {
            if (this.onOffsetChange) {
              this.onOffsetChange(0);
            }
          })
        Button(t('close'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(DesignTokens.touchTarget())
          .fontSize(15)
          .fontColor(DesignTokens.onAccent())
          .backgroundColor(DesignTokens.accent())
          .onClick(() => {
            this.visible = false;
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  build() {
    BottomSheet({
      visible: $visible,
      title: t('lyric_offset'),
      content: (): void => {
        this.Content();
      },
    })
  }
}
