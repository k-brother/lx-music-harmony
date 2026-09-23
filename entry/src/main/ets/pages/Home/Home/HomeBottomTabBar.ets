/**
 * 首页导航栏（手机底部 Tab / 平板与 PC 左侧导航栏）
 *
 * 统一底部导航：图标 + 文案，选中态用强调色并带轻微放大动效（商业化 App 的常见手感），
 * 选中切换时图标填充色与文字颜色一起变化，避免"只有文字变色"的廉价感。
 *
 * 一多：宽屏（平板横屏 / PC）用竖排侧边导航更符合大屏使用习惯（QQ 音乐、Apple Music 的
 * PC 版都是左栏导航），因此同一个组件按 `vertical` 出两种形态，动作与选中态共用一份逻辑。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { hapticService } from '../../../service/HapticService';

export interface HomeTabItem {
  idx: number;
  icon: Resource;
  label: string;
}

@Component
export struct HomeBottomTabBar {
  @StorageProp('theme') theme: string = 'light';
  @Prop tabs: HomeTabItem[] = [];
  @Prop activeIndex: number = 0;
  /** 宽屏：竖排在左侧 */
  @Prop vertical: boolean = false;
  onSelect?: (index: number) => void;

  @Builder
  TabItem(tab: HomeTabItem) {
    Column({ space: 2 }) {
      // 系统符号必须用 SymbolGlyph 渲染（Image 加载 sys.symbol.* 会空白）
      SymbolGlyph(tab.icon)
        .fontSize(DesignTokens.iconMd() + 4)
        .fontColor([this.activeIndex === tab.idx ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme)])
        .scale({ x: this.activeIndex === tab.idx ? 1.08 : 1, y: this.activeIndex === tab.idx ? 1.08 : 1 })
        .animation({ duration: DesignTokens.motionFast(), curve: Curve.EaseOut })
      Text(tab.label)
        .fontSize(DesignTokens.fontBody())
        .fontColor(this.activeIndex === tab.idx ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme))
        .fontWeight(this.activeIndex === tab.idx ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
    }
    .layoutWeight(1)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      // 切换 Tab 给一次「选择」触感：商业化 App 的基本手感
      if (this.activeIndex !== tab.idx) {
        hapticService.selection();
      }
      if (this.onSelect) {
        this.onSelect(tab.idx);
      }
    })
  }

  build() {
    if (this.vertical) {
      // 侧边导航：通栏高度，条目等分竖排；右侧一条分隔线与内容区分开
      Column({ space: 4 }) {
        ForEach(this.tabs, (tab: HomeTabItem) => {
          this.TabItem(tab)
        }, (tab: HomeTabItem) => tab.idx.toString())
      }
      .width(96)
      .height('100%')
      .padding({ top: 12, bottom: 12 })
      .backgroundColor(DesignTokens.tabBarBg(this.theme))
      .border({ width: { right: 0.33 }, color: DesignTokens.hairlineSeparator(this.theme) })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    } else {
      Column() {
        Row() {
          ForEach(this.tabs, (tab: HomeTabItem) => {
            this.TabItem(tab)
          }, (tab: HomeTabItem) => tab.idx.toString())
        }
        .width('100%')
        .height(44)
        .padding({ top: 4, bottom: 4 })
        .border({ width: { top: 0.33 }, color: DesignTokens.hairlineSeparator(this.theme) })

        // 底部安全区占位（沉浸式导航栏）
        Blank()
          .width('100%')
          .height(6)
      }
      .width('100%')
      .backgroundColor(DesignTokens.tabBarBg(this.theme))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
  }
}
