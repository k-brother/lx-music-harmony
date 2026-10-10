/**
 * 实况窗（LiveView）跨进程契约 —— 叶子文件，service 与 liveview 进程都只准从这里取常量。
 *
 * 写入方分工：
 * - UI 进程 LiveViewService 创建/更新实况窗，并把歌词负载经 common event 广播给锁屏进程；
 * - 锁屏进程 LiveViewAbility + LockScreenPage 只读负载渲染，不回写。
 *
 * 注意：锁屏扩展运行在独立进程，拿不到应用的 LocalizationService，
 * 所有界面文案都由 UI 进程翻译好随负载下发（playingLabel/pausedLabel/noLyricLabel）。
 */

/** 应用唯一的音乐实况窗 id（固定值，开发者生成） */
export const LIVE_VIEW_ID: number = 1001;

/** LiveView Kit 没有音乐场景，用通用 TIMER（计时）场景（对齐对方项目验证过的做法） */
export const LIVE_VIEW_EVENT: string = 'TIMER';

/** module.json5 注册的锁屏扩展名 */
export const LIVE_VIEW_LOCK_ABILITY: string = 'LiveViewAbility';

/** want.parameters 里首帧负载的键 */
export const LIVE_VIEW_PARAM_KEY: string = 'liveViewParameters';

/** UI 进程 → 锁屏进程的歌词更新广播名 */
export const LIVE_VIEW_LYRIC_EVENT: string = 'com.lxmusic.mobile.LIVE_VIEW_LYRIC_UPDATE';

/** 锁屏页 LocalStorage 首帧键 */
export const LS_INIT_DATA_KEY: string = 'liveViewInitData';

/** 广播与 want.parameters 共用的负载形状（JSON 序列化传输） */
export interface LiveViewLyricPayload {
  title: string;
  artist: string;
  curLine: string;
  nextLine: string;
  isPlaying: boolean;
  /** 以下文案由 UI 进程本地化后下发（锁屏进程没有 LocalizationService） */
  playingLabel: string;
  pausedLabel: string;
  noLyricLabel: string;
}
