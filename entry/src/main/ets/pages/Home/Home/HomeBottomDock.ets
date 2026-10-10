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
  /** 内容是否正在滚动（utils/ScrollActivity 写入）：滚动时底舱轻微收一点 */
  @StorageProp('contentScrolling') contentScrolling: boolean = false;

  /**
   * 收拢态左侧的动作位：回到顶部。
   * 这是**渲染内容**的 @Builder（@BuilderParam 传的是"这个槽位画什么"）。
   */
  @Builder
  RestoreAction() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.house_fill'))
        // 比 Tab 图标大一档、用强调色：它是收拢态下的主入口，太小会显得没分量
        .fontSize(DesignTokens.fontDisplay())
        .fontColor([DesignTokens.accent()])
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
    // 两行是**两个独立的圆角容器**（对齐华为音乐的底舱）：材质与圆角各自带，
    // 中间留 `dockRowGap()` 的缝 —— 缝本身就是分界，不用再画分隔线。
    Column({ space: DesignTokens.dockRowGap() }) {
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
      // 左右留白比普通页面大：底舱是浮在内容上的玻璃，贴边会显得糊在边框上
      left: DesignTokens.dockSideMargin(),
      right: DesignTokens.dockSideMargin(),
      // 贴屏幕底部放，只留系统手势条小横条的生存空间
      bottom: DesignTokens.dockBottomGap(),
    })
    // 材质随滑动"呼吸"：滚动时收一点点，停手回弹
    .scale({
      x: this.contentScrolling ? 0.985 : 1,
      y: this.contentScrolling ? 0.985 : 1,
    })
    .animation({ duration: 200, curve: Curve.EaseOut })
    // 注意：安全区扩展不在这里做。窗口内容区本身已避开底部安全区，扩展必须挂在
    // HomePage 那一层 Stack 上，底舱才真正落到屏幕底部（挂在这里无效，会多出一条空带）。
  }
}
