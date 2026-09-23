/**
 * 定时退出（睡眠定时）服务
 *
 * 设置页与播放详情页共用同一个定时器，避免两处各自 setTimeout 导致状态不一致。
 * 时长与开关持久化在 SettingsService，应用重启后自动恢复。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { settingsService } from './SettingsService';
import { playerService } from './PlayerService';
import { EventChannel } from './EventChannel';
import { getStorageService } from '../core/interfaces/IStorageService';

const TAG = 'SleepTimerService';
const DOMAIN = 0x0005;
/**
 * 倒计时截止时间戳（毫秒）的落盘键。
 *
 * 这是「本次会话还剩多久」而不是用户偏好，所以不进设置：只用来在应用重启后
 * 接着原来的截止时间走（此前重启会把定时重新按整段时长开始，等于偷偷续了半小时）。
 */
const DEADLINE_KEY = 'sleepTimer.endsAt';
const MINUTE_MS = 60 * 1000;

export interface SleepTimerState {
  enabled: boolean;
  minutes: number;
  /** 倒计时已到、正在等待当前歌曲播完 */
  waitingTrackEnd: boolean;
}

type SleepTimerListener = (state: SleepTimerState) => void;

class SleepTimerServiceImpl {
  private timerId: number = -1;
  /** 状态订阅（通用订阅器，与播放事件中心同一套实现） */
  private listeners: EventChannel<SleepTimerListener> = new EventChannel('sleepTimer');
  /** 倒计时结束但仍在等当前歌曲播完 */
  private waitingTrackEnd: boolean = false;
  private trackEndUnsub: (() => void) | null = null;

  /** 应用启动时调用：如果设置里开启了定时退出，则恢复倒计时 */
  restoreFromSettings(): void {
    const settings = settingsService.get();
    if (settings.sleepTimerEnabled && settings.sleepTimerMinutes > 0) {
      void this.resumeByDeadline();
      return;
    }
    // 没开启就顺手清掉可能残留的截止时间，避免下次误恢复
    void this.clearDeadline();
  }

