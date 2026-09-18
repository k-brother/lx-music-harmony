/**
 * 通用错误视图组件
 * 注意：重试逻辑由父组件通过条件渲染处理
 */
import { t } from '../../service/LocalizationService';

@Component
export struct ErrorView {
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @Prop message: string = '';
  @Prop showRetry: boolean = true;

  build() {
    Column() {
      Text('⚠️')
        .fontSize(50)
        .fontColor('#CCCCCC')

      Text(this.message ? this.message : t('load_failed'))
        .fontSize(14)
        .fontColor('#999999')
        .margin({ top: 12 })

      if (this.showRetry) {
        Text(t('retry'))
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
