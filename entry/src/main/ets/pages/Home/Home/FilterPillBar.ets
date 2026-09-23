/**
 * 通用胶囊筛选条（首页歌单 Tab / 排行榜 Tab 共用）
 *
 * 横向可滚动，吸顶时由页面负责固定位置。
 * 之前各 Tab 各写一套筛选按钮，选中态、间距、圆角都不一致；
 * 这里抽出组件，并用 variant 保留两种既有的选中样式：
 *  - soft：浅色强调底 + 强调色文字（排行榜分类/榜单）
 *  - solid：强调色实底 + 白字（强调「当前筛选」的强对比场景）
 */
import { DesignTokens } from '../../../theme/DesignTokens';

export interface FilterPillOption {
  id: string;
  label: string;
}

@Component
export struct FilterPillBar {
  @StorageProp('theme') theme: string = 'light';
  @Prop options: FilterPillOption[] = [];
  @Prop activeId: string = '';
  /** 选中样式：soft（默认）/ solid */
  @Prop variant: string = 'soft';
  /** 顶部/底部内边距（不同 Tab 间距不同） */
  @Prop topPadding: number = 6;
  @Prop bottomPadding: number = 6;
  /** 胶囊间距 */
  @Prop spacing: number = 6;
  onSelect?: (id: string) => void;

  @Styles
  pressed() {
    .opacity(DesignTokens.pressedOpacity())
  }

  private isSolid(): boolean {
    return this.variant === 'solid';
  }

  private activeBg(): string {
    return this.isSolid() ? DesignTokens.accent() : DesignTokens.accentSoft(this.theme);
  }

  private activeFg(): string {
    return this.isSolid() ? DesignTokens.onAccent() : DesignTokens.accent();
  }

  /** 实底胶囊需要更饱满的内边距，浅底胶囊留白略小（对齐两类既有设计） */
  private padH(): number {
    return this.isSolid() ? 14 : 10;
  }

  private padV(): number {
    return this.isSolid() ? 7 : 6;
  }

  build() {
    Scroll() {
      Row({ space: this.spacing }) {
        ForEach(this.options, (option: FilterPillOption) => {
          Text(option.label)
            .fontSize(DesignTokens.fontCallout())
            .fontColor(this.activeId === option.id ? this.activeFg() : DesignTokens.labelSecondary(this.theme))
            .fontWeight(this.activeId === option.id ? FontWeight.Medium : FontWeight.Normal)
            .padding({ left: this.padH(), right: this.padH(), top: this.padV(), bottom: this.padV() })
            .backgroundColor(this.activeId === option.id ? this.activeBg() : Color.Transparent)
            .borderRadius(DesignTokens.radiusPill())
            .maxLines(1)
            .stateStyles({ pressed: this.pressed })
            .onClick(() => {
              if (this.onSelect && this.activeId !== option.id) {
                this.onSelect(option.id);
              }
            })
        }, (option: FilterPillOption) => option.id)
      }
      .padding({
        left: DesignTokens.spaceGutter(),
        right: DesignTokens.spaceGutter(),
        top: this.topPadding,
        bottom: this.bottomPadding,
      })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .align(Alignment.Start)
  }
}
