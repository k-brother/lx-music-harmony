/**
 * 定时退出（睡眠定时）服务
 *
 * 设置页与播放详情页共用同一个定时器，避免两处各自 setTimeout 导致状态不一致。
 * 时长与开关持久化在 SettingsService，应用重启后自动恢复。
 */
import hilog from '@ohos.hilog';
import { settingsService } from './SettingsService';
import { playerService } from './PlayerService';

const TAG = 'SleepTimerService';
const DOMAIN = 0x0005;

export interface SleepTimerState {
  enabled: boolean;
  minutes: number;
}

type SleepTimerListener = (state: SleepTimerState) => void;

class SleepTimerServiceImpl {
  private timerId: number = -1;
  private listeners: SleepTimerListener[] = [];

  /** 应用启动时调用：如果设置里开启了定时退出，则恢复倒计时 */
  restoreFromSettings(): void {
    const settings = settingsService.get();
    if (settings.sleepTimerEnabled && settings.sleepTimerMinutes > 0) {
      this.start(settings.sleepTimerMinutes, false);
    }
  }

  /**
   * 开始倒计时
   * @param minutes 分钟数
   * @param persist 是否写入设置（默认写入）
   */
  start(minutes: number, persist: boolean = true): void {
    this.stopTimerOnly();
    const safeMinutes = minutes > 0 ? minutes : 30;
    this.timerId = setTimeout(() => {
      this.timerId = -1;
      hilog.info(DOMAIN, TAG, 'Sleep timer fired after %{public}d min, pausing playback', safeMinutes);
      playerService.pause().catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'Sleep timer pause failed: %{public}s', err.message);
      });
      if (persist) {
        settingsService.update({ sleepTimerEnabled: false }).catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, 'Failed to persist sleep timer stop: %{public}s', err.message);
        });
      }
      this.notify();
    }, safeMinutes * 60 * 1000);

    if (persist) {
      settingsService.update({ sleepTimerEnabled: true, sleepTimerMinutes: safeMinutes })
        .catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, 'Failed to persist sleep timer: %{public}s', err.message);
        });
    }
    hilog.info(DOMAIN, TAG, 'Sleep timer started: %{public}d min', safeMinutes);
    this.notify();
  }

  /** 取消倒计时 */
  stop(persist: boolean = true): void {
    this.stopTimerOnly();
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
    };
  }

  onStateChange(listener: SleepTimerListener): () => void {
    this.listeners.push(listener);
    return (): void => {
      const index = this.listeners.indexOf(listener);
      if (index > -1) {
        this.listeners.splice(index, 1);
      }
    };
  }

  private stopTimerOnly(): void {
    if (this.timerId >= 0) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
  }

  private notify(): void {
    const state = this.getState();
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i](state);
    }
  }
}

export const sleepTimerService = new SleepTimerServiceImpl();
export default sleepTimerService;
