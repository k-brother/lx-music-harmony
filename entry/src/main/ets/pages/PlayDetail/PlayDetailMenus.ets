/**
 * 播放页的命令式菜单（倍速 / 歌词显示 / 歌词偏移 / 不喜欢）
 *
 * 全部走 DialogService.appActionMenu（Promise 化 + 超 5 项自动折叠），
 * 页面只接回调，不再出现手写的按钮元组与回调透传。
 */
import { t, tf } from '../../service/LocalizationService';
import { appActionMenu } from '../../service/DialogService';
import type { PlayActionRow, PlayActionSection } from './MoreActionsSheet';

/** 倍速选项（0.5x - 2.0x） */
const SPEED_RATES: string[] = ['0.5', '0.75', '1.0', '1.25', '1.5', '2.0'];
export type LyricDisplayAction = 'translation' | 'roma' | 'word' | 'fontSize' | 'align' | 'progress';
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
  /** 逐字歌词（卡拉OK 高亮） */
  word: boolean;
  fontSize: number;
  alignLabel: string;
  progress: boolean;
}

export async function showLyricDisplayMenu(state: LyricDisplayState): Promise<LyricDisplayAction | null> {
  const mark = (on: boolean): string => on ? '  ✓' : '';
  const items: string[] = [
    `${t('lyric_translation')}${mark(state.translation)}`,
    `${t('lyric_roma')}${mark(state.roma)}`,
    `${t('lyric_word')}${mark(state.word)}`,
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
    return 'word';
  }
  if (picked === 3) {
    return 'fontSize';
  }
  if (picked === 4) {
    return 'align';
  }
  if (picked === 5) {
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

/**
 * 「更多」面板的动作分组内容。
 *
 * 14 个动作平铺时用户要逐行找，这里按用途分成四组（与主流播放器的「⋯」菜单一致）：
 * 歌曲信息与来源 / 播放相关 / 歌词相关 / 保存与分享。
 * 其中三项文案随状态变化（定时等待态、当前在封面页还是歌词页、桌面歌词开关），
 * 所以由调用方把状态传进来、每次渲染重新构造。
 */
export interface PlayActionState {
  /** 定时器已到点、正在等当前歌曲播完 */
  sleepWaitingTrackEnd: boolean;
  /** 0=封面页，1=歌词页 */
  currentTab: number;
  desktopLyricOn: boolean;
  /** 宽屏封面/歌词同屏，此时不再提供「切换封面/歌词」动作 */
  wideLayout: boolean;
}

export function buildPlayActionSections(state: PlayActionState): PlayActionSection[] {
  const lyricRows: PlayActionRow[] = [
    { key: 'lyricOffset', icon: $r('app.media.ic_pd_lyric'), label: t('lyric_offset') },
    { key: 'lyricDisplay', icon: $r('app.media.ic_pd_lyric'), label: t('lyric_display') },
    {
      key: 'desktopLyric',
      icon: $r('app.media.ic_pd_lyric'),
      label: state.desktopLyricOn ? t('close_desktop_lyric') : t('open_desktop_lyric'),
    },
  ];
  if (!state.wideLayout) {
    // 窄屏才需要「封面/歌词」二选一，大屏两个都在屏幕上
    lyricRows.unshift({
      key: 'switchTab',
      icon: $r('app.media.ic_pd_lyric'),
      label: state.currentTab === 0 ? t('switch_to_lyric') : t('switch_to_cover'),
    });
  }

  return [
    {
      title: t('player_action_group_song'),
      rows: [
        { key: 'addToList', icon: $r('app.media.ic_pd_playlist'), label: t('player_add_to_list') },
        { key: 'comment', icon: $r('app.media.ic_pd_comment'), label: t('player_comment') },
        { key: 'dislike', icon: $r('app.media.ic_pd_comment'), label: t('dislike_title') },
        { key: 'switchSource', icon: $r('app.media.ic_pd_loop'), label: t('switch_source') },
      ],
    },
    {
      title: t('player_action_group_play'),
      rows: [
        { key: 'speed', icon: $r('app.media.ic_pd_timer'), label: t('play_speed') },
        { key: 'volume', icon: $r('app.media.ic_pd_timer'), label: t('settings_volume') },
        {
          key: 'sleepTimer',
          icon: $r('app.media.ic_pd_timer'),
          label: state.sleepWaitingTrackEnd ? t('sleep_cancel_wait') : t('sleep_timer_setting'),
        },
        { key: 'queue', icon: $r('app.media.ic_pd_playlist'), label: t('play_queue') },
      ],
    },
    {
      title: t('player_action_group_lyric'),
      rows: lyricRows,
    },
    {
      title: t('player_action_group_save'),
      rows: [
        { key: 'saveLyric', icon: $r('app.media.ic_pd_lyric'), label: t('media_save_lyric') },
        { key: 'saveCover', icon: $r('app.media.ic_pd_comment'), label: t('media_save_cover') },
      ],
    },
  ];
}
