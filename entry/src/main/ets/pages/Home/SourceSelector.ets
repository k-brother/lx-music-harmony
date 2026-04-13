/**
 * 音乐源选择器组件
 */

class SourceSelectorItem {
  id: string;
  name: string;
  icon: string;

  constructor(id: string, name: string, icon: string) {
    this.id = id;
    this.name = name;
    this.icon = icon;
  }
}

@Component
export struct SourceSelector {
  @StorageProp('theme') theme: string = 'light';
  @Prop currentSource: string = 'kw';

  private sources: SourceSelectorItem[] = [
    new SourceSelectorItem('kw', '酷我', 'kw'),
    new SourceSelectorItem('tx', 'QQ', 'tx'),
    new SourceSelectorItem('wy', '网易', 'wy'),
    new SourceSelectorItem('kg', '酷狗', 'kg'),
    new SourceSelectorItem('mg', '咪咕', 'mg'),
  ];

  private onSourceChange: (sourceId: string) => void = () => {};

  setOnSourceChange(callback: (sourceId: string) => void): void {
    this.onSourceChange = callback;
  }

  build() {
    Row() {
      Scroll() {
        Row() {
          ForEach(this.sources, (source: SourceSelectorItem) => {
            Column() {
              // 选中指示器
              Row()
                .width(20)
                .height(3)
                .borderRadius(1.5)
                .backgroundColor(this.currentSource === source.id ? '#E63946' : 'transparent')
                .margin({ bottom: 6 })

              Text(source.name)
                .fontSize(this.currentSource === source.id ? 18 : 15)
                .fontColor(this.currentSource === source.id ? '#E63946' : (this.theme === 'dark' ? '#CCCCCC' : '#666666'))
                .fontWeight(this.currentSource === source.id ? FontWeight.Bold : FontWeight.Normal)
            }
            .padding({ left: 10, right: 10, top: 8, bottom: 8 })
            .onClick(() => {
              if (this.currentSource !== source.id) {
                this.onSourceChange(source.id);
              }
            })
          })
        }
        .padding({ left: 4 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
  }
}
