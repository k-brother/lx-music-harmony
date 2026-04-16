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
const VERSION_CHECK_DEFER_MS = 9000;

function parseVersionPayload(text: string): VersionInfo | null {
  try {
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      return null;
    }
    const root = JSON.parse(trimmed) as Record<string, string | number | Object | undefined>;
    const rawVer = root['version'];
    const versionStr = typeof rawVer === 'number' ? String(rawVer) : rawVer;
    if (typeof versionStr !== 'string' || versionStr.length === 0) {
      return null;
    }
    const desc = root['desc'];
    const descStr = typeof desc === 'string' ? desc : '';
    const info: VersionInfo = {
      version: versionStr,
      desc: descStr,
      publishTime: '',
    };
    return info;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'parseVersionPayload failed: %{public}s', (e as Error)?.message);
    return null;
  }
}

async function fetchAndEmitVersionInfo(): Promise<void> {
  try {
    const body = await fetchUtf8Text(PRIMARY_VERSION_URL);
    if (body.length === 0) {
      hilog.warn(DOMAIN, TAG, 'Version check empty response');
      return;
    }
    const info = parseVersionPayload(body);
    if (info) {
      stateEvent.versionInfoUpdated(info);
      hilog.info(DOMAIN, TAG, 'Remote version: %{public}s', info.version);
    } else {
      hilog.warn(DOMAIN, TAG, 'Version check unparsable or no top-level version (len=%{public}d)', body.length);
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'Version check failed: %{public}s', JSON.stringify(e));
  }
}

/** 延后执行，避免与冷启动存储/首屏抢占网络。 */
export function runVersionCheckDeferred(): void {
  setTimeout(() => {
    void fetchAndEmitVersionInfo();
  }, VERSION_CHECK_DEFER_MS);
}
