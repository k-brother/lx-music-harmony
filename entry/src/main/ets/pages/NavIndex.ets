// NavIndex - 主导航页面
// 使用 Navigation 组件 + NavPathStack 进行页面管理

import hilog from '@ohos.hilog';
import { HomePage } from './HomePage';
import { AboutView } from './Home/AboutView';
import { CustomSourceView } from './Home/CustomSourceView';
import { BoardDetailPage } from './BoardDetailPage';
import { SonglistDetailPage } from './SonglistDetailPage';
import { PlayDetailPage } from './PlayDetailPage';
import { SettingView } from './Home/SettingView';
import { navigationService, RouteName } from '../service/NavigationService';
import { DownloadPage } from './DownloadPage';
import { CommentPage } from './CommentPage';
import { HistoryListPage } from './HistoryListPage';
import { UserListsPage } from './UserListsPage';
import { LoveListPage } from './LoveListPage';
import { settingsService } from '../service/SettingsService';
import { on, EventTypes } from '../service/EventBus';
import { playerService } from '../service/PlayerService';


@Component
export struct NavIndex {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State navRefreshKey: number = 0;
  private navPathStack: NavPathStack = new NavPathStack();
  private startupPageApplied: boolean = false;
  private settingsUnsub: (() => void) | null = null;

  aboutToAppear() {
    // 将 NavPathStack 注入到 NavigationService
    navigationService.setNavPathStack(this.navPathStack);
    // 「设置 -> 启动页面」：设置是异步加载的，加载完成后应用一次
    this.settingsUnsub = on(EventTypes.SETTING_CHANGED, (): void => {
      this.applyStartupPageOnce();
    });
    this.applyStartupPageOnce();
  }

  aboutToDisappear() {
    if (this.settingsUnsub) {
      this.settingsUnsub();
      this.settingsUnsub = null;
    }
  }

  /** 启动页为播放页时，进入应用后自动打开播放详情 */
  private applyStartupPageOnce(): void {
    if (this.startupPageApplied) {
      return;
    }
    // 设置尚未加载完成时等待下一次通知
    if (AppStorage.get<boolean>('settingsReady') !== true) {
      return;
    }
    this.startupPageApplied = true;
    if (settingsService.get().startupPage !== 'playdetail') {
      return;
    }
    const current = playerService.getCurrentMusicInfo();
    if (!current || !current.name) {
      hilog.info(0x0001, 'NavIndex', 'Startup page is playdetail but no current song, stay on home');
      return;
    }
    hilog.info(0x0001, 'NavIndex', 'Startup page is playdetail, opening PlayDetailPage');
    navigationService.navigateTo(RouteName.PLAY_DETAIL);
  }

  build() {
    Navigation(this.navPathStack) {
      HomePage()
    }
    .hideTitleBar(true)
    .navDestination(this.buildRouteMap)
  }

  @Builder
  buildRouteMap(name: string) {
    if (name === 'home') {
      HomePage()
    } else if (name === 'playdetail') {
      NavDestination() {
        PlayDetailPage()
      }
      .hideTitleBar(true)
      .onReady((context: NavDestinationContext) => {
        const params = context.pathInfo.param as Record<string, object | string | number | boolean | undefined>;
        hilog.info(0x0001, 'NavIndex', 'PlayDetailPage onReady with params: %{public}s', JSON.stringify(params));
      })
    } else if (name === 'songlistdetail') {
      NavDestination() {
        SonglistDetailPage()
      }
      .hideTitleBar(true)
      .onReady((context: NavDestinationContext) => {
        const params = context.pathInfo.param as Record<string, object | string | number | boolean | undefined>;
        hilog.info(0x0001, 'NavIndex', 'SonglistDetailPage onReady with params: %{public}s', JSON.stringify(params));
      })
    } else if (name === 'boarddetail') {
      NavDestination() {
        BoardDetailPage()
      }
      .hideTitleBar(true)
      .onReady((context: NavDestinationContext) => {
        const params = context.pathInfo.param as Record<string, object | string | number | boolean | undefined>;
        hilog.info(0x0001, 'NavIndex', 'BoardDetailPage onReady with params: %{public}s', JSON.stringify(params));
      })
    } else if (name === 'customsource') {
      NavDestination() {
        CustomSourceView()
      }
      .hideTitleBar(true)
      .onReady((context: NavDestinationContext) => {
        const params = context.pathInfo.param as Record<string, object | string | number | boolean | undefined>;
        hilog.info(0x0001, 'NavIndex', 'CustomSourceView onReady with params: %{public}s', JSON.stringify(params));
      })
    } else if (name === 'about') {
      NavDestination() {
        AboutView()
      }
      .hideTitleBar(true)
      .onReady((context: NavDestinationContext) => {
        const params = context.pathInfo.param as Record<string, object | string | number | boolean | undefined>;
        hilog.info(0x0001, 'NavIndex', 'AboutView onReady with params: %{public}s', JSON.stringify(params));
      })
    } else if (name === 'settings') {
      NavDestination() {
        SettingView()
      }
      .onReady((context: NavDestinationContext) => {
        const params = context.pathInfo.param as Record<string, object | string | number | boolean | undefined>;
        hilog.info(0x0001, 'NavIndex', 'SettingView onReady with params: %{public}s', JSON.stringify(params));
      })
    } else if (name === 'download') {
      NavDestination() {
        DownloadPage()
      }
      .hideTitleBar(true)
      .onReady((context: NavDestinationContext) => {
        const params = context.pathInfo.param as Record<string, object | string | number | boolean | undefined>;
        hilog.info(0x0001, 'NavIndex', 'DownloadPage onReady with params: %{public}s', JSON.stringify(params));
      })
    } else if (name === 'comment') {
      NavDestination() {
        CommentPage()
      }
      .hideTitleBar(true)
      .onReady((context: NavDestinationContext) => {
        const params = context.pathInfo.param as Record<string, object | string | number | boolean | undefined>;
        hilog.info(0x0001, 'NavIndex', 'CommentPage onReady with params: %{public}s', JSON.stringify(params));
      })
    } else if (name === 'historylist') {
      NavDestination() {
        HistoryListPage()
      }
      .hideTitleBar(true)
      .onReady((context: NavDestinationContext) => {
        const params = context.pathInfo.param as Record<string, object | string | number | boolean | undefined>;
        hilog.info(0x0001, 'NavIndex', 'HistoryListPage onReady with params: %{public}s', JSON.stringify(params));
      })
    } else if (name === 'userlists') {
      NavDestination() {
        UserListsPage()
      }
      .hideTitleBar(true)
      .onReady((context: NavDestinationContext) => {
        const params = context.pathInfo.param as Record<string, object | string | number | boolean | undefined>;
        hilog.info(0x0001, 'NavIndex', 'UserListsPage onReady with params: %{public}s', JSON.stringify(params));
      })
    } else if (name === 'lovelist') {
      NavDestination() {
        LoveListPage()
      }
      .hideTitleBar(true)
      .onReady((context: NavDestinationContext) => {
        const params = context.pathInfo.param as Record<string, object | string | number | boolean | undefined>;
        hilog.info(0x0001, 'NavIndex', 'LoveListPage onReady with params: %{public}s', JSON.stringify(params));
      })
    }
  }
}
