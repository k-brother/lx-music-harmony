/**
 * 焦点工具
 *
 * 输入类浮层（首页搜索、设置里的输入面板）打开后应当自动聚焦并弹出键盘 ——
 * 否则用户点了搜索还要再点一次输入框才能打字，与主流 App 的手感差距明显。
 *
 * `FocusController.requestFocus` 在节点尚未上树/不可聚焦时会抛 BusinessError，
 * 这里统一兜住：聚焦失败只记日志，不影响界面渲染。
 */
import type { UIContext } from '@kit.ArkUI';
import { appLog as hilog } from '../core/log/AppLogger';

const DOMAIN: number = 0x0001;
const TAG = 'FocusTools';

/** 把焦点移到指定 key 的组件（失败静默） */
export function requestFocusSafe(uiContext: UIContext, key: string): void {
  if (key.length === 0) {
    return;
  }
  try {
    uiContext.getFocusController().requestFocus(key);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'requestFocus(%{public}s) failed: %{public}s', key,
      err instanceof Error ? err.message : JSON.stringify(err));
  }
}
