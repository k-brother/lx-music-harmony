/**
 * 播放页「播放设置类」动作
 *
 * 都是「弹一个菜单 → 写设置 → 回一句提示」的同一套路：
 * 歌词显示（翻译/罗马音/字号/对齐/进度）、定时退出、播放模式轮转。
 * 页面只负责把返回的提示显示出来，不再被这些分支撑开。
 */
import { t } from '../../service/LocalizationService';
import { settingsService } from '../../service/SettingsService';
import { sleepTimerService } from '../../service/SleepTimerService';
import { appActionMenu } from '../../service/DialogService';
import { showLyricDisplayMenu } from './PlayDetailMenus';

/** 播放模式轮转顺序（与设置页一致：列表循环 → 单曲循环 → 随机 → 顺序） */
const PLAY_MODES: string[] = ['listLoop', 'singleLoop', 'random', 'sequential'];

/** 歌词对齐方式的可读文案 */
export function lyricAlignLabel(mode: string): string {
  if (mode === 'left') {
    return t('lyric_align_left');
  }
  if (mode === 'right') {
    return t('lyric_align_right');
  }
  return t('lyric_align_center');
}

/** 播放模式的可读文案 */
export function playModeText(mode: string): string {
  switch (mode) {
    case 'listLoop': return t('mode_list_loop');
    case 'singleLoop': return t('mode_single_loop');
    case 'random': return t('mode_random');
    case 'sequential': return t('mode_sequential');
    default: return t('mode_list_loop');
  }
}

/** 轮转到下一个播放模式 */
export function nextPlayMode(current: string): string {
  const index = PLAY_MODES.indexOf(current);
  const next = index >= 0 ? (index + 1) % PLAY_MODES.length : 0;
  return PLAY_MODES[next];
}

/** 歌词显示设置的结果 */
export interface LyricDisplayOutcome {
  /** 给用户看的提示（已含开关状态/新值） */
  toast: string;
  /** 是否改动了罗马音开关（需要调用方重建罗马音行） */
  romaChanged: boolean;
}

/**
 * 歌词显示设置菜单：翻译 / 罗马音 / 字号 / 对齐 / 进度。
 * 每项点一次即轮转或开关，立即写设置并返回提示；取消返回 null。
 */
export async function applyLyricDisplayChoice(): Promise<LyricDisplayOutcome | null> {
  const settings = settingsService.get();
  const action = await showLyricDisplayMenu({
    translation: settings.showLyricTranslation,
    roma: settings.showLyricRoma,
    fontSize: settings.lyricFontSize,
    alignLabel: lyricAlignLabel(settings.lyricAlign),
    progress: settings.showLyricProgress,
  });
  if (action === null) {
    return null;
  }
  if (action === 'translation') {
    const next = !settings.showLyricTranslation;
    await settingsService.update({ showLyricTranslation: next });
    return { toast: `${t('lyric_translation')}: ${next ? t('on') : t('off')}`, romaChanged: false };
  }
  if (action === 'roma') {
    const next = !settings.showLyricRoma;
    await settingsService.update({ showLyricRoma: next });
    return { toast: `${t('lyric_roma')}: ${next ? t('on') : t('off')}`, romaChanged: true };
  }
  if (action === 'fontSize') {
    const sizes: number[] = [14, 16, 18, 20, 22, 24];
    const index = sizes.indexOf(settings.lyricFontSize);
    const nextSize = sizes[(index + 1) % sizes.length];
    await settingsService.update({ lyricFontSize: nextSize });
    return { toast: `${t('lyric_font_size')}: ${nextSize}`, romaChanged: false };
  }
  if (action === 'align') {
    const modes: string[] = ['center', 'left', 'right'];
    const index = modes.indexOf(settings.lyricAlign);
    const nextAlign = modes[(index + 1) % modes.length];
    await settingsService.update({ lyricAlign: nextAlign });
    return { toast: `${t('lyric_align')}: ${lyricAlignLabel(nextAlign)}`, romaChanged: false };
  }
  const next = !settings.showLyricProgress;
  await settingsService.update({ showLyricProgress: next });
  return { toast: `${t('lyric_progress')}: ${next ? t('on') : t('off')}`, romaChanged: false };
}

/** 定时退出的结果 */
export interface SleepTimerOutcome {
  /** 定时是否处于开启状态 */
  enabled: boolean;
  /** 按钮/行上显示的文案 */
  label: string;
  toast: string;
}

/**
 * 定时退出菜单：15 / 30 / 60 分钟或关闭。
 * 计时统一交给 SleepTimerService，保证与设置页状态一致；取消返回 null。
 */
export async function chooseSleepTimer(): Promise<SleepTimerOutcome | null> {
  // 走 DialogService：取消项由系统菜单提供，避免出现两个「取消」
  const index = await appActionMenu(t('sleep_timer_setting'), [
    t('sleep_15min'),
    t('sleep_30min'),
    t('sleep_60min'),
    t('sleep_disable'),
  ]);
  if (index < 0 || index > 3) {
    return null;
  }
  if (index === 3) {
    sleepTimerService.stop();
    sleepTimerService.cancelPendingExit();
    return { enabled: false, label: t('sleep_timer_setting'), toast: t('toast_sleep_cancel') };
  }
  const minutes = index === 0 ? 15 : (index === 1 ? 30 : 60);
  sleepTimerService.start(minutes);
  return {
    enabled: true,
    label: `${minutes} ${t('settings_sleep_minutes')}`,
    toast: `${t('toast_sleep_set')} ${minutes} ${t('toast_sleep_start')}`,
  };
}

/** 取消「等待当前歌曲播完」的挂起退出 */
export function cancelPendingSleepExit(): string {
  sleepTimerService.cancelPendingExit();
  return t('toast_sleep_cancel');
}
