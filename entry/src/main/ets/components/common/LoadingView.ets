/**
 * 通用加载视图组件
 */
import { t } from '../../service/LocalizationService';

@Component
export struct LoadingView {
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @Prop message: string = '';
  @Prop iconSize: number = 32;

  build() {
    Column() {
      LoadingProgress()
        .width(this.iconSize)
        .height(this.iconSize)
        .color('#E63946')

      Text(this.message ? this.message : t('loading'))
        .fontSize(14)
        .fontColor('#999999')
        .margin({ top: 12 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
