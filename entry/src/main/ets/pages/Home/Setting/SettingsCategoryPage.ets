/**
 * 设置二级页（分类页）
 *
 * 设置首页点分类入口进来，这里只做两件事：
 * 1. 统一的顶部栏（与设置首页、其它二级页同一个 NavBar）+ 页面级安全区/一多适配；
 * 2. 按分类路由渲染对应的分组组件——分组组件本身就是原来挂首页的那几个，
 *    没有搬家成本，改某个设置项仍然只需要看它自己那 100~200 行。
 *
 * 分类目录（标题 / 说明 / 有哪些分类）在 SettingsCatalog，这里不重复写文案。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { Breakpoints } from '../../../theme/Breakpoints';
import { NavBar } from '../../../components/ui/NavBar';
import { RouteName } from '../../../service/NavigationService';
import { settingsCategoryTitle } from './SettingsCatalog';
import { BasicSection } from './BasicSection';
import { PlaybackSection } from './PlaybackSection';
import { DownloadSection } from './DownloadSection';
import { SearchSection } from './SearchSection';
import { ListSection } from './ListSection';
import { StorageSection } from './StorageSection';
import { BackupSection } from './BackupSection';
import { SyncSection } from './SyncSection';
import { AppearanceSection } from './AppearanceSection';
import { DesktopLyricSection } from './DesktopLyricSection';
import { LiveViewSection } from './LiveViewSection';
import { CustomSourceSection } from './CustomSourceSection';
import { SourceSection } from './SourceSection';
import { AboutSection } from './AboutSection';

@Component
export struct SettingsCategoryPage {
  @StorageProp('theme') theme: string = 'light';
  /** 一多：窗口宽度（vp），大屏时内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
  /** 语言版本号：顶部栏标题来自目录文案，切语言后要跟着重渲染 */
  @StorageProp('langVersion') langVersion: number = 0;
  /** 分类标识：路由枚举值，由 NavIndex 按路由显式传入 */
  @Prop category: string = '';

  /** 顶部栏标题：与首页那一行完全同名（都来自 SettingsCatalog） */
  private title(): string {
    return settingsCategoryTitle(this.category as RouteName);
  }

  build() {
    Column() {
      NavBar({ title: this.title() })

      Scroll() {
        Column() {
          this.Sections()
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
      // Scroll 默认 align 是 Center：设置项少的分类页会被整体居中，上下各留一大片空白
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
    // 顶部/底部安全区都由页面自己绘制（深色模式下底部手势区不能透出系统白底）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /**
   * 分类 → 分组组件。
   * 「音源」把内置音源管理与自定义源放一页：它们本来就该一起找；
   * 其余分类一一对应，若某天一个分类要放多个分组，在这里并排即可。
   */
  @Builder
  Sections() {
    if (this.category === RouteName.SETTINGS_BASIC) {
      BasicSection()
    } else if (this.category === RouteName.SETTINGS_PLAYBACK) {
      PlaybackSection()
    } else if (this.category === RouteName.SETTINGS_LYRIC) {
      DesktopLyricSection()
      LiveViewSection()
    } else if (this.category === RouteName.SETTINGS_SOURCE) {
      SourceSection()
      CustomSourceSection()
    } else if (this.category === RouteName.SETTINGS_STORAGE) {
      DownloadSection()
      StorageSection()
    } else if (this.category === RouteName.SETTINGS_APPEARANCE) {
      AppearanceSection()
    } else if (this.category === RouteName.SETTINGS_SEARCH_LIST) {
      SearchSection()
      ListSection()
    } else if (this.category === RouteName.SETTINGS_BACKUP) {
      BackupSection()
      SyncSection()
    } else if (this.category === RouteName.SETTINGS_ABOUT) {
      AboutSection()
    }
  }
}
