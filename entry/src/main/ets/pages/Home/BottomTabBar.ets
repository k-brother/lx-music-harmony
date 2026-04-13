/**
 * 底部TabBar组件
 */

@Component
export struct BottomTabBar {
  @StorageProp('theme') theme: string = 'light';
  @Prop currentTab: number = 0;
  @Prop tabs: string[] = ['歌单', '排行榜', '下载', '我的'];

  build() {
    Row() {
      ForEach(this.tabs, (tab: string, index: number) => {
        Column() {
          Text(tab)
            .fontSize(this.currentTab === index ? 14 : 12)
            .fontColor(this.currentTab === index ? '#E63946' : (this.theme === 'dark' ? '#AAAAAA' : '#999999'))
            .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
        }
        .layoutWeight(1)
        .height(50)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      })
    }
    .width('100%')
    .height(50)
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
    .border({ width: { top: 0.5 }, color: this.theme === 'dark' ? '#333333' : '#E0E0E0' })
  }
}
