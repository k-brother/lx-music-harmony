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
  /** 图标用系统符号，避免 emoji 在不同字体/系统上观感不一致 */
  @Prop iconRes: Resource = $r('sys.symbol.music_note_list');
  @Prop iconSize: number = 56;

  build() {
    Column() {
      // 系统符号必须用 SymbolGlyph 渲染：Image 无法加载 sys.symbol.* 资源
      SymbolGlyph(this.iconRes)
        .fontSize(this.iconSize)
        .fontColor([DesignTokens.labelTertiary(this.theme)])
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