  /**
   * 按落盘的截止时间恢复倒计时。
   * - 还没到点：接着剩余时长走（不是重新按整段计时）；
   * - 已经过点：视为在应用没运行期间已经结束，清掉开关；
   * - 没有落盘记录（旧版本升级上来）：退回按设置里的时长重新开始，与旧行为一致。
   */
  private async resumeByDeadline(): Promise<void> {
    const endsAt: number = await this.loadDeadline();
    if (endsAt <= 0) {
      this.start(settingsService.get().sleepTimerMinutes, false);
      return;
    }
    if (endsAt - Date.now() <= 0) {
      hilog.info(DOMAIN, TAG, 'Sleep timer expired while app was not running, clearing');
      await this.clearDeadline();
      settingsService.update({ sleepTimerEnabled: false }).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'Failed to clear expired sleep timer: %{public}s', err.message);
      });
      this.notify();
      return;
    }
    this.scheduleUntil(endsAt);
    hilog.info(DOMAIN, TAG, 'Sleep timer resumed, %{public}d ms left', endsAt - Date.now());
    this.notify();
  }

  /**
   * 开始倒计时
   * @param minutes 分钟数
   * @param persist 是否写入设置（默认写入）
   */
  start(minutes: number, persist: boolean = true): void {
    const safeMinutes = minutes > 0 ? minutes : 30;
    const endsAt: number = Date.now() + safeMinutes * MINUTE_MS;
    this.scheduleUntil(endsAt);

    if (persist) {
      void this.saveDeadline(endsAt);
      settingsService.update({ sleepTimerEnabled: true, sleepTimerMinutes: safeMinutes })
        .catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, 'Failed to persist sleep timer: %{public}s', err.message);
        });
    }
    hilog.info(DOMAIN, TAG, 'Sleep timer started: %{public}d min', safeMinutes);
    this.notify();
  }

  /**
   * 按「截止时间戳」排定时器。
   * 新建与恢复都走这里，剩余时长的计算只有这一处；到点时统一清开关与落盘记录，
   * 避免出现「定时已经响过、界面还显示倒计时中」的残留状态。
   */
  private scheduleUntil(endsAt: number): void {
    this.stopTimerOnly();
    const remainingMs: number = Math.max(0, endsAt - Date.now());
    this.timerId = setTimeout(() => {
      this.timerId = -1;
      hilog.info(DOMAIN, TAG, 'Sleep timer fired, pausing playback');
      void this.clearDeadline();
      this.handleTimerFired();
      settingsService.update({ sleepTimerEnabled: false }).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'Failed to persist sleep timer stop: %{public}s', err.message);
      });
      this.notify();
    }, remainingMs);
  }

  /** 保存截止时间（失败只告警：定时器本身已经排好，不影响本次会话） */
  private async saveDeadline(endsAt: number): Promise<void> {
    try {
      await getStorageService().setNumber(DEADLINE_KEY, Math.floor(endsAt));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'save deadline failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 读取截止时间（无记录返回 0） */
  private async loadDeadline(): Promise<number> {
    try {
      return await getStorageService().getNumber(DEADLINE_KEY, 0);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'load deadline failed: %{public}s', JSON.stringify(err));
      return 0;
    }
  }

  private async clearDeadline(): Promise<void> {
    try {
      await getStorageService().remove(DEADLINE_KEY);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clear deadline failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 倒计时到点时的动作（对齐安卓版 player.timeoutExitPlayed）：
   * - 开启「播完当前歌曲再退出」且正在播放 → 等整首歌播完再停，界面显示等待状态，可取消；
   * - 否则立即暂停。
   */
  private handleTimerFired(): void {
    const waitTrackEnd = settingsService.get().sleepTimerWaitTrackEnd;
    if (waitTrackEnd && playerService.isPlaying()) {
      this.waitingTrackEnd = true;
      this.armTrackEndListener();
      hilog.info(DOMAIN, TAG, 'Sleep timer waiting for current track to finish');
      this.notify();
      return;
    }
    this.stopPlaybackNow();
  }

  /** 监听"当前歌曲播放结束"，到点后停止播放并清理等待态 */
  private armTrackEndListener(): void {
    this.releaseTrackEndListener();
    this.trackEndUnsub = playerService.onTrackCompleted((): void => {
      if (!this.waitingTrackEnd) {
        return;
      }
      this.waitingTrackEnd = false;
      this.releaseTrackEndListener();
      hilog.info(DOMAIN, TAG, 'Current track finished, sleep timer stopping playback');
      this.stopPlaybackNow();
      this.notify();
    });
  }

  private releaseTrackEndListener(): void {
    if (this.trackEndUnsub) {
      this.trackEndUnsub();
      this.trackEndUnsub = null;
    }
  }

  private stopPlaybackNow(): void {
    this.waitingTrackEnd = false;
    this.releaseTrackEndListener();
    playerService.pause().catch((err: Error) => {
      hilog.error(DOMAIN, TAG, 'Sleep timer pause failed: %{public}s', err.message);
    });
  }

  /** 取消"等待播放结束后退出"（安卓版的 cancelTimeoutExit） */
  cancelPendingExit(): void {
    if (!this.waitingTrackEnd) {
      return;
    }
    this.waitingTrackEnd = false;
    this.releaseTrackEndListener();
    hilog.info(DOMAIN, TAG, 'Pending sleep-timer exit cancelled');
    this.notify();
  }

  /** 取消倒计时 */
  stop(persist: boolean = true): void {
    this.stopTimerOnly();
    // 落盘的截止时间也要清掉，否则下次启动会「凭空恢复」一个已经取消的定时
    void this.clearDeadline();
    if (persist) {
      settingsService.update({ sleepTimerEnabled: false }).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'Failed to persist sleep timer stop: %{public}s', err.message);
      });
    }
    hilog.info(DOMAIN, TAG, 'Sleep timer stopped');
    this.notify();
  }

  /** 修改时长（已开启时重新计时） */
  setMinutes(minutes: number): void {
    if (this.isRunning()) {
      this.start(minutes, true);
      return;
    }
    settingsService.update({ sleepTimerMinutes: minutes }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'Failed to persist sleep minutes: %{public}s', err.message);
    });
    this.notify();
  }

  isRunning(): boolean {
    return this.timerId >= 0;
  }

  getState(): SleepTimerState {
    const settings = settingsService.get();
    return {
      enabled: this.isRunning() || settings.sleepTimerEnabled,
      minutes: settings.sleepTimerMinutes,
      waitingTrackEnd: this.waitingTrackEnd,
    };
  }

  onStateChange(listener: SleepTimerListener): () => void {
    return this.listeners.on(listener);
  }

  private stopTimerOnly(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  private notify(): void {
    const state = this.getState();
    this.listeners.emit((listener: SleepTimerListener): void => {
      listener(state);
    });
  }
}

export const sleepTimerService = new SleepTimerServiceImpl();
export default sleepTimerService;
