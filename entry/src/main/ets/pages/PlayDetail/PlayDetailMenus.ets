/**
 * 播放页的命令式菜单（倍速 / 歌词显示 / 歌词偏移 / 不喜欢）
 *
 * 全部走 DialogService.appActionMenu（Promise 化 + 超 5 项自动折叠），
 * 页面只接回调，不再出现手写的按钮元组与回调透传。
 */
import { t, tf } from '../../service/LocalizationService';
import { appActionMenu } from '../../service/DialogService';

/** 倍速选项（0.5x - 2.0x） */
const SPEED_RATES: string[] = ['0.5', '0.75', '1.0', '1.25', '1.5', '2.0'];
export type LyricDisplayAction = 'translation' | 'roma' | 'fontSize' | 'align' | 'progress';
export type DislikeLevel = 'song' | 'singer' | 'name';

/** 倍速选择：返回选中的倍速（取消返回 null） */
export async function showSpeedMenu(current: number): Promise<number | null> {
  const items: string[] = [];
  for (let i = 0; i < SPEED_RATES.length; i++) {
    const rate = parseFloat(SPEED_RATES[i]);
    const mark = Math.abs(rate - current) < 0.01 ? '  ✓' : '';
    items.push(`${SPEED_RATES[i]}x${mark}`);
  }
  const picked = await appActionMenu(t('play_speed'), items);
  if (picked < 0) {
    return null;
  }
  return parseFloat(SPEED_RATES[picked]);
}

/** 歌词显示设置：返回要切换的项（取消返回 null） */
export interface LyricDisplayState {
  translation: boolean;
  roma: boolean;
  fontSize: number;
  alignLabel: string;
  progress: boolean;
}

export async function showLyricDisplayMenu(state: LyricDisplayState): Promise<LyricDisplayAction | null> {
  const mark = (on: boolean): string => on ? '  ✓' : '';
  const items: string[] = [
    `${t('lyric_translation')}${mark(state.translation)}`,
    `${t('lyric_roma')}${mark(state.roma)}`,
    `${t('lyric_font_size')}: ${state.fontSize}`,
    `${t('lyric_align')}: ${state.alignLabel}`,
    `${t('lyric_progress')}${mark(state.progress)}`,
  ];
  const picked = await appActionMenu(t('lyric_display'), items);
  if (picked === 0) {
    return 'translation';
  }
  if (picked === 1) {
    return 'roma';
  }
  if (picked === 2) {
    return 'fontSize';
  }
  if (picked === 3) {
    return 'align';
  }
  if (picked === 4) {
    return 'progress';
  }
  return null;
}

/** 不喜欢：返回粒度（取消返回 null） */
export async function showDislikeMenu(): Promise<DislikeLevel | null> {
  const picked = await appActionMenu(t('dislike_title'), [
    t('dislike_song'),
    t('dislike_singer'),
    t('dislike_name'),
  ]);
  if (picked === 0) {
    return 'song';
  }
  if (picked === 1) {
    return 'singer';
  }
  if (picked === 2) {
    return 'name';
  }
  return null;
}

/** 后续动作提示文案（用于切歌/切源后的统一 toast） */
export function speedToast(rate: number): string {
  return tf('play_speed_set', [`${rate}x`]);
}
