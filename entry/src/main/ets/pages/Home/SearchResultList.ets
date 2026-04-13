/**
 * 搜索结果列表组件
 */

import { MusicSourceBadge } from '../../components/common/MusicSourceBadge';

interface SearchResultItem {
  id: string;
  name: string;
  singer: string;
  album: string;
  source: string;
  duration?: number;
}

@Component
export struct SearchResultList {
  @StorageProp('theme') theme: string = 'light';
  @Prop results: SearchResultItem[] = [];
  @Prop isLoading: boolean = false;

  private onItemClick: (item: SearchResultItem) => void = () => {};
  private onMoreClick: (item: SearchResultItem) => void = () => {};

  setCallbacks(
    onItemClick: (item: SearchResultItem) => void,
    onMoreClick: (item: SearchResultItem) => void
  ): void {
    this.onItemClick = onItemClick;
    this.onMoreClick = onMoreClick;
  }

  build() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color('#E63946')

          Text('搜索中...')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.results.length === 0) {
        Column() {
          Text('未找到相关结果')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.results, (item: SearchResultItem) => {
            ListItem() {
              Row() {
                // 序号
                Text(this.getIndex(item).toString())
                  .fontSize(12)
                  .fontColor('#999999')
                  .width(32)
                  .textAlign(TextAlign.Center)

                // 歌曲信息
                Column() {
                  Text(item.name)
                    .fontSize(15)
                    .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })

                  Row() {
                    Text(item.singer)
                      .fontSize(12)
                      .fontColor('#999999')
                      .maxLines(1)

                    if (item.album) {
                      Text(' - ' + item.album)
                        .fontSize(12)
                        .fontColor('#999999')
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }
                  }
                  .margin({ top: 2 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                // 时长
                if (item.duration && item.duration > 0) {
                  Text(this.formatDuration(item.duration))
                    .fontSize(11)
                    .fontColor('#999999')
                    .margin({ right: 8 })
                }

                // 音乐源标签
                MusicSourceBadge({ source: item.source, fontSize: 10 })
                  .margin({ right: 8 })

                // 更多按钮
                Image($r('sys.symbol.ellipsis_circle'))
                  .width(20)
                  .height(20)
                  .fillColor('#999999')
                  .onClick(() => {
                    this.onMoreClick(item);
                  })
              }
              .width('100%')
              .padding({ left: 8, right: 12, top: 12, bottom: 12 })
              .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
            }
            .onClick(() => {
              this.onItemClick(item);
            })
          })
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
        .divider({
          strokeWidth: 0.5,
          color: this.theme === 'dark' ? '#333333' : '#F0F0F0',
          startMargin: 40,
          endMargin: 0
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  private getIndex(item: SearchResultItem): number {
    return this.results.indexOf(item) + 1;
  }

  private formatDuration(seconds: number): string {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  }
}
