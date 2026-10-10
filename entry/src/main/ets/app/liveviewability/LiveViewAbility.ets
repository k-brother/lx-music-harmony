/**
 * 实况窗锁屏扩展（独立子进程）
 *
 * 由系统渲染锁屏沉浸实况窗时拉起。初始歌词负载经 want.parameters
 * （LiveViewService 下发的 liveViewLockScreenAbilityParameters）送达，
 * 这里注入 LocalStorage 交给 LockScreenPage；之后的逐句更新走 common event
 * （事件名与负载形状见 utils/LiveViewKeys）。
 *
 * 本进程没有应用侧的 LocalizationService / 资源体系，
 * 所以页面文案全部由发布方翻译后随负载下发，这里不做任何本地化。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { Want, UIExtensionContentSession } from '@kit.AbilityKit';
import { LiveViewLockScreenExtensionAbility } from '@kit.LiveViewKit';
import { LIVE_VIEW_PARAM_KEY, LS_INIT_DATA_KEY } from '../../utils/LiveViewKeys';

const TAG = 'LiveViewAbility';
const DOMAIN = 0x0003;

/** want.parameters 取值：泛型绕开 object→string 直转限制（与 widget/CardFormAbility 同款） */
function paramAs<T>(params: Record<string, object> | undefined, key: string): T | undefined {
  if (params === undefined) {
    return undefined;
  }
  const value: object | undefined = params[key];
  if (value === undefined || value === null) {
    return undefined;
  }
  return value as T;
}

export default class LiveViewAbility extends LiveViewLockScreenExtensionAbility {
  onSessionCreate(want: Want, session: UIExtensionContentSession): void {
    hilog.info(DOMAIN, TAG, 'onSessionCreate');
    const storage: LocalStorage = new LocalStorage();
    const raw: string | undefined = paramAs<string>(want.parameters, LIVE_VIEW_PARAM_KEY);
    if (raw !== undefined && raw.length > 0) {
      storage.setOrCreate(LS_INIT_DATA_KEY, raw);
    }
    try {
      session.loadContent('liveview/pages/LockScreenPage', storage);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadContent failed: %{public}s', JSON.stringify(err));
    }
  }
}
