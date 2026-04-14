/**
 * 应用层启动编排：在 initAllServices 之后执行，对齐 RN src/core/init 中的后置步骤。
 */
import hilog from '@ohos.hilog';
import { initMusicSDK, loadCustomSource } from '../../core/music/MusicFeatureEntry';
import { runVersionCheckDeferred } from '../../service/VersionCheckService';
import { getStorageService } from '../../core/interfaces/IStorageService';

const TAG = 'AppBootstrap';
const DOMAIN = 0x0001;

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
  await initMusicSDK();
  try {
    const storage = getStorageService();
    const currentSource = await storage.getString('plugin.currentSource', 'kw');
    const customSourceUrl = await storage.getString('plugin.customSourceUrl', '');
    if (currentSource === 'custom' && customSourceUrl.length > 0) {
      hilog.info(DOMAIN, TAG, 'Restoring custom source on bootstrap: %{public}s', customSourceUrl);
      const loaded = await loadCustomSource(customSourceUrl);
      hilog.info(DOMAIN, TAG, 'Custom source restore result: %{public}s', loaded.toString());
    }
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'Custom source restore skipped: %{public}s', JSON.stringify(err));
  }
  handleLaunchWant(want);
  runVersionCheckDeferred();
}
