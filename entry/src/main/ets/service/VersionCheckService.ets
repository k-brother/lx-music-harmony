/**
 * 启动后异步检查远端版本信息，与 RN 端 src/core/version.ts 行为对齐（仅拉取并广播，不弹窗）。
 */
import hilog from '@ohos.hilog';
import { stateEvent, type VersionInfo } from '../event/StateEvent';
import { fetchUtf8Text } from './HttpRepository';

const TAG = 'VersionCheck';
const DOMAIN = 0x0006;

const PRIMARY_VERSION_URL =
  'https://raw.githubusercontent.com/lyswhut/lx-music-mobile/master/publish/version.json';

function parseVersionPayload(text: string): VersionInfo | null {
  try {
    const root = JSON.parse(text) as Record<string, string | Object>;
    const ver = root['version'];
    const desc = root['desc'];
    if (typeof ver !== 'string' || ver.length === 0) {
      return null;
    }
    const descStr = typeof desc === 'string' ? desc : '';
    const info: VersionInfo = {
      version: ver,
      desc: descStr,
      publishTime: '',
    };
    return info;
  } catch {
    return null;
  }
}

async function fetchAndEmitVersionInfo(): Promise<void> {
  try {
    const body = await fetchUtf8Text(PRIMARY_VERSION_URL);
    const info = parseVersionPayload(body);
    if (info) {
      stateEvent.versionInfoUpdated(info);
      hilog.info(DOMAIN, TAG, 'Remote version: %{public}s', info.version);
    } else {
      hilog.warn(DOMAIN, TAG, 'Version JSON missing version field');
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'Version check failed: %{public}s', JSON.stringify(e));
  }
}

/** 延后执行，避免与冷启动存储/首屏抢占网络。 */
export function runVersionCheckDeferred(): void {
  setTimeout(() => {
    void fetchAndEmitVersionInfo();
  }, 2500);
}
