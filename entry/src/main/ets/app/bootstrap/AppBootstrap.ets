/**
 * 应用层启动编排：在 initAllServices 之后执行，对齐 RN src/core/init 中的后置步骤。
 */
import hilog from '@ohos.hilog';
import { initMusicSDK, restoreEnabledCustomSource } from '../../core/music/MusicFeatureEntry';
import { runVersionCheckDeferred } from '../../service/VersionCheckService';
import { settingsService } from '../../service/SettingsService';
import { DesktopLyricManager } from '../../components/common/DesktopLyric';
import { on, EventTypes } from '../../service/EventBus';
import { setLanguage } from '../../service/LocalizationService';

const TAG = 'AppBootstrap';
const DOMAIN = 0x0001;
const CUSTOM_SOURCE_RESTORE_DELAY_MS = 3000;
/** 桌面歌词子窗口需要主窗口 WindowStage 就绪，延迟恢复 */
const DESKTOP_LYRIC_RESTORE_DELAY_MS = 3000;

function handleLaunchWant(want?: object): void {
  if (!want) {
    return;
  }
  const w = want as Record<string, string | Object | undefined>;
  const uri = w['uri'];
  if (typeof uri === 'string' && uri.length > 0) {
    hilog.info(DOMAIN, TAG, 'Launch want.uri=%{public}s', uri);
  }
  const action = w['action'];
  if (typeof action === 'string' && action.length > 0) {
    hilog.info(DOMAIN, TAG, 'Launch want.action=%{public}s', action);
  }
}

export async function runBootstrapAfterServices(want?: object): Promise<void> {
  // 语言与桌面歌词配置由 SettingsService 统一加载并镜像到 AppStorage；
  // 歌词文本由 PlayerService（播放器歌词中枢）在切歌/播放时下发。
  AppStorage.setOrCreate('desktopLyricText', '');
  AppStorage.setOrCreate('desktopLyricNextText', '');
  bindLanguageSync();
  await initMusicSDK();
  hilog.info(
    DOMAIN,
    TAG,
    'Bootstrap marker v2: custom source restore scheduled in %{public}dms',
    CUSTOM_SOURCE_RESTORE_DELAY_MS
  );
  scheduleDeferredCustomSourceRestore();
  scheduleDesktopLyricRestore();
  handleLaunchWant(want);
  runVersionCheckDeferred();
}

/**
 * 语言跟随设置变化。
 *
 * 用户手动切语言时由设置页直接调 setLanguage()；但「恢复默认设置」「恢复备份」
 * 「同步下发」都会改 settings.language 而不会经过设置页 —— 那样界面语言会一直
 * 停在旧值，直到重启。这里订阅一次设置变化，发现与当前语言不一致就补一次。
 */
function bindLanguageSync(): void {
  const applyIfChanged = (): void => {
    const next = settingsService.get().language;
    const current = AppStorage.get<string>('language');
    if (next.length > 0 && next !== current) {
      setLanguage(next);
      hilog.info(DOMAIN, TAG, 'Language synced from settings: %{public}s', next);
    }
  };
  applyIfChanged();
  on(EventTypes.SETTING_CHANGED, (): void => {
    applyIfChanged();
  });
}

function scheduleDesktopLyricRestore(): void {
  // 先绑定「播控会话就绪」回调：启动阶段会话还没建，系统歌词要等它就绪后自动接管
  DesktopLyricManager.bindSessionReadyHook();
  setTimeout(() => {
    try {
      if (settingsService.get().showDesktopLyric) {
        hilog.info(DOMAIN, TAG, 'Restoring desktop lyric window');
        void DesktopLyricManager.setEnabled(true);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Desktop lyric restore skipped: %{public}s', JSON.stringify(err));
    }
  }, DESKTOP_LYRIC_RESTORE_DELAY_MS);
}

function scheduleDeferredCustomSourceRestore(): void {
  setTimeout(async () => {
    try {
      // 自定义源列表由持久化仓库统一恢复（脚本存在时离线直接激活）
      hilog.info(DOMAIN, TAG, 'Deferred custom source restore start');
      const loaded = await restoreEnabledCustomSource();
      hilog.info(DOMAIN, TAG, 'Deferred custom source restore result: %{public}s', loaded.toString());
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Deferred custom source restore skipped: %{public}s', JSON.stringify(err));
    }
  }, CUSTOM_SOURCE_RESTORE_DELAY_MS);
}
