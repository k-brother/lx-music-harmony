/**
 * 歌曲列表项组件
 */

import { MusicSourceBadge } from './MusicSourceBadge';

@Component
export struct SongListItem {
  @Prop name: string;
  @Prop singer: string;
  @Prop album: string = '';
  @Prop source: string = '';
  @Prop isPlaying: boolean = false;
  @Prop showSourceBadge: boolean = true;

  build() {
    Row() {
      // 歌曲信息
      Column() {
        Text(this.name)
          .fontSize(15)
          .fontColor(this.isPlaying ? '#E63946' : '#333333')
          .maxLines(1)

        Text(this.singer + (this.album ? ' - ' + this.album : ''))
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 播放指示器
      if (this.isPlaying) {
        Image($r('sys.symbol.play'))
          .width(20)
          .height(20)
          .fillColor('#E63946')
          .margin({ right: 8 })
      }

      // 音乐源标签
      if (this.showSourceBadge && this.source) {
        MusicSourceBadge({ source: this.source, fontSize: 10 })
          .margin({ right: 8 })
      }

      // 更多按钮
      Image($r('sys.symbol.ellipsis_circle'))
        .width(20)
        .height(20)
        .fillColor('#999999')
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
  }
}
