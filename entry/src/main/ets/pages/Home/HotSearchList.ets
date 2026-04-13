/**
 * 热搜列表组件
 */

import type { HotSearchItem } from '../../core/search/search';

@Component
export struct HotSearchList {
  @StorageProp('theme') theme: string = 'light';
  @Prop hotSearchList: HotSearchItem[] = [];

  build() {
    Column() {
      // 热搜标题
      Row() {
        Text('热门搜索')
          .fontSize(15)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding({ left: 16, top: 16, bottom: 8 })

      // 热搜列表
      List() {
        ForEach(this.hotSearchList, (item: HotSearchItem) => {
          ListItem() {
            Row() {
              Text((item.index).toString())
                .fontSize(14)
                .fontColor(item.index <= 3 ? '#E63946' : '#999999')
                .fontWeight(item.index <= 3 ? FontWeight.Bold : FontWeight.Normal)
                .width(32)

              Text(item.title)
                .fontSize(14)
                .fontColor(this.theme === 'dark' ? '#CCCCCC' : '#666666')
                .layoutWeight(1)

              Image($r('sys.symbol.chevron_right'))
                .width(16)
                .height(16)
                .fillColor('#999999')
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
    }
    .width('100%')
    .layoutWeight(1)
  }
}
