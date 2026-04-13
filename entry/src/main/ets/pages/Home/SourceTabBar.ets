/**
 * 音乐源TabBar组件
 */

class SourceTabItem {
  id: string;
  name: string;

  constructor(id: string, name: string) {
    this.id = id;
    this.name = name;
  }
}

@Component
export struct SourceTabBar {
  @StorageProp('theme') theme: string = 'light';
  @Prop currentSource: string = 'kw';
  @Prop sources: SourceTabItem[] = [
    new SourceTabItem('kw', '酷我'),
    new SourceTabItem('tx', 'QQ'),
    new SourceTabItem('wy', '网易'),
    new SourceTabItem('kg', '酷狗'),
    new SourceTabItem('mg', '咪咕'),
  ];

  build() {
    Scroll() {
      Row() {
        ForEach(this.sources, (source: SourceTabItem) => {
          Text(source.name)
            .fontSize(this.currentSource === source.id ? 20 : 17)
            .fontColor(this.currentSource === source.id ? '#E63946' : (this.theme === 'dark' ? '#CCCCCC' : '#666666'))
            .fontWeight(this.currentSource === source.id ? FontWeight.Bold : FontWeight.Normal)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ right: 6 })
        })
      }
      .padding({ left: 4 })
      .alignItems(VerticalAlign.Center)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .layoutWeight(1)
    .align(Alignment.Start)
  }
}
