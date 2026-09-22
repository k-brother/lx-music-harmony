/**
 * 首页音源切换条
 *
 * 商业化 App 的做法：横向可滚动的标签 + 选中态下划线指示，
 * 而不是把 5 个音源等宽硬塞进一行（等宽在文案变长时会被挤压变形）。
 */
import { DesignTokens } from '../../../theme/DesignTokens';

export interface SourceTabOption {
  id: string;
  name: string;
}

@Component
export struct SourceTabBar {
  @StorageProp('theme') theme: string = 'light';
  @Prop options: SourceTabOption[] = [];
  @Prop activeId: string = '';
  onSelect?: (id: string) => void;

  @Styles
  pressed() {
    .opacity(DesignTokens.pressedOpacity())
  }

  build() {
    Scroll() {
      Row({ space: 4 }) {
        ForEach(this.options, (option: SourceTabOption) => {
          Column({ space: 4 }) {
            Text(option.name)
              .fontSize(16)
              .fontColor(this.activeId === option.id ? DesignTokens.accent() : DesignTokens.labelSecondary(this.theme))
              .fontWeight(this.activeId === option.id ? FontWeight.Medium : FontWeight.Normal)
              .maxLines(1)
              .padding({ left: 10, right: 10, top: 8, bottom: 4 })

            // 选中下划线（宽度与文案联动，形成"指示条"观感）
            Row()
              .width(this.activeId === option.id ? 22 : 0)
              .height(2.5)
              .borderRadius(2)
              .backgroundColor(DesignTokens.accent())
              .animation({ duration: DesignTokens.motionFast(), curve: Curve.EaseOut })
          }
          .stateStyles({ pressed: this.pressed })
          .onClick(() => {
            if (this.onSelect) {
              this.onSelect(option.id);
            }
          })
        }, (option: SourceTabOption) => option.id)
      }
      .alignItems(VerticalAlign.Center)
      .padding({ left: DesignTokens.spaceGutter() - 8, right: DesignTokens.spaceGutter() - 8 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Start)
  }
}
