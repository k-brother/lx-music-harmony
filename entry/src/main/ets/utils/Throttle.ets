/**
 * 节流器（两种语义，统一在这里实现）
 *
 * 项目里有两类"别刷太勤"的需求，语义不同，以前各写一套 setTimeout：
 * - `schedule()`：**合并窗口**。事件驱动的推送用（卡片快照、歌词句），
 *   窗口内的多次调用合并成一次，窗口结束后执行 —— 保证最终状态一定被送达；
 * - `tryRun()`：**最小间隔**。时间驱动的更新用（实况窗随播放推进刷新），
 *   距上次执行不足 interval 的直接丢弃 —— 不用定时器，也不补发。
 *
 * 两类共享同一份计时/释放逻辑，避免服务里再各自维护 flag + setTimeout。
 * 使用方在对象销毁时调 `dispose()`（与 check_timer_cleanup 的约定一致）。
 */

export class Throttle {
  private readonly intervalMs: number;
  private readonly action: () => void;
  private timerId: number = -1;
  private lastRunAt: number = 0;

  constructor(intervalMs: number, action: () => void) {
    this.intervalMs = intervalMs;
    this.action = action;
  }

  /** 合并窗口：窗口内的重复调用只保留一次执行（窗口结束时执行） */
  schedule(): void {
    if (this.timerId !== -1) {
      return;
    }
    this.timerId = setTimeout((): void => {
      this.timerId = -1;
      this.lastRunAt = Date.now();
      this.action();
    }, this.intervalMs);
  }

  /** 最小间隔：距上次执行不足 interval 时直接丢弃，不排队、不补发 */
  tryRun(): void {
    const now: number = Date.now();
    if (now - this.lastRunAt < this.intervalMs) {
      return;
    }
    this.lastRunAt = now;
    this.action();
  }

  /** 取消未执行的窗口（不影响已执行过的记录） */
  cancel(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  /** 对象销毁时调用：等价于 cancel()，语义更明确 */
  dispose(): void {
    this.cancel();
  }
}
