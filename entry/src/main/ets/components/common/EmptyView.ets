/**
 * 通用空状态视图组件
 */

@Component
export struct EmptyView {
  @Prop message: string = '暂无数据';
  @Prop icon: string = '🎵';
  @Prop iconSize: number = 60;

  build() {
    Column() {
      Text(this.icon)
        .fontSize(this.iconSize)
        .fontColor('#CCCCCC')

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
