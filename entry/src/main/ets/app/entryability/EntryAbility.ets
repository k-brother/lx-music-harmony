// 应用入口能力 - 对应 src/app.ts
// 负责应用初始化和窗口管理

import UIAbility from '@ohos.app.ability.UIAbility';
import type { Configuration } from '@ohos.app.ability.Configuration';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import { stateEvent } from '../../event/StateEvent';
import { appEvent } from '../../event/AppEvent';
import { playerService } from '../../service/PlayerService';
import { initAllServices, initImageCache } from '../../service/index';
import { storageService } from '../../service/StorageService';
import { settingsService } from '../../service/SettingsService';
import { initWindowService } from '../../service/WindowService';
import { runBootstrapAfterServices } from '../bootstrap/AppBootstrap';
import { initLocalization } from '../../service/LocalizationService';
import { setQuickJSContext } from '../../core/napi/napi_quickjs';
import { backgroundRunningManager } from '../../service/BackgroundRunningManager';
import { mediaSaveService } from '../../service/MediaSaveService';
import { localMusicService } from '../../service/LocalMusicService';
import { logService } from '../../service/LogService';
import { setSystemDarkMode, applyAutoTheme } from '../../service/ThemeService';

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
    // 初始化后台任务管理器（传入 context 用于后续长时任务申请）
    backgroundRunningManager.init(this.context);
    // 初始化应用（异步，传入 want 供深链等后续扩展）
    void this.initApp(want);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'EntryAbility onDestroy');
    // 退出前落盘进度
    playerService.saveProgress();
    // 销毁播放器
    playerService.destroy();
    // 清理后台任务资源
    void backgroundRunningManager.destroy();
  }

  /**
   * 系统配置变化（深浅色/语言/字体等）：
   * 开启「自动跟随系统深浅色」时同步切换主题（安卓版 common.isAutoTheme）
   */
  onConfigurationUpdate(newConfig: Configuration): void {
    const isDark = newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    hilog.info(DOMAIN, TAG, 'onConfigurationUpdate colorMode=%{public}d', newConfig.colorMode ?? -1);
    setSystemDarkMode(isDark);
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    hilog.info(DOMAIN, TAG, 'EntryAbility onWindowStageCreate');

    // 保存 windowStage 供子窗口使用
    AppStorage.setOrCreate('windowStage', windowStage);

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
      settingsService.setContext(this.context);
      setQuickJSContext(this.context);

      // 运行日志：尽可能早地装好，才能覆盖启动阶段的失败信息
      await logService.init(this.context);

      // 设置 PlayerService 上下文（用于读取偏好设置）
      playerService.setContext(this.context);

      // 设置媒体保存服务上下文（保存歌词/封面到文件）
      mediaSaveService.setContext(this.context);

      // 初始化所有服务（存储、主题、列表、播放器）
      await initAllServices();

      // 自动跟随系统深浅色：设置已加载，按当前系统色彩模式应用一次
      // （config.colorMode 为 COLOR_MODE_DARK 表示系统深色）
      setSystemDarkMode(this.context.config.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      await applyAutoTheme();

      // 设置已加载，同步「记录详细日志」开关（init 时设置尚未就绪，只能读默认值）
      logService.setVerbose(settingsService.get().enableVerboseLog);

      // 语言依赖已加载的设置快照，必须放在 initAllServices 之后
      initLocalization();

      await runBootstrapAfterServices(want);

      // 首帧之后再补做非关键初始化：避免冷启动被磁盘/目录操作拖慢
      setTimeout(() => {
        localMusicService.setContext(this.context);
        localMusicService.init().then((): void => {
          hilog.info(DOMAIN, TAG, 'Local music library loaded (deferred)');
        }).catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, 'Deferred local music init failed: %{public}s', err.message);
        });
        initImageCache(this.context).catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, 'Deferred image cache init failed: %{public}s', err.message);
        });
      }, 300);

      // 延迟初始化播放器，避免窗口未准备好导致的错误
      setTimeout(async () => {
        try {
          // 更新播放选项
          await playerService.updateOptions();

          // 设置音量
          await playerService.setVolume(settingsService.get().volume / 100);

          // 应用上次的倍速（不能用 setPlaybackRate(1.0)：那会把用户偏好写回成默认值）
          await playerService.applySavedPlaybackRate();

          // 恢复上次播放的歌曲与进度（续播；不自动播放）
          await playerService.restoreLastPlayback();

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
