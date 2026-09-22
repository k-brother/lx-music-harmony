/**
 * 播放队列面板
 *
 * 展示当前队列并高亮正在播放的一首，点击任意一首直接切歌。
 * 覆盖安卓 mini 播放条长按 `jumpListPosition()` 的意图，
 * 且对搜索结果、本地音乐这类"没有所属列表 id"的队列同样可用。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t, tf } from '../../service/LocalizationService';
import { BottomSheet } from '../../components/ui/BottomSheet';
import type { SongInfo } from '../../service/PlayerService';

@Component
export struct QueueSheet {
  @StorageProp('theme') theme: string = 'light';
  @Link visible: boolean;
  @Prop queue: SongInfo[] = [];
  @Prop currentIndex: number = -1;
  onPick?: (index: number) => void;

  @Builder
  Row(song: SongInfo, index: number) {
    Row() {
      Text((index + 1).toString())
        .fontSize(DesignTokens.fontCaption())
        .fontColor(index === this.currentIndex ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme))
        .width(24)
        .textAlign(TextAlign.Center)

      Column({ space: 2 }) {
        Text(song.title)
          .fontSize(15)
          .fontColor(index === this.currentIndex ? DesignTokens.accent() : DesignTokens.labelPrimary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(song.artist)
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 8 })

      if (index === this.currentIndex) {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(17)
          .fontColor([DesignTokens.accent()])
      }
    }
    .width('100%')
    .height(DesignTokens.rowHeightTwoLine())
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.visible = false;
      if (this.onPick) {
        this.onPick(index);
      }
    })
  }

  @Builder
  Content() {
    if (this.queue.length === 0) {
      Text(t('list_empty'))
        .fontSize(14)
        .fontColor(DesignTokens.labelSecondary(this.theme))
        .padding({ top: 20, bottom: 20 })
    } else {
      List() {
        ForEach(this.queue, (song: SongInfo, index: number) => {
          ListItem() {
            this.Row(song, index)
          }
        }, (song: SongInfo, index: number) => `${song.id}_${index}`)
      }
      .width('100%')
      .height(380)
      .scrollBar(BarState.Off)
    }
  }

  build() {
    BottomSheet({
      visible: $visible,
      title: tf('play_queue_count', [this.queue.length.toString()]),
      sheetSize: 'large',
      content: (): void => {
        this.Content();
      },
    })
  }
}
