/**
 * 骨架屏组件 - 用于内容加载占位
 */

@Component
export struct SkeletonView {
  @StorageProp('theme') theme: string = 'light';
  @Prop width: string | number = '100%';
  @Prop height: number = 16;
  @Prop borderRadius: number = 4;

  build() {
    Column() {
      Text('')
        .width('100%')
        .height(this.height)
        .backgroundColor(this.theme === 'dark' ? '#2C2C2C' : '#E8E8E8')
        .borderRadius(this.borderRadius)
    }
    .width(this.width)
    .clip(true)
  }
}

/**
 * 骨架屏列表项 - 用于歌曲/歌单列表加载占位
 */
@Component
export struct SkeletonListItem {
  @StorageProp('theme') theme: string = 'light';

  build() {
    Row() {
      // 封面占位
      SkeletonView({ width: 52, height: 52, borderRadius: 8 })

      // 文字占位
      Column() {
        SkeletonView({ width: '60%', height: 14, borderRadius: 4 })
        SkeletonView({ width: '40%', height: 12, borderRadius: 4 })
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
  }
}

/**
 * 骨架屏网格项 - 用于歌单网格加载占位
 */
@Component
export struct SkeletonGridItem {
  @StorageProp('theme') theme: string = 'light';

  build() {
    Column() {
      // 封面占位
      SkeletonView({ width: '100%', height: 120, borderRadius: 10 })
        .aspectRatio(1)

      // 文字占位
      Column() {
        SkeletonView({ width: '80%', height: 13, borderRadius: 4 })
        SkeletonView({ width: '50%', height: 11, borderRadius: 4 })
          .margin({ top: 6 })
      }
      .width('100%')
      .padding({ top: 8 })
    }
    .width('100%')
    .padding(8)
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
    .borderRadius(12)
  }
}
