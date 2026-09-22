/**
 * 首页底部 Tab 栏
 *
 * 统一底部导航：图标 + 文案，选中态用强调色并带轻微放大动效（商业化 App 的常见手感），
 * 选中切换时图标填充色与文字颜色一起变化，避免"只有文字变色"的廉价感。
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
        .fontSize(14)
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
