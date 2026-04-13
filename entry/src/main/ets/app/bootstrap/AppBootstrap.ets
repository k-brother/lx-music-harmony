/**
 * 应用层启动编排：在 initAllServices 之后执行，对齐 RN src/core/init 中的后置步骤。
 */
import hilog from '@ohos.hilog';
import { initMusicSDK } from '../../core/music/MusicFeatureEntry';
import { runVersionCheckDeferred } from '../../service/VersionCheckService';

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
  handleLaunchWant(want);
  runVersionCheckDeferred();
}
