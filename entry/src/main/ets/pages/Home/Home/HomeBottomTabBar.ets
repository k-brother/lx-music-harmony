/**
 * 首页导航栏（手机底部玻璃底舱 / 平板与 PC 左侧导航栏）
 *
 * 手机形态对齐系统音乐 App 的"液态玻璃"底舱：
 * - 半透明玻璃材质（`DesignTokens.glassFill` + `backgroundBlurStyle`），下面滚动的内容透得出来；
 * - 选中态是一枚**会飞的胶囊**（`position` + `.animation`，切换时从上一项滑到当前项），
 *   而不是把胶囊硬塞进每个条目里（那种做法只能淡入淡出，没有"液体"感）；
 * - 内容滚动时整体轻微收一点（`scale`），停手回弹 —— 材质跟着滑动"呼吸"。
 *
 * 大屏形态（`vertical`）保持竖排在左侧的不透明侧栏：侧栏旁边就是列表，做成玻璃反而看不清。
 * 一多的两种形态共用同一份选中逻辑，只是外观分支不同。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { hapticService } from '../../../service/HapticService';
import { createDockGlassMaterial } from '../../../theme/GlassMaterial';
import { uiMaterial } from '@kit.ArkUI';

export interface HomeTabItem {
  idx: number;
  icon: Resource;
  label: string;
}

/** 滚动时的收放比例：这是个比例不是尺寸，不受平台密度影响，所以留在组件里 */
const SCROLL_PRESS_SCALE: number = 0.985;

@Component
export struct HomeBottomTabBar {
  @StorageProp('theme') theme: string = 'light';
  /** 一多：窗口宽度（vp）——横向展开动画需要"展开后的确定宽度"，不能用百分比（会被压扁） */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
  @Prop tabs: HomeTabItem[] = [];
  @Prop activeIndex: number = 0;
  /** 宽屏：竖排在左侧（不透明侧栏） */
  @Prop vertical: boolean = false;
  /**
   * 收拢态（内容已滚离顶部）：高度收成 0 并淡出，让底舱只剩迷你播放条一条。
   * 用高度/透明度动画而不是 if 分支插入删除 —— 后者需要 animateTo 包裹才会动，
   * 而这里的触发来自滚动回调（不在用户点按的动画上下文里），分支切换会直接"跳"。
   */
  @Prop collapsed: boolean = false;
  onSelect?: (index: number) => void;

  /** 系统沉浸材质（鸿蒙版"液态玻璃"）：不支持时为 undefined，走自绘玻璃回退 */
  private material: uiMaterial.Material | undefined = createDockGlassMaterial();

  /** 条目行实测宽度：选中胶囊按它算位置（不猜像素，也不依赖百分比定位） */
  @State rowWidth: number = 0;

  private tabCount(): number {
    return Math.max(1, this.tabs.length);
  }

  /** 单个条目宽度 */
  private cellWidth(): number {
    return this.rowWidth / this.tabCount();
  }

  private capsuleWidth(): number {
    return Math.max(0, this.cellWidth() - DesignTokens.tabCapsuleInset() * 2);
  }

  private capsuleX(): number {
    return this.activeIndex * this.cellWidth() + DesignTokens.tabCapsuleInset();
  }

  private capsuleY(): number {
    return (DesignTokens.tabBarHeight() - DesignTokens.tabCapsuleHeight()) / 2;
  }

  /**
   * 展开后的内容宽度（= 屏幕宽 - 底舱左右留白）。
   * 收拢/展开用"容器宽度动画 + clip"做**从左向右拉开**的效果：内容必须保持这个定宽，
   * 否则条目会跟着容器一起被压扁（用百分比宽度就会这样）。
   */
  private contentWidth(): number {
    return Math.max(0, this.windowWidthVp - DesignTokens.dockSideMargin() * 2);
  }

  private onRowResize(area: Area): void {
    const width: Length = area.width;
    if (typeof width === 'number' && width > 0 && width !== this.rowWidth) {
      this.rowWidth = width;
    }
  }

  @Builder
  TabItem(tab: HomeTabItem) {
    Column({ space: 2 }) {
      // 系统符号必须用 SymbolGlyph 渲染（Image 加载 sys.symbol.* 会空白）
      SymbolGlyph(tab.icon)
        .fontSize(DesignTokens.tabIconSize())
        .fontColor([this.activeIndex === tab.idx ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme)])
        .scale({ x: this.activeIndex === tab.idx ? 1.08 : 1, y: this.activeIndex === tab.idx ? 1.08 : 1 })
        .animation({ duration: DesignTokens.motionFast(), curve: Curve.EaseOut })
      Text(tab.label)
        .fontSize(DesignTokens.fontCaption())
        .fontColor(this.activeIndex === tab.idx ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme))
        .fontWeight(this.activeIndex === tab.idx ? FontWeight.Medium : FontWeight.Normal)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(DesignTokens.tabItemHeight())
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

  /** 选中胶囊：位置随 activeIndex 动画移动（"会飞"的部分） */
  @Builder
  ActiveCapsule() {
    if (this.rowWidth > 0) {
      Column()
        .width(this.capsuleWidth())
        .height(DesignTokens.tabCapsuleHeight())
        .position({ x: this.capsuleX(), y: this.capsuleY() })
        .backgroundColor(DesignTokens.accentSoft(this.theme))
        .borderRadius(DesignTokens.tabCapsuleHeight() / 2)
        .animation({ duration: 260, curve: Curve.EaseOut })
    }
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
      // 底部玻璃底舱：左右/底部留白由 HomePage 的底舱统一给，这里只管玻璃本体
      Stack({ alignContent: Alignment.TopStart }) {
        this.ActiveCapsule()

        Row() {
          ForEach(this.tabs, (tab: HomeTabItem) => {
            this.TabItem(tab)
          }, (tab: HomeTabItem) => tab.idx.toString())
        }
        // 定宽：容器裁剪时内容不会被压扁（横向展开的关键）
        .width(this.contentWidth())
        .height(DesignTokens.tabBarHeight())
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          this.onRowResize(newArea);
        })
      }
      // 从左向右"拉开"：宽度 0 ↔ 展开宽度（以左端为锚点），高度同时补上必需的行高
      .width(this.collapsed ? 0 : this.contentWidth())
      .height(this.collapsed ? 0 : DesignTokens.tabBarHeight())
      .clip(true)
      .scale({ x: this.collapsed ? 0.9 : 1, y: this.collapsed ? 0.9 : 1 })
      .opacity(this.collapsed ? 0 : 1)
      .hitTestBehavior(this.collapsed ? HitTestMode.None : HitTestMode.Default)
      .animation({ duration: 240, curve: Curve.EaseOut })
      // 自己就是一片圆角玻璃（与迷你条是两个独立容器，中间留缝分界）
      .backgroundColor(DesignTokens.glassFill(this.theme))
      // adaptiveColor.AVERAGE：材质取背后内容的平均色，透过去不会发灰
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, {
        adaptiveColor: AdaptiveColor.AVERAGE,
        scale: 1,
      })
      .borderRadius(DesignTokens.dockRadius())
      .border({ width: 0.5, color: DesignTokens.glassStroke(this.theme) })
      .shadow(DesignTokens.floatingShadow())
      // 系统沉浸材质（含交互形变与光感反馈）；设备不支持时为 undefined，走上面的自绘回退
      .systemMaterial(this.material)
    }
  }
}
