// NavIndex - 主导航页面
// 使用 Navigation 组件 + NavPathStack 进行页面管理

import { hilog } from '@kit.PerformanceAnalysisKit';
import { HomePage } from './HomePage';
import { AboutView } from './Home/AboutView';
import { CustomSourceView } from './Home/CustomSourceView';
import { BoardDetailPage } from './BoardDetailPage';
import { SonglistDetailPage } from './SonglistDetailPage';
import { PlayDetailPage } from './PlayDetailPage';
import { SettingView } from './Home/SettingView';
import { navigationService, RouteName } from '../service/NavigationService';
import { CommentPage } from './CommentPage';
import { HistoryListPage } from './HistoryListPage';
import { UserListsPage } from './UserListsPage';
import { LoveListPage } from './LoveListPage';
import { LocalMusicPage } from './LocalMusicPage';
import { LogPage } from './LogPage';
import { PactDialog } from '../components/common/PactDialog';
import { setAppUiContext } from '../service/UiContext';
import { settingsService } from '../service/SettingsService';
import { on, EventTypes } from '../service/EventBus';
import type { PlaybackErrorData } from '../service/EventBus';
import { appToast } from '../service/DialogService';
import { t, tf } from '../service/LocalizationService';
import { playerService } from '../service/PlayerService';
import { SheetHost } from '../components/ui/SheetHost';
import { AppDestination } from '../components/ui/AppDestination';
import { DesignTokens } from '../theme/DesignTokens';


@Component
export struct NavIndex {
  private navPathStack: NavPathStack = new NavPathStack();
  private startupPageApplied: boolean = false;
  private settingsUnsub: (() => void) | null = null;
  private playbackErrorUnsub: (() => void) | null = null;
  /** 首次启动未同意许可协议时全屏拦截 */
  @State showPact: boolean = false;

  aboutToAppear() {
    // 将 NavPathStack 注入到 NavigationService
    navigationService.setNavPathStack(this.navPathStack);
    // 注入全局 UIContext：DialogService（appConfirm/appActionMenu/appToast）依赖它，
    // 这样各页面不必逐层传 context
    setAppUiContext(this.getUIContext());
    // 「设置 -> 启动页面」：设置是异步加载的，加载完成后应用一次
    this.settingsUnsub = on(EventTypes.SETTING_CHANGED, (): void => {
      this.syncPactState();
      this.applyStartupPageOnce();
    });
    // 播放出错：在应用根提示一次（已跳过 / 已停止），用户不会遇到「莫名没声音」
    this.playbackErrorUnsub = on(EventTypes.PLAYBACK_ERROR, (data?: Object): void => {
      const info = data as PlaybackErrorData;
      if (!info) {
        return;
      }
      appToast(info.skipped
        ? tf('playback_error_skipped', [info.title])
        : t('playback_error_stopped'));
    });
    this.syncPactState();
    this.applyStartupPageOnce();
  }

  /** 设置就绪后决定是否拦截：未同意协议则显示首启协议弹层 */
  private syncPactState(): void {
    if (AppStorage.get<boolean>('settingsReady') !== true) {
      return;
    }
    if (!settingsService.get().agreedPact) {
      this.showPact = true;
    }
  }

  aboutToDisappear() {
    if (this.settingsUnsub) {
      this.settingsUnsub();
      this.settingsUnsub = null;
    }
    if (this.playbackErrorUnsub) {
      this.playbackErrorUnsub();
      this.playbackErrorUnsub = null;
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
    Stack() {
      Navigation(this.navPathStack) {
        HomePage()
      }
      .hideTitleBar(true)
      .navDestination(this.buildRouteMap)

      // 全局面板宿主：命令式面板（设置项选择/输入等）统一挂在这里，避免被 Scroll 裁剪
      SheetHost()

      // 首次启动：未同意许可协议前全屏拦截（对齐安卓版 PactModal）
      if (this.showPact) {
        Column() {
          PactDialog({
            readonlyMode: false,
            visible: true,
            onClose: (): void => {
              this.showPact = false;
            },
          })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(DesignTokens.maskColor())
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildRouteMap(name: string) {
    if (name === 'home') {
      HomePage()
    } else if (name === 'playdetail') {
      AppDestination({ routeName: 'PlayDetailPage' }) {
        PlayDetailPage()
      }
    } else if (name === 'songlistdetail') {
      AppDestination({ routeName: 'SonglistDetailPage' }) {
        SonglistDetailPage()
      }
    } else if (name === 'boarddetail') {
      AppDestination({ routeName: 'BoardDetailPage' }) {
        BoardDetailPage()
      }
    } else if (name === 'customsource') {
      AppDestination({ routeName: 'CustomSourceView' }) {
        CustomSourceView()
      }
    } else if (name === 'about') {
      AppDestination({ routeName: 'AboutView' }) {
        AboutView()
      }
    } else if (name === 'settings') {
      AppDestination({ routeName: 'SettingView' }) {
        SettingView()
      }
    } else if (name === 'comment') {
      AppDestination({ routeName: 'CommentPage' }) {
        CommentPage()
      }
    } else if (name === 'historylist') {
      AppDestination({ routeName: 'HistoryListPage' }) {
        HistoryListPage()
      }
    } else if (name === 'userlists') {
      AppDestination({ routeName: 'UserListsPage' }) {
        UserListsPage()
      }
    } else if (name === 'localmusic') {
      AppDestination({ routeName: 'LocalMusicPage' }) {
        LocalMusicPage()
      }
    } else if (name === 'lovelist') {
      AppDestination({ routeName: 'LoveListPage' }) {
        LoveListPage()
      }
    } else if (name === 'logs') {
      AppDestination({ routeName: 'LogPage' }) {
        LogPage()
      }
    }
  }
}
