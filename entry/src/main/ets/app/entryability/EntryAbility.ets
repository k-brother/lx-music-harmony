// 应用入口能力 - 对应 src/app.ts
// 负责应用初始化和窗口管理

import UIAbility from '@ohos.app.ability.UIAbility';
import { BusinessError } from '@kit.BasicServicesKit';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import { stateEvent } from '../../event/StateEvent';
import { appEvent } from '../../event/AppEvent';
import { playerService } from '../../service/PlayerService';
import { initAllServices } from '../../service/index';
import { storageService } from '../../service/StorageService';
import { initWindowService } from '../../service/WindowService';
import { runBootstrapAfterServices } from '../bootstrap/AppBootstrap';

const TAG = 'EntryAbility';
const DOMAIN = 0x0001;

// 全局LX状态接口 - 对应 global.lx
export interface LX {
  fontSize: number;
  playerStatus: PlayerStatus;
  isPlayedStop: boolean;
  playerTrackId: string | null;
  gettingUrlId: string | null;
  playInfo: PlayInfo;
  homePagerIdle: boolean;
}

// 播放器状态
interface PlayerStatus {
  isIniting: boolean;
  isInitialized: boolean;
  isRegisteredService: boolean;
}

// 播放信息
interface PlayInfo {
  isPlaying: boolean;
  status: string;
  currentTrack: object | null;
}

// 全局App对象
interface GlobalApp {
  app_event: object; // 使用具体的事件类型
  state_event: object; // 使用具体的事件类型
}

// 全局变量声明
let lx: LX;
let globalApp: GlobalApp;

export default class EntryAbility extends UIAbility {
  onCreate(want: object, launchParam: object): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onCreate');
    // 初始化全局状态
    this.initGlobalState();
    // 初始化应用（异步，传入 want 供深链等后续扩展）
    void this.initApp(want);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onDestroy');
    // 销毁播放器
    playerService.destroy();
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(DOMAIN, TAG, 'EntryAbility onWindowStageCreate');

    // 先加载内容，再设置窗口属性
    try {
      windowStage.loadContent('pages/Index', (err: BusinessError) => {
        if (err.code !== 0) {
          hilog.error(DOMAIN, TAG, 'Failed to load content: code=%{public}d, msg=%{public}s', err.code, err.message || 'unknown');
          this.loadContentWithRetry(windowStage, 'pages/Index', 0);
          return;
        }
        hilog.info(DOMAIN, TAG, 'Succeeded in loading content');

        // 初始化窗口服务
        initWindowService(windowStage).then(() => {
          hilog.info(DOMAIN, TAG, 'WindowService initialized');
        }).catch((windowErr: Error) => {
          hilog.error(DOMAIN, TAG, 'Failed to init WindowService: %{public}s', JSON.stringify(windowErr));
        });
      });
    } catch (loadEx) {
      hilog.error(DOMAIN, TAG, 'Error loading content: %{public}s', JSON.stringify(loadEx));
      this.loadContentWithRetry(windowStage, 'pages/Index', 0);
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onBackground');
  }

  // 初始化全局状态 - 对应 src/config/globalData.ts
  private initGlobalState(): void {
    hilog.info(DOMAIN, TAG, 'Initializing global state...');

    // 创建全局状态 - 对应 global.lx
    lx = {
      fontSize: 1,
      playerStatus: {
        isIniting: false,
        isInitialized: false,
        isRegisteredService: false,
      },
      isPlayedStop: false,
      playerTrackId: null,
      gettingUrlId: null,
      playInfo: {
        isPlaying: false,
        status: 'idle',
        currentTrack: null,
      },
      homePagerIdle: true,
    };

    // 创建全局App对象 - 对应 global.app_event 和 global.state_event
    globalApp = {
      app_event: appEvent,
      state_event: stateEvent,
    };

    hilog.info(DOMAIN, TAG, 'Global state initialized');
  }

  // 重试加载内容
  private loadContentWithRetry(windowStage: window.WindowStage, page: string, retryCount: number): void {
    if (retryCount >= 3) {
      hilog.error(DOMAIN, TAG, 'Failed to load content after %{public}d retries', retryCount);
      return;
    }

    setTimeout(() => {
      windowStage.loadContent(page, (err: BusinessError) => {
        if (err.code !== 0) {
          hilog.error(DOMAIN, TAG, 'Retry %{public}d failed to load content: code=%{public}d, %{public}s',
            retryCount + 1, err.code, err.message || 'unknown');
          this.loadContentWithRetry(windowStage, page, retryCount + 1);
          return;
        }
        hilog.info(DOMAIN, TAG, 'Succeeded in loading content on retry %{public}d', retryCount + 1);
        initWindowService(windowStage).then(() => {
          hilog.info(DOMAIN, TAG, 'WindowService initialized after retry');
        }).catch((windowErr: Error) => {
          hilog.error(DOMAIN, TAG, 'Failed to init WindowService after retry: %{public}s', JSON.stringify(windowErr));
        });
      });
    }, 1000 * (retryCount + 1)); // 1s, 2s, 3s 重试间隔
  }

  // 初始化应用 - 对应 src/app.ts 的初始化逻辑
  private async initApp(want?: object): Promise<void> {
    hilog.info(DOMAIN, TAG, 'Initializing LX Music app...');

    try {
      // 设置存储服务上下文
      storageService.setContext(this.context);

      // 初始化所有服务（存储、主题、列表、播放器）
      await initAllServices();

      await runBootstrapAfterServices(want);

      // 延迟初始化播放器，避免窗口未准备好导致的错误
      setTimeout(async () => {
        try {
          // 更新播放选项
          await playerService.updateOptions();

          // 设置音量
          await playerService.setVolume(1.0);

          // 设置播放速率
          await playerService.setPlaybackRate(1.0);

          // 更新全局状态
          lx.playerStatus.isInitialized = true;

          hilog.info(DOMAIN, TAG, 'LX Music app initialized successfully');
        } catch (playerErr) {
          hilog.error(DOMAIN, TAG, 'Failed to initialize player: ' + JSON.stringify(playerErr));
        }
      }, 1000);

    } catch (appErr) {
      hilog.error(DOMAIN, TAG, 'Failed to initialize app: ' + JSON.stringify(appErr));
    }
  }
}
