import { t } from '../../service/LocalizationService';
/**
 * 操作表组件 - 从底部弹出的操作列表
 */

@Component
export struct ActionSheet {
  @Prop title: string = '';
  @Prop actions: string[] = [];
  @Prop show: boolean = false;
  @Prop cancelText: string = t('cancel');

  private onActionClick: (index: number) => void = () => {};
  private onCancel: () => void = () => {};

  setCallbacks(onAction: (index: number) => void, onCancel: () => void): void {
    this.onActionClick = onAction;
    this.onCancel = onCancel;
  }

  build() {
    if (this.show) {
      Stack() {
        // 遮罩层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.4)')
          .onClick(() => {
            this.onCancel();
          })

        // 操作表
        Column() {
          // 标题
          if (this.title) {
            Text(this.title)
              .fontSize(14)
              .fontColor('#666666')
              .padding({ top: 16, bottom: 12, left: 20, right: 20 })
          }

          // 操作列表
          Column() {
            ForEach(this.actions, (action: string, index: number) => {
              Column() {
                Text(action)
                  .fontSize(16)
                  .fontColor('#333333')
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 14, bottom: 14 })
              }
              .width('100%')
              .onClick(() => {
                this.onActionClick(index);
              })
            })
          }
          .backgroundColor('#FFFFFF')
          .borderRadius(12)

          // 取消按钮
          Column() {
            Text(this.cancelText)
              .fontSize(16)
              .fontColor('#333333')
              .fontWeight(FontWeight.Medium)
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 14, bottom: 14 })
          }
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .margin({ top: 8 })
          .onClick(() => {
            this.onCancel();
          })
        }
        .width('100%')
        .padding({ left: 8, right: 8, bottom: 20 })
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
    }
  }
}
