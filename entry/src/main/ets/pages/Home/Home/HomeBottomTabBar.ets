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

/** 底部 Tab 栏高度（玻璃胶囊按它居中）——44 与系统底部导航一致，再高就"压屏"了 */
const TAB_BAR_HEIGHT: number = 44;
/** 单个条目高度（图标 + 文案）：留 40 保证点按手感，条高 44 只多出 2vp 余量 */
const TAB_ITEM_HEIGHT: number = 40;
/** 选中胶囊相对条目的内缩（左右各缩一点，胶囊不会顶着相邻条目） */
const CAPSULE_INSET: number = 6;
/** 选中胶囊高度 */
const CAPSULE_HEIGHT: number = 30;
/** 滚动时的收放比例（小到能感觉到"回应"，又不会明显跳） */
const SCROLL_PRESS_SCALE: number = 0.985;

@Component
export struct HomeBottomTabBar {
  @StorageProp('theme') theme: string = 'light';
  /** 内容是否正在滚动（utils/ScrollActivity 写入）：滚动时底舱轻微收一点 */
  @StorageProp('contentScrolling') contentScrolling: boolean = false;
  @Prop tabs: HomeTabItem[] = [];
  @Prop activeIndex: number = 0;
  /** 宽屏：竖排在左侧（不透明侧栏） */
  @Prop vertical: boolean = false;
  onSelect?: (index: number) => void;

  /** 条目行实测宽度：选中胶囊按它算位置（不猜像素，也不依赖百分比定位） */
  @State rowWidth: number = 0;
  /**
   * 系统沉浸材质（鸿蒙版"液态玻璃"）。
   * 不支持时是 undefined：下面自绘的玻璃底色 + 模糊 + 描边就是回退，两者不冲突
   * （支持时以系统材质为准，系统材质会覆盖组件的底色/描边/阴影）。
   */
  private material: uiMaterial.Material | undefined = createDockGlassMaterial();

  private tabCount(): number {
    return Math.max(1, this.tabs.length);
  }

  /** 单个条目宽度 */
  private cellWidth(): number {
    return this.rowWidth / this.tabCount();
  }

  private capsuleWidth(): number {
    return Math.max(0, this.cellWidth() - CAPSULE_INSET * 2);
  }

  private capsuleX(): number {
    return this.activeIndex * this.cellWidth() + CAPSULE_INSET;
  }

  private capsuleY(): number {
    return (TAB_BAR_HEIGHT - CAPSULE_HEIGHT) / 2;
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
        // 底部导航图标按平台规范取 20vp（iconMd 是正文图标尺寸，这里加一档）
        .fontSize(DesignTokens.iconMd() + 4)
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
    .height(TAB_ITEM_HEIGHT)
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
        .height(CAPSULE_HEIGHT)
        .position({ x: this.capsuleX(), y: this.capsuleY() })
        .backgroundColor(DesignTokens.accentSoft(this.theme))
        .borderRadius(CAPSULE_HEIGHT / 2)
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
        .width('100%')
        .height(TAB_BAR_HEIGHT)
        .onAreaChange((_oldArea: Area, newArea: Area): void => {
          this.onRowResize(newArea);
        })
      }
      .width('100%')
      .height(TAB_BAR_HEIGHT)
      // 材质随滑动"呼吸"：滚动时收一点点，停手回弹
      .scale({
        x: this.contentScrolling ? SCROLL_PRESS_SCALE : 1,
        y: this.contentScrolling ? SCROLL_PRESS_SCALE : 1,
      })
      .animation({ duration: 200, curve: Curve.EaseOut })
      .backgroundColor(DesignTokens.glassFill(this.theme))
      // adaptiveColor.AVERAGE：材质取背后内容的平均色，透过去不会发灰
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK, {
        adaptiveColor: AdaptiveColor.AVERAGE,
        scale: 1,
      })
      .borderRadius(DesignTokens.radiusCard())
      .border({ width: 0.5, color: DesignTokens.glassStroke(this.theme) })
      .shadow(DesignTokens.floatingShadow())
      // 系统沉浸材质（含交互形变与光感反馈）；设备不支持时为 undefined，走上面的自绘回退
      .systemMaterial(this.material)
    }
  }
}
