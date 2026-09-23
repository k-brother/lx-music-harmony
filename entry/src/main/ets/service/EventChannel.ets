/**
 * 订阅 + 广播的通用实现
 *
 * 播放事件中心（service/player/PlaybackEvents）与睡眠定时器
 * （service/SleepTimerService）都需要「一组监听器 + 订阅返回取消函数 + 广播」，
 * 之前各写了一遍。收敛到这里后：
 * - 新增一种事件只需声明一个字段；
 * - 广播自动隔离异常：某个订阅者抛错只记日志，不影响其它订阅者。
 */
import { appLog as hilog } from '../core/log/AppLogger';

const DOMAIN: number = 0x0002;
const TAG = 'EventChannel';

export class EventChannel<T> {
  private listeners: T[] = [];
  private readonly name: string;

  /** @param name 仅用于日志，便于定位是哪个事件出了问题 */
  constructor(name: string) {
    this.name = name;
  }

  /** 订阅，返回取消订阅函数 */
  on(listener: T): () => void {
    this.listeners.push(listener);
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index > -1) {
        this.listeners.splice(index, 1);
      }
    };
  }

  /** 是否有订阅者（避免无谓地构造广播数据） */
  hasListeners(): boolean {
    return this.listeners.length > 0;
  }

  /** 广播：订阅者抛错只记日志，不影响其他订阅者 */
  emit(invoke: (listener: T) => void): void {
    if (this.listeners.length === 0) {
      return;
    }
    const snapshot = this.listeners.slice();
    for (let i = 0; i < snapshot.length; i++) {
      try {
        invoke(snapshot[i]);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, '%{public}s listener failed: %{public}s',
          this.name, err instanceof Error ? err.message : JSON.stringify(err));
      }
    }
  }

  /** 移除全部订阅（服务销毁/测试重置用） */
  clear(): void {
    this.listeners = [];
  }
}
