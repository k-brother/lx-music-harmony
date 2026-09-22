/**
 * 设置变更订阅（分组组件用）
 *
 * 分组组件自持状态后，"外部改了设置怎么办"必须统一解决：
 * 恢复备份、同步下发、播放页改设置、其它入口改设置都会触发 SETTING_CHANGED，
 * 分组只要订阅它并刷新自己的状态即可，不必各自记住"哪里改过要通知我"。
 *
 * 用法：
 *   this.settingsUnsub = watchSettings(() => this.loadFromSettings());
 */
import { on, EventTypes } from './EventBus';

/** 订阅设置变化；返回取消订阅函数 */
export function watchSettings(handler: () => void): () => void {
  return on(EventTypes.SETTING_CHANGED, (): void => {
    handler();
  });
}
