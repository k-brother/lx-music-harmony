/**
 * 歌词视图组件 - 支持高亮同步滚动
 */

@Component
export struct LyricView {
  @StorageProp('theme') theme: string = 'light';
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

  build() {
    if (this.lyricLines.length === 0) {
      Column() {
        Text('暂无歌词')
          .fontSize(14)
          .fontColor('#999999')
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
                .fontSize(index === this.currentLyricIndex ? 17 : 14)
                .fontColor(index === this.currentLyricIndex ? '#E63946' : (this.theme === 'dark' ? '#D6D6DB' : '#555555'))
                .fontWeight(index === this.currentLyricIndex ? FontWeight.Medium : FontWeight.Normal)
                .textAlign(TextAlign.Center)
                .width('100%')
                .maxLines(1)
              if (index < this.secondaryLyricLines.length && this.secondaryLyricLines[index] && this.secondaryLyricLines[index].length > 0) {
                Text(this.secondaryLyricLines[index])
                  .fontSize(index === this.currentLyricIndex ? 12 : 11)
                  .fontColor(index === this.currentLyricIndex ? (this.theme === 'dark' ? '#D0A0A5' : '#B75A62') : (this.theme === 'dark' ? '#8A8A93' : '#A0A0AA'))
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
              duration: 300,
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
