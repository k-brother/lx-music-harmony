/**
 * 订阅句柄
 *
 * ArkUI 组件里「aboutToAppear 订阅、aboutToDisappear 取消」是固定套路，
 * 但每个文件都手写一遍 `if (this.xxxUnsub) { this.xxxUnsub(); this.xxxUnsub = null; }`，
 * 既啰嗦又容易漏（漏了就是页面销毁后仍在回调里 setState）。
 *
 * 用这个句柄把成对调用收成两行：`bind(...)` / `detach()`。
 */
import { watchSettings } from './SettingsWatcher';

export class Subscription {
  private unsub: (() => void) | null = null;

  /** 绑定一个「返回取消函数」的订阅；重复调用只保留最新一次 */
  bind(subscribe: () => () => void): void {
    this.detach();
    this.unsub = subscribe();
  }

  /** 绑定设置变更（设置分组组件最常用） */
  bindSettings(handler: () => void): void {
    this.bind((): () => void => watchSettings(handler));
  }

  /** 取消当前订阅；未订阅时为空操作 */
  detach(): void {
    if (this.unsub) {
      this.unsub();
      this.unsub = null;
    }
  }
}
