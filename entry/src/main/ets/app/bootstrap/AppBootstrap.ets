/**
 * 应用层启动编排：在 initAllServices 之后执行，对齐 RN src/core/init 中的后置步骤。
 */
import hilog from '@ohos.hilog';
import { initMusicSDK, loadCustomSource } from '../../core/music/MusicFeatureEntry';
import { runVersionCheckDeferred } from '../../service/VersionCheckService';
import { getStorageService } from '../../core/interfaces/IStorageService';
import { settingsService } from '../../service/SettingsService';
import { DesktopLyricManager } from '../../components/common/DesktopLyric';

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

function scheduleDesktopLyricRestore(): void {
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
      const storage = getStorageService();
      const currentSource = await storage.getString('plugin.currentSource', 'kw');
      const customSourceUrl = await storage.getString('plugin.customSourceUrl', '');
      if (currentSource !== 'custom' || customSourceUrl.length <= 0) {
        return;
      }
      hilog.info(DOMAIN, TAG, 'Deferred custom source restore start: %{public}s', customSourceUrl);
      const loaded = await loadCustomSource(customSourceUrl);
      hilog.info(DOMAIN, TAG, 'Deferred custom source restore result: %{public}s', loaded.toString());
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Deferred custom source restore skipped: %{public}s', JSON.stringify(err));
    }
  }, CUSTOM_SOURCE_RESTORE_DELAY_MS);
}
