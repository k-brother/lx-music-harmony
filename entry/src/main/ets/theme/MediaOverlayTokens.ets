/**
 * 媒体层调色板（画在专辑封面 / 锁屏遮罩之上的统一样式）
 *
 * 与 DesignTokens 的区别：DesignTokens 是按**应用主题**（浅/深色）取值的页面配色；
 * 桌面卡片与锁屏实况窗的底色是**封面图或系统锁屏遮罩**，与主题无关，
 * 硬套主题 token 会让这两处失去"浮在图上"的层次。所以单独一份**不带 theme 参数**的调色板。
 *
 * 约定：卡片页（widget/pages）与锁屏页（liveview/pages）只允许从这里取色，
 * 字面量只出现在本文件；check_design_tokens.py 已把这两个目录纳入扫描范围。
 */

/** 主文案（标题、当前歌词强调行） */
export const onMediaTextPrimary: string = '#CCFFFFFF';
/** 次级文案（歌手、副标题） */
export const onMediaTextSecondary: string = '#B3FFFFFF';
/** 三级文案（歌单来源等弱信息） */
export const onMediaTextTertiary: string = '#99FFFFFF';
/** 最弱文案 / 分隔描边（未播放态图标、线条） */
export const onMediaTextFaint: string = '#66FFFFFF';

/** 歌词未唱行 */
export const onMediaLyricIdle: string = '#59FFFFFF';

/** 控件底（弱）：描边、图标按钮底 */
export const onMediaFillWeak: string = '#26FFFFFF';
/** 控件底（强）：主播放按钮底 */
export const onMediaFillStrong: string = '#40FFFFFF';

/** 无封面时的兜底底板 */
export const onMediaSurface: string = '#1F2226';
/** 卡片内文字压暗遮罩 */
export const onMediaScrim: string = '#99000000';
/** 锁屏沉浸页整体遮罩（更深，保证文字可读） */
export const lockScreenScrim: string = '#E6000000';

/**
 * 实况窗强调色（播放中圆点等）。
 * 刻意对齐系统实况窗的观感，语义独立于应用主题的 accent（红色），不要用 DesignTokens.accent 替换。
 */
export const liveViewAccent: string = '#07C556';
