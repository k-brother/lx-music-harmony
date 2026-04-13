/**
 * 通用错误视图组件
 * 注意：重试逻辑由父组件通过条件渲染处理
 */

@Component
export struct ErrorView {
  @Prop message: string = '加载失败';
  @Prop showRetry: boolean = true;

  build() {
    Column() {
      Text('⚠️')
        .fontSize(50)
        .fontColor('#CCCCCC')

      Text(this.message)
        .fontSize(14)
        .fontColor('#999999')
        .margin({ top: 12 })

      if (this.showRetry) {
        Text('点击重试')
          .fontSize(14)
          .fontColor('#E63946')
          .margin({ top: 16 })
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
