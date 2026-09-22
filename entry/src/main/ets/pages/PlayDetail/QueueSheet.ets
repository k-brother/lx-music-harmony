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
import { appActionMenu } from '../../service/DialogService';
import type { SongInfo } from '../../service/PlayerService';

@Component
export struct QueueSheet {
  @StorageProp('theme') theme: string = 'light';
  @Link visible: boolean;
  @Prop queue: SongInfo[] = [];
  @Prop currentIndex: number = -1;
  onPick?: (index: number) => void;
  /** 拖动排序（长按行拖动） */
  onMove?: (from: number, to: number) => void;
  /** 长按菜单里选择「从队列移除」 */
  onRemove?: (index: number) => void;

  /** 正在被拖动的行下标（-1 表示没有拖拽） */
  @State dragFromIndex: number = -1;

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
    .gesture(LongPressGesture().onAction(() => {
      void this.openRowMenu(index);
    }))
  }

  /** 长按行：与主流播放器一致，给出「从队列移除」 */
  private async openRowMenu(index: number): Promise<void> {
    if (!this.onRemove) {
      return;
    }
    const song = this.queue[index];
    if (!song) {
      return;
    }
    const picked = await appActionMenu(`${song.title} - ${song.artist}`, [
      t('play_queue_remove'),
    ]);
    if (picked === 0) {
      this.visible = false;
      this.onRemove(index);
    }
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
          // 拖拽排序：把被拖动的行放到目标行位置
          .onDragStart(() => {
            this.dragFromIndex = index;
            return this.DragPreview(song);
          })
          .onDrop((_event: DragEvent, _extraParams: string) => {
            const from = this.dragFromIndex;
            this.dragFromIndex = -1;
            if (from >= 0 && from !== index && this.onMove) {
              this.onMove(from, index);
            }
          })
        }, (song: SongInfo, index: number) => `${song.id}_${index}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
  }

  /** 拖拽跟随手指时显示的小卡片 */
  @Builder
  DragPreview(song: SongInfo) {
    Row() {
      Text(song.title)
        .fontSize(15)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(10)
    .shadow(DesignTokens.cardShadow(this.theme))
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
