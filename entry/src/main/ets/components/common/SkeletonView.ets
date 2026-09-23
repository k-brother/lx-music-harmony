/**
 * 骨架屏组件 - 用于内容加载占位
 *
 * 说明：属性名不能叫 width/height/borderRadius —— 会与自定义组件的同名内置属性冲突
 * （ArkTS 会报 "Property 'width' ... not assignable to the same property in base type"），
 * 因此统一使用 boxWidth / boxHeight / boxRadius。
 */
import { DesignTokens } from '../../theme/DesignTokens';

@Component
export struct SkeletonView {
  @StorageProp('theme') theme: string = 'light';
  @Prop boxWidth: string | number = '100%';
  @Prop boxHeight: number = 16;
  @Prop boxRadius: number = 4;

  build() {
    Column() {
      Text('')
        .width('100%')
        .height(this.boxHeight)
        .backgroundColor(DesignTokens.mutedFill(this.theme))
        .borderRadius(this.boxRadius)
    }
    .width(this.boxWidth)
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
      SkeletonView({ boxWidth: 52, boxHeight: 52, boxRadius: 8 })

      Column() {
        SkeletonView({ boxWidth: '60%', boxHeight: 14, boxRadius: 4 })
        SkeletonView({ boxWidth: '40%', boxHeight: 12, boxRadius: 4 })
          .margin({ top: 8 })
      }
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(DesignTokens.card(this.theme))
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
      SkeletonView({ boxWidth: '100%', boxHeight: 120, boxRadius: 10 })
        .aspectRatio(1)

      Column() {
        SkeletonView({ boxWidth: '80%', boxHeight: 13, boxRadius: 4 })
        SkeletonView({ boxWidth: '50%', boxHeight: 11, boxRadius: 4 })
          .margin({ top: 6 })
      }
      .width('100%')
      .padding({ top: 8 })
    }
    .width('100%')
    .padding(8)
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(12)
  }
}

/**
 * 骨架屏评论项 - 评论页加载占位（头像 + 昵称行 + 两行正文 + 一行操作）
 */
@Component
export struct SkeletonCommentItem {
  @StorageProp('theme') theme: string = 'light';

  build() {
    Row() {
      Circle({ width: 36, height: 36 })
        .fill(DesignTokens.mutedFill(this.theme))

      Column() {
        SkeletonView({ boxWidth: '35%', boxHeight: 13, boxRadius: 4 })
        SkeletonView({ boxWidth: '92%', boxHeight: 13, boxRadius: 4 })
          .margin({ top: 10 })
        SkeletonView({ boxWidth: '70%', boxHeight: 13, boxRadius: 4 })
          .margin({ top: 6 })
        SkeletonView({ boxWidth: '22%', boxHeight: 11, boxRadius: 4 })
          .margin({ top: 10 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Top)
  }
}
