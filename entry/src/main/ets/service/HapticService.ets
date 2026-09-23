/**
 * 触感反馈服务（HarmonyOS 振动能力）
 *
 * 商业化 App 的手感很大一部分来自"按下去有反馈"：切 Tab、播放/暂停、长按菜单、
 * 收藏成功这类操作给一次轻微振动，用户会觉得界面"跟手"。
 *
 * 设计要点：
 * - 统一入口：调用方只说语义（selection/light/medium/notifySuccess...），
 *   具体用哪个系统预设由这里决定，换效果不用改业务代码；
 * - 节流：24ms 内重复触发只响一次，连续滑动/连点不会变成"嗡嗡嗡"；
 * - 可关：跟随「设置 → 触感反馈」，关掉后所有调用静默返回；
 * - 能力降级：设备不支持/权限被拒时静默失败并记住结果，不再反复尝试。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { vibrator } from '@kit.SensorServiceKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import { settingsService } from './SettingsService';

const TAG = 'Haptic';
const DOMAIN = 0x0002;
/** 同一次交互里的重复触发间隔（毫秒） */
const THROTTLE_MS = 24;

/** 触感语义 */
export enum HapticKind {
  /** 选择变化：切 Tab、切分段控件、滚动选择 */
  Selection = 'selection',
  /** 轻：播放/暂停、开关 */
  Light = 'light',
  /** 中：长按唤起菜单、拖拽开始/结束 */
  Medium = 'medium',
  /** 强：删除等破坏性操作前的确认 */
  Heavy = 'heavy',
  /** 成功：收藏、下载完成 */
  Success = 'success',
  /** 警告/失败：操作失败提示 */
  Warning = 'warning',
}

interface HapticEffectSpec {
  /** 系统预设效果 id（haptic.effect.soft 等），空表示用时长兜底 */
  preset?: string;
  /** 兜底时长（毫秒），部分设备不支持预设 */
  fallbackMs: number;
}

/** 语义 -> 系统预设效果（集中一处，换效果不用改业务代码） */
function specFor(kind: HapticKind): HapticEffectSpec {
  if (kind === HapticKind.Selection) {
    const spec: HapticEffectSpec = { preset: vibrator.HapticFeedback.EFFECT_SOFT.toString(), fallbackMs: 8 };
    return spec;
  }
  if (kind === HapticKind.Medium) {
    const spec: HapticEffectSpec = { preset: vibrator.HapticFeedback.EFFECT_HARD.toString(), fallbackMs: 20 };
    return spec;
  }
  if (kind === HapticKind.Heavy) {
    const spec: HapticEffectSpec = { preset: vibrator.HapticFeedback.EFFECT_SHARP.toString(), fallbackMs: 30 };
    return spec;
  }
  if (kind === HapticKind.Success) {
    const spec: HapticEffectSpec = { preset: vibrator.HapticFeedback.EFFECT_NOTICE_SUCCESS.toString(), fallbackMs: 24 };
    return spec;
  }
  if (kind === HapticKind.Warning) {
    const spec: HapticEffectSpec = { preset: vibrator.HapticFeedback.EFFECT_NOTICE_WARNING.toString(), fallbackMs: 24 };
    return spec;
  }
  const light: HapticEffectSpec = { preset: vibrator.HapticFeedback.EFFECT_SOFT.toString(), fallbackMs: 12 };
  return light;
}

class HapticServiceImpl {
  private lastAt: number = 0;
  /** 设备/权限不可用时置为 false，避免每次交互都走一遍失败路径 */
  private available: boolean = true;

  /** 触感是否开启（跟随设置，默认开） */
  private isEnabled(): boolean {
    try {
      return settingsService.get().hapticFeedback;
    } catch (err) {
      return true;
    }
  }

  /**
   * 触发一次触感反馈（不阻塞调用方，失败静默）
   */
  play(kind: HapticKind = HapticKind.Light): void {
    if (!this.available || !this.isEnabled()) {
      return;
    }
    const now = Date.now();
    if (now - this.lastAt < THROTTLE_MS) {
      return;
    }
    this.lastAt = now;

    const spec: HapticEffectSpec = specFor(kind);
    const attribute: vibrator.VibrateAttribute = { id: 0, usage: 'touch' };
    const preset = spec.preset;

    let startVibration: Promise<void>;
    if (preset !== undefined) {
      const presetEffect: vibrator.VibratePreset = { type: 'preset', effectId: preset };
      startVibration = vibrator.startVibration(presetEffect, attribute);
    } else {
      startVibration = Promise.reject(new Error('no preset'));
    }

    startVibration.catch(() => {
      // 预设效果不被支持时退回固定时长
      const timeEffect: vibrator.VibrateTime = { type: 'time', duration: spec.fallbackMs };
      return vibrator.startVibration(timeEffect, attribute);
    }).catch((err: Error) => {
      const code: number = (err as BusinessError)?.code ?? 0;
      // 201=权限被拒、801=能力不支持：都属于设备/环境限制，之后不再尝试。
      // 这里只记一次 info，避免静音模式下每次点击都刷日志。
      if (code === 201 || code === 801) {
        if (this.available) {
          this.available = false;
          hilog.info(DOMAIN, TAG, 'Haptic unavailable on this device: code=%{public}d', code);
        }
        return;
      }
      hilog.debug(DOMAIN, TAG, 'vibrate skipped: code=%{public}d, msg=%{public}s', code, err?.message ?? '');
    });
  }

  /** 语义化快捷方法（调用点可读性更好） */
  selection(): void {
    this.play(HapticKind.Selection);
  }

  light(): void {
    this.play(HapticKind.Light);
  }

  medium(): void {
    this.play(HapticKind.Medium);
  }

  heavy(): void {
    this.play(HapticKind.Heavy);
  }

  success(): void {
    this.play(HapticKind.Success);
  }

  warning(): void {
    this.play(HapticKind.Warning);
  }
}

export const hapticService = new HapticServiceImpl();
