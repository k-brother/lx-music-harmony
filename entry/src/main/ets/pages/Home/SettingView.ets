/**
 * 设置页（编排层）
 *
 * 2971 行 → ~120 行：页面只负责「按顺序摆放分组组件 + 统一外边距」，
 * 每个分组的视觉/状态/交互/持久化都在 pages/Home/Setting/ 下的组件里，
 * 分组自身通过 SettingsSection（分组卡片）与 DialogService（确认/菜单/提示）统一呈现。
 *
 * 之所以这样拆：
 * - 原来 40 个 @State + 12 个构造器 + 备份导入导出混在一个页面里，改一处要读整页；
 * - 现在「某个设置不生效」只需要看对应分组那 100~200 行，定位成本低一个数量级；
 * - 新增设置项 = 加一个分组组件或往现有分组的 items 里加一项，不会互相踩状态。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { NavBar } from '../../components/ui/NavBar';
import { t } from '../../service/LocalizationService';
import { Breakpoints } from '../../theme/Breakpoints';
import { BasicSection } from './Setting/BasicSection';
import { PlaybackSection } from './Setting/PlaybackSection';
import { DownloadSection } from './Setting/DownloadSection';
import { SearchSection } from './Setting/SearchSection';
import { ListSection } from './Setting/ListSection';
import { StorageSection } from './Setting/StorageSection';
import { BackupSection } from './Setting/BackupSection';
import { SyncSection } from './Setting/SyncSection';
import { AppearanceSection } from './Setting/AppearanceSection';
import { DesktopLyricSection } from './Setting/DesktopLyricSection';
import { LiveViewSection } from './Setting/LiveViewSection';
import { CustomSourceSection } from './Setting/CustomSourceSection';
import { SourceSection } from './Setting/SourceSection';
import { AboutSection } from './Setting/AboutSection';

@Component
export struct SettingView {
  @StorageProp('theme') theme: string = 'light';
  /** 一多：窗口宽度（vp），大屏时内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
  /** 一多：断点（lg 时设置分组分两列，避免单列拉得过长） */
  @StorageProp('breakpoint') breakpoint: string = 'sm';

  /** 左列分组（常用项） */
  @Builder
  LeftSections() {
    BasicSection()
    PlaybackSection()
    DownloadSection()
    SearchSection()
    ListSection()
    StorageSection()
  }

  /** 右列分组（进阶项） */
  @Builder
  RightSections() {
    BackupSection()
    SyncSection()
    AppearanceSection()
    DesktopLyricSection()
    LiveViewSection()
    SourceSection()
    CustomSourceSection()
    AboutSection()
  }

  build() {
    Column() {
      // 统一顶部栏：与其它二级页同一套（返回 + 居中标题 + 沉浸式安全区）
      NavBar({ title: t('settings_title') })

      Scroll() {
        Column() {
          // 平板横屏 / PC：分成两列，一屏能看到更多分组（与 iPad 版设置页的密度接近）
        if (Breakpoints.isLarge(this.breakpoint)) {
          Row({ space: 0 }) {
            Column() {
              this.LeftSections()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Column() {
              this.RightSections()
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        } else {
          Column() {
            this.LeftSections()
            this.RightSections()
          }
          .width('100%')
        }
      }
      .width('100%')
      // 分组卡片左右留白（8pt 网格）；大屏额外居中，避免卡片被拉满整屏
        .padding({
          left: DesignTokens.spaceGutter() + Breakpoints.contentInset(this.windowWidthVp),
          right: DesignTokens.spaceGutter() + Breakpoints.contentInset(this.windowWidthVp),
          bottom: 28,
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
    // 顶部/底部安全区都由页面自己绘制（深色模式下底部手势区不能透出系统白底）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
