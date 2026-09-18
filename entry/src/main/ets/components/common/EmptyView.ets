/**
 * 通用空状态视图组件
 */
import { t } from '../../service/LocalizationService';

@Component
export struct EmptyView {
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @Prop message: string = '';
  @Prop icon: string = '🎵';
  @Prop iconSize: number = 60;

  build() {
    Column() {
      Text(this.icon)
        .fontSize(this.iconSize)
        .fontColor('#CCCCCC')

      Text(this.message ? this.message : t('no_data'))
        .fontSize(14)
        .fontColor('#999999')
        .margin({ top: 12 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
