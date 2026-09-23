/**
 * 统一轻提示
 *
 * 之前 11 个页面各自实现了一遍 `getUIContext().getPromptAction().showToast(...)`
 * 加 try/catch 的样板代码；这里收口成一处，页面只保留一行薄封装即可。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { UIContext } from '@kit.ArkUI';

const DOMAIN = 0x0001;
const TAG = 'Toast';
/** 默认展示时长（毫秒） */
export const TOAST_DURATION_SHORT = 1800;
export const TOAST_DURATION_DEFAULT = 2000;

/**
 * 显示轻提示；UI 未就绪（预览器、页面已销毁）时退化为 hilog，不抛异常。
 * @param uiContext 调用方通过 this.getUIContext() 传入
 */
export function showAppToast(
  uiContext: UIContext,
  message: string,
  duration: number = TOAST_DURATION_DEFAULT
): void {
  if (!message || message.length === 0) {
    return;
  }
  try {
    uiContext.getPromptAction().showToast({ message, duration });
  } catch (err) {
    hilog.info(DOMAIN, TAG, 'fallback toast: %{public}s', message);
  }
}
