import { t } from '../../service/LocalizationService';
/**
 * 确认对话框组件
 */

@Component
export struct ConfirmDialog {
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @Prop title: string = '';
  @Prop message: string = '';
  @Prop confirmText: string = '';
  @Prop cancelText: string = '';
  @Prop show: boolean = false;

  private onConfirm: () => void = () => {};
  private onCancel: () => void = () => {};

  setCallbacks(onConfirm: () => void, onCancel: () => void): void {
    this.onConfirm = onConfirm;
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

        // 对话框
        Column() {
          // 标题
          Text(this.title)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor('#333333')
            .padding({ top: 20, bottom: 12 })

          // 消息
          Text(this.message)
            .fontSize(14)
            .fontColor('#666666')
            .padding({ left: 20, right: 20, bottom: 20 })
            .textAlign(TextAlign.Center)

          // 分隔线
          Row() {
            Column()
              .height(0.5)
              .width('50%')
              .backgroundColor('#E0E0E0')
          }

          // 按钮行
          Row() {
            // 取消按钮
            Column() {
              Text(this.cancelText || t('cancel'))
                .fontSize(16)
                .fontColor('#666666')
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 14, bottom: 14 })
            }
            .width('50%')
            .onClick(() => {
              this.onCancel();
            })

            // 分隔线
            Column() {
              Text('')
                .width(0.5)
                .height('100%')
                .backgroundColor('#E0E0E0')
            }

            // 确认按钮
            Column() {
              Text(this.confirmText || t('confirm'))
                .fontSize(16)
                .fontColor('#E63946')
                .fontWeight(FontWeight.Medium)
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 14, bottom: 14 })
            }
            .width('50%')
            .onClick(() => {
              this.onConfirm();
            })
          }
          .height(48)
          .width('100%')
        }
        .width('70%')
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
    }
  }
}
