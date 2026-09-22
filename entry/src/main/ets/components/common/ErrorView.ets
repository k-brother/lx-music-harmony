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
  /** 图标用系统符号（本 SDK 无警告类符号，用 xmark 表达失败） */
  @Prop iconRes: Resource = $r('sys.symbol.xmark');

  build() {
    Column() {
      Image(this.iconRes)
        .width(44)
        .height(44)
        .fillColor(DesignTokens.labelTertiary(this.theme))
        .opacity(0.6)

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
