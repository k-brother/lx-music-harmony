/**
 * 统一顶部栏（Page App Bar）
 *
 * 取代各页面手写的「Row + NavBackButton + Text + Blank」：
 * - 返回按钮统一 44vp 触控区与按压反馈
 * - 标题支持「常规 / 大标题」两种形态：大标题在滚动收缩时切到居中常规标题
 * - 右侧动作由调用方以 @BuilderParam 传入（ArkTS V1 里 @BuilderParam 可安全传递）
 * - 顶部安全区由窗口/系统统一内缩；本组件不再自行做安全区扩展（见 build 末尾说明）
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { navigationService } from '../../service/NavigationService';

@Component
export struct NavBar {
  @StorageProp('theme') theme: string = 'light';
  @Prop title: string = '';
  /** 大标题（左对齐、字号更大），滚动收缩后自动切回标题样式 */
  @Prop largeTitle: boolean = false;
  /** 是否显示返回按钮（根页面可关） */
  @Prop showBack: boolean = true;
  /** 滚动收缩态：true 时用常规标题 + 分隔线 */
  @Prop collapsed: boolean = false;
  /** 右侧动作区 */
  @BuilderParam trailing?: () => void;

  build() {
    Row() {
      if (this.showBack) {
        Stack() {
          Circle({ width: 34, height: 34 })
            .fill(DesignTokens.mutedFill(this.theme))
          Image($r('app.media.ic_pd_back'))
            .width(16)
            .height(16)
            .fillColor(DesignTokens.labelPrimary(this.theme))
        }
        .width(DesignTokens.touchTarget())
        .height(DesignTokens.touchTarget())
        .accessibilityText(t('a11y_back'))
        .onClick(() => {
          navigationService.back();
        })
      }

      if (this.largeTitle && !this.collapsed) {
        // 大标题形态：标题左对齐、字号更大（iOS Large Title 风格）
        Text(this.title)
          .fontSize(DesignTokens.fontDisplay())
          .fontWeight(FontWeight.Bold)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .margin({ left: this.showBack ? 8 : 0 })
      } else {
        Text(this.title)
          .fontSize(DesignTokens.fontHeadline())
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ left: 4, right: 4 })
      }

      if (this.trailing) {
        this.trailing()
      }
    }
    .width('100%')
    .height(this.largeTitle && !this.collapsed ? 64 : DesignTokens.navBarHeight())
    .padding({ left: 8, right: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(DesignTokens.chromeBar(this.theme))
    .border({ width: { bottom: this.collapsed ? 0.5 : 0 }, color: { bottom: DesignTokens.hairlineSeparator(this.theme) } })
    // 注意：这里不能再挂顶部安全区扩展。
    // 它与固定 height 同时使用时，背景会向状态栏方向多画一段、而内容仍按固定高度居中，
    // 结果标题与返回按钮落到页面背景上，被一条白/灰色带横切（真机上很明显的显示异常）。
    // 窗口本身不是全屏布局、顶部安全区由系统统一内缩，保持普通布局即可。
  }
}
