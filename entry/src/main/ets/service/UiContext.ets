/**
 * 全局 UIContext 持有者
 *
 * 目的：让「对话框 / 轻提示 / 菜单」这类需要在任意位置弹出的能力
 * 不必每个页面都 `this.getUIContext()` 再往下传参，
 * 页面只需要 `appConfirm(...)` / `appActionMenu(...)` / `appToast(...)`。
 *
 * 由根页面 NavIndex（aboutToAppear）注入一次；预览器或未注入时返回 null，
 * 调用方按"无 UI 能力"降级处理（不抛异常）。
 */
import type { UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0005;
const TAG = 'UiContext';

let appUiContext: UIContext | null = null;

/** 根页面启动时注入（重复注入以最后一次为准，兼容多窗口） */
export function setAppUiContext(context: UIContext): void {
  appUiContext = context;
  hilog.info(DOMAIN, TAG, 'UIContext registered');
}

/** 取全局 UIContext；未注入时返回 null */
export function getAppUiContext(): UIContext | null {
  return appUiContext;
}
