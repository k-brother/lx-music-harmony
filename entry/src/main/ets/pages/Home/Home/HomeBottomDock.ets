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
import { createDockGlassMaterial } from '../../../theme/GlassMaterial';
import { uiMaterial } from '@kit.ArkUI';

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

  /** 房子按钮的系统沉浸材质（与播放条各是一片玻璃，各自独立） */
  private houseMaterial: uiMaterial.Material | undefined = createDockGlassMaterial();

  /**
   * 收拢态左侧的「房子」：**独立一个圆形容器**（与右侧播放条的圆角矩形同一行）。
   * 直径取 `dockHouseSize()`（= 行高），所以它出现/消失都不会把这一行撑高或压扁。
   */
  @Builder
  HouseButton() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.house_fill'))
        // 用强调色：它是收拢态下的主入口
        .fontSize(DesignTokens.fontLarge())
        .fontColor([DesignTokens.accent()])
    }
    .width(DesignTokens.dockHouseSize())
    .height(DesignTokens.dockHouseSize())
    .borderRadius(DesignTokens.dockHouseSize() / 2)
    .backgroundColor(DesignTokens.glassFill(this.theme))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, {
      adaptiveColor: AdaptiveColor.AVERAGE,
      scale: 1,
    })
    .border({ width: 0.5, color: DesignTokens.glassStroke(this.theme) })
    .shadow(DesignTokens.floatingShadow())
    .systemMaterial(this.houseMaterial)
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
      // 迷你行：收拢态 = [房子圆] + [播放圆角矩形]；展开态 = 整条播放圆角矩形。
      // 房子用"宽度 0 ↔ 直径"动画进出（不是 if 分支：滚动回调里没有 animateTo 上下文，
      // 分支切换会跳），高度始终等于行高，所以这一行不会因为收拢而变高。
      Row({ space: DesignTokens.dockRowGap() }) {
        Column() {
          if (this.collapsed) {
            this.HouseButton()
          }
        }
        .width(this.collapsed ? DesignTokens.dockHouseSize() : 0)
        .opacity(this.collapsed ? 1 : 0)
        .clip(true)
        .animation({ duration: 220, curve: Curve.EaseOut })

        Column() {
          PlayerBar({ glass: true })
        }
        .layoutWeight(1)
      }
      .width('100%')

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
