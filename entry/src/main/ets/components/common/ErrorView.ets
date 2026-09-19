/**
 * 通用错误/失败状态视图
 *
 * 纯展示组件（ArkTS V1 的 @Prop 不支持函数类型，回调由页面自己渲染按钮实现）。
 */
import { t } from '../../service/LocalizationService';
import { DesignTokens } from '../../theme/DesignTokens';

@Component
export struct ErrorView {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @Prop message: string = '';
  @Prop icon: string = '⚠️';

  build() {
    Column() {
      Text(this.icon)
        .fontSize(48)
        .opacity(0.55)

      Text(this.message.length > 0 ? this.message : t('load_failed'))
        .fontSize(14)
        .fontColor(DesignTokens.labelSecondary(this.theme))
        .margin({ top: 12 })
        .textAlign(TextAlign.Center)

    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
