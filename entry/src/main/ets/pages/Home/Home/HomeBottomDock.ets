/**
 * 首页底部玻璃底舱（迷你播放条 + Tab 栏）
 *
 * 为什么单独成组件，而不是留在 HomePage 里当一个 @Builder：
 * ArkUI V1 的 @Builder **按参数缓存**——带参数的 @Builder 在"只有状态变化、参数没变"时
 * 不会被重建（`scripts/check_builder_state_args.py` 记的就是这一类坑）。
 * 真机上踩到的表现：滚动后迷你条已经收成 `compact` 形态（左侧出现「回到顶部」），
 * 但同一个 @Builder 里的 Tab 栏没收起来 —— 就是这里的 `collapsed` 没拿到新值。
 * 拆成组件后 `collapsed`/`activeIndex` 都是 @Prop，更新链路和其它组件一样可靠。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { t } from '../../../service/LocalizationService';
import { PlayerBar } from '../../../components/player/PlayerBar';
import { HomeBottomTabBar, type HomeTabItem } from './HomeBottomTabBar';

@Component
export struct HomeBottomDock {
  @StorageProp('theme') theme: string = 'light';
  @Prop tabs: HomeTabItem[] = [];
  @Prop activeIndex: number = 0;
  /**
   * 收拢态（内容已滚离顶部）：Tab 栏收起，迷你条左侧让出「回到顶部」动作位。
   * 与华为音乐滚动后的形态一致。
   */
  @Prop collapsed: boolean = false;
  onSelect?: (index: number) => void;
  /** 点左侧「房子」：展开底舱菜单（各 Tab 视图下次滚动时会再次收拢） */
  onRestore?: () => void;

  /**
   * 收拢态左侧的动作位：回到顶部。
   * 这是**渲染内容**的 @Builder（@BuilderParam 传的是"这个槽位画什么"）。
   */
  @Builder
  RestoreAction() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.house_fill'))
        .fontSize(DesignTokens.fontLarge())
        .fontColor([DesignTokens.labelSecondary(this.theme)])
    }
    .width(DesignTokens.miniActionSlot())
    .height(DesignTokens.miniActionSlot())
    .accessibilityText(t('dock_expand_menu'))
    .onClick((): void => {
      // 只复原底舱（不回顶部）：再滑动时内容继续上报"已滚离"，底舱会再次收拢
      if (this.onRestore) {
        this.onRestore();
      }
    })
  }

  build() {
    Column({ space: DesignTokens.spaceUnit() / 2 }) {
      PlayerBar({
        glass: true,
        compact: this.collapsed,
        leading: (): void => {
          this.RestoreAction();
        },
      })

      HomeBottomTabBar({
        tabs: this.tabs,
        activeIndex: this.activeIndex,
        vertical: false,
        collapsed: this.collapsed,
        onSelect: (index: number): void => {
          if (this.onSelect) {
            this.onSelect(index);
          }
        },
      })
    }
    .width('100%')
    .padding({
      left: DesignTokens.spaceGutter(),
      right: DesignTokens.spaceGutter(),
      // 贴屏幕底部放，只留系统手势条小横条的生存空间
      bottom: DesignTokens.dockBottomGap(),
    })
    // 底舱盒子延伸进底部安全区（否则它的"底"停在内容区底部，等于又空出一条安全区）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
