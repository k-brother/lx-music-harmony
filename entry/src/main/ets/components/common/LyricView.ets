/**
 * 歌词视图组件 - 支持高亮同步滚动
 */

@Component
export struct LyricView {
  @StorageProp('theme') theme: string = 'light';
  @Prop lyricLines: string[] = [];
  @Prop currentLyricIndex: number = -1;

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
      Scroll() {
        Column() {
          ForEach(this.lyricLines, (line: string, index: number) => {
            Text(line)
              .fontSize(index === this.currentLyricIndex ? 16 : 14)
              .fontColor(index === this.currentLyricIndex ? '#E63946' : (this.theme === 'dark' ? '#AAAAAA' : '#999999'))
              .fontWeight(index === this.currentLyricIndex ? FontWeight.Medium : FontWeight.Normal)
              .textAlign(TextAlign.Center)
              .width('100%')
              .padding({ top: 14, bottom: 14 })
              .animation({
                duration: 300,
              })
          })
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 20, bottom: 20 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }
}
