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
import { navigationService, RouteName, NavigationParams } from '../service/NavigationService';
import { DownloadPage } from './DownloadPage';
import { CommentPage } from './CommentPage';
import { HistoryListPage } from './HistoryListPage';


@Component
export struct NavIndex {
  @StorageProp('theme') theme: string = 'light';
  private navPathStack: NavPathStack = new NavPathStack();

  aboutToAppear() {
    // 将 NavPathStack 注入到 NavigationService
    navigationService.setNavPathStack(this.navPathStack);
  }

  build() {
    Navigation(this.navPathStack) {
      // 首页
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
    }
  }
}
