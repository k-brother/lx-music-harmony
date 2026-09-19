/**
 * 通用空状态视图
 *
 * 纯展示组件（ArkTS V1 的 @Prop 不支持函数类型，行动按钮由页面自己渲染）。
 * 颜色走 DesignTokens，深浅色一致。
 */
import { t } from '../../service/LocalizationService';
import { DesignTokens } from '../../theme/DesignTokens';

@Component
export struct EmptyView {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @Prop message: string = '';
  @Prop icon: string = '🎵';
  @Prop iconSize: number = 56;

  build() {
    Column() {
      Text(this.icon)
        .fontSize(this.iconSize)
        .opacity(0.55)

      Text(this.message.length > 0 ? this.message : t('no_data'))
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
