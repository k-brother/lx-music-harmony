/**
 * 通用加载视图组件
 */

@Component
export struct LoadingView {
  @Prop message: string = '加载中...';
  @Prop iconSize: number = 32;

  build() {
    Column() {
      LoadingProgress()
        .width(this.iconSize)
        .height(this.iconSize)
        .color('#E63946')

      Text(this.message)
        .fontSize(14)
        .fontColor('#999999')
        .margin({ top: 12 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
