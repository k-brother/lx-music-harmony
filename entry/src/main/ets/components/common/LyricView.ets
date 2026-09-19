/**
 * 歌词视图组件 - 支持高亮同步滚动
 */

import { t } from '../../service/LocalizationService';
import { DesignTokens } from '../../theme/DesignTokens';

@Component
export struct LyricView {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('showAnimation') showAnimation: boolean = true;
  @Prop lyricLines: string[] = [];
  @Prop secondaryLyricLines: string[] = [];
  @Prop @Watch('onCurrentLyricIndexChanged') currentLyricIndex: number = -1;
  private lyricScroller: Scroller = new Scroller();
  private lineHeight: number = 62;
  private pendingScrollTimer: number = -1;
  private alive: boolean = false;

  aboutToAppear(): void {
    this.alive = true;
  }

  aboutToDisappear(): void {
    this.alive = false;
    if (this.pendingScrollTimer !== -1) {
      clearTimeout(this.pendingScrollTimer);
      this.pendingScrollTimer = -1;
    }
  }

  private onCurrentLyricIndexChanged(): void {
    if (this.currentLyricIndex < 0 || this.lyricLines.length === 0) {
      return;
    }
    if (this.pendingScrollTimer !== -1) {
      clearTimeout(this.pendingScrollTimer);
      this.pendingScrollTimer = -1;
    }
    this.pendingScrollTimer = setTimeout(() => {
      if (!this.alive || this.currentLyricIndex < 0 || this.currentLyricIndex >= this.lyricLines.length) {
        this.pendingScrollTimer = -1;
        return;
      }
      const targetOffset = Math.max(0, this.currentLyricIndex * this.lineHeight - this.lineHeight * 3);
      try {
        this.lyricScroller.scrollTo({
          xOffset: 0,
          yOffset: targetOffset,
          animation: true,
        });
      } catch (_err) {
        // Ignore single scroll failure to avoid UI crash loops.
      }
      this.pendingScrollTimer = -1;
    }, 60);
  }

  /** 当前行取主题强调色，保证跟随主题/深浅色 */
  private accentColor(): string {
    return DesignTokens.accent();
  }

  /**
   * 非当前行按与当前行的距离递减透明度：离得越远越淡，
   * 让视线自然聚焦在当前句上（主流歌词动效的基本做法）。
   */
  private lineOpacity(index: number): number {
    if (this.currentLyricIndex < 0 || index === this.currentLyricIndex) {
      return 1;
    }
    const distance: number = Math.abs(index - this.currentLyricIndex);
    if (distance === 1) {
      return 0.72;
    }
    if (distance === 2) {
      return 0.5;
    }
    return 0.32;
  }

  build() {
    if (this.lyricLines.length === 0) {
      Column() {
        Text(t('no_lyric'))
          .fontSize(14)
          .fontColor(this.theme === 'dark' ? '#8A8A93' : '#9A9AA0')
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      Scroll(this.lyricScroller) {
        Column() {
          ForEach(this.lyricLines, (line: string, index: number) => {
            Column({ space: 2 }) {
              Text(line)
                // 当前行放大加粗、非当前行降对比，是最主流的歌词视觉层次
                .fontSize(index === this.currentLyricIndex ? 20 : 15)
                .fontColor(index === this.currentLyricIndex
                  ? this.accentColor()
                  : (this.theme === 'dark' ? '#8A8A93' : '#8E8E93'))
                .fontWeight(index === this.currentLyricIndex ? FontWeight.Bold : FontWeight.Normal)
                .opacity(this.lineOpacity(index))
                .textAlign(TextAlign.Center)
                .width('100%')
                .maxLines(1)
              if (index < this.secondaryLyricLines.length && this.secondaryLyricLines[index] && this.secondaryLyricLines[index].length > 0) {
                Text(this.secondaryLyricLines[index])
                  .fontSize(index === this.currentLyricIndex ? 13 : 11)
                  .fontColor(index === this.currentLyricIndex
                    ? (this.theme === 'dark' ? '#D0A0A5' : '#B75A62')
                    : (this.theme === 'dark' ? '#6E6E78' : '#A0A0AA'))
                  .opacity(this.lineOpacity(index))
                  .textAlign(TextAlign.Center)
                  .width('100%')
                  .maxLines(1)
              }
            }
            .width('100%')
            .height(this.lineHeight)
            .padding({ left: 8, right: 8 })
            .justifyContent(FlexAlign.Center)
            .animation({
              // 「设置 -> 外观 -> 动画效果」关闭时不做滚动动画
              duration: this.showAnimation ? 300 : 0,
            })
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 120, bottom: 120 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
    }
  }
}
