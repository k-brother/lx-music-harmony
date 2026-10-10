/**
 * 设置项的类型定义与默认值
 *
 * 从 SettingsService 拆出：类型被页面/服务广泛引用，默认值只在加载时用一次，
 * 单独成文件后「设置有哪些字段」一目了然。
 */
import type { S2TMode } from '../../core/lyric/ChineseConvert';
import type { DownloadFileNameFormat } from '../../core/music/MusicTitle';
import { toBuiltinSourceId } from '../../core/music/SourcePolicy';
import type { Quality } from '../../types/MusicTypes';
import type { BuiltinSource } from '../../types/MusicSource';

export type { S2TMode, DownloadFileNameFormat };
export { toDownloadFileNameFormat } from '../../core/music/MusicTitle';

/** 播放模式 */
export type PlayMode = 'listLoop' | 'singleLoop' | 'random' | 'sequential';
/** 主题明暗模式 */
export type ThemeMode = 'light' | 'dark';
/** 启动页面 */
export type StartupPage = 'home' | 'playdetail';
/** 添加歌曲到列表的位置 */
export type AddMusicLocation = 'top' | 'bottom';
/** 桌面歌词位置（custom = 用户拖动后的自由位置） */
export type DesktopLyricPosition = 'top' | 'middle' | 'bottom' | 'custom';
/** 桌面歌词文字在窗口内的水平位置 */
export type DesktopLyricTextPositionX = 'left' | 'center' | 'right';
/** 桌面歌词文字在窗口内的垂直位置 */
export type DesktopLyricTextPositionY = 'top' | 'middle' | 'bottom';
/** 桌面歌词字重 */
export type DesktopLyricFontWeight = 'light' | 'normal' | 'medium' | 'bold';
/**
 * 桌面歌词行切换动画。
 * slide = 下一句从下方滑入（主流播放器做法）；fade = 淡入淡出；none = 直接切换
 */
export type DesktopLyricAnimStyle = 'slide' | 'fade' | 'none';
/** 同步模式 */
export type SyncMode = 'client' | 'server';
/** 音源名称显示方式：别名（小蜗音乐…） / 原名（酷我音乐…） */
export type SourceNameType = 'alias' | 'real';
/** 分享方式：系统分享 / 复制文本（安卓版 common.shareType） */
export type ShareType = 'system' | 'clipboard';

/** 设置快照（读取时使用，全部为已解析的强类型值） */
export interface AppSettings {
  // 基础
  language: string;
  startupPage: StartupPage;
  showExitDialog: boolean;
  themeMode: ThemeMode;
  themeId: string;
  /** 自动跟随系统深浅色（安卓版 common.isAutoTheme） */
  autoTheme: boolean;
  /** 自动模式下的浅色主题 id */
  themeLightId: string;
  /** 自动模式下的深色主题 id */
  themeDarkId: string;
  /** 动态背景：用当前歌曲封面作为播放页背景（安卓版 theme.dynamicBg） */
  dynamicBg: boolean;
  /** 字体阴影：提升封面背景上的文字可读性（安卓版 theme.fontShadow） */
  fontShadow: boolean;
  /** 深色主题下隐藏背景图（安卓版 theme.hideBgDark） */
  hideBgDark: boolean;

  // 播放
  autoPlay: boolean;
  highQuality: boolean;
  /** 播放音质：128k / 320k / flac / flac24bit（安卓版 player.playQuality，默认 128k） */
  playQuality: Quality;
  playMode: PlayMode;
  /** 播放倍速（0.5 - 2.0） */
  playRate: number;
  /** 是否处理音频焦点（来电/其他应用播放时自动暂停） */
  audioFocus: boolean;
  /** 是否启用 AudioOffload（低功耗硬解，部分设备/格式不支持） */
  audioOffload: boolean;
  /** 播放缓存上限（MB） */
  playerCacheSizeMb: number;
  /** 是否保存播放进度（重启续播） */
  savePlayTime: boolean;
  /** 播控中心/锁屏是否显示封面（安卓版 player.isShowNotificationImage） */
  showNotificationImage: boolean;
  /**
   * 蓝牙/车机歌词：把整段 LRC 写入 AVSession 元数据
   * （安卓版 player.isShowBluetoothLyric；关闭时只推送当前句，播控/锁屏仍正常）
   */
  showBluetoothLyric: boolean;
  /** 歌词是否显示翻译 */
  showLyricTranslation: boolean;
  /** 歌词是否显示罗马音（拼音） */
  showLyricRoma: boolean;
  /** 本地音乐自动在线匹配歌词/封面（关闭后仍可手动匹配） */
  autoMatchLocalLyric: boolean;
  /** 逐字歌词：有逐字数据的歌按字高亮（卡拉OK 效果） */
  wordLyric: boolean;
  /** 歌词字号（14-24） */
  lyricFontSize: number;
  /** 歌词对齐：center | left | right */
  lyricAlign: string;
  /** 歌词页是否显示播放进度 */
  showLyricProgress: boolean;
  /** 桌面歌词宽度（屏宽百分比 40-100） */
  desktopLyricWidth: number;
  /** 桌面歌词最大显示行数（1-3） */
  desktopLyricMaxLines: number;
  /** 桌面歌词行切换动画 */
  desktopLyricAnim: boolean;
  /** 桌面歌词阴影色（文字投影，用于和背景拉开层次） */
  desktopLyricShadowColor: string;
  /**
   * 桌面歌词描边宽度 vp（0 = 关闭，1-3）。
   * 透明背景下靠描边保证任何壁纸上都能看清，这是"没有黑底也自然"的关键。
   */
  desktopLyricOutlineWidth: number;
  /** 桌面歌词描边颜色 */
  desktopLyricOutlineColor: string;
  /** 桌面歌词字重 */
  desktopLyricFontWeight: DesktopLyricFontWeight;
  /** 桌面歌词面板圆角 vp */
  desktopLyricCornerRadius: number;
  /** 桌面歌词面板左右内边距 vp */
  desktopLyricPadding: number;
  /** 桌面歌词行切换动画方式 */
  desktopLyricAnimStyle: DesktopLyricAnimStyle;
  /** 列表是否显示音源 */
  showListSource: boolean;
  /** 触感反馈（切 Tab / 播放暂停 / 长按菜单等操作的轻微振动） */
  hapticFeedback: boolean;
  /** 列表是否显示专辑名 */
  showListAlbum: boolean;
  /** 列表是否显示时长 */
  showListDuration: boolean;
  /** 是否记住列表滚动位置 */
  rememberScrollPosition: boolean;
  /** 是否记录详细日志（DEBUG/INFO 级），用于「设置 → 运行日志」排查问题 */
  enableVerboseLog: boolean;
  /** 歌词简繁转换模式（off / s2t / t2s） */
  s2tMode: S2TMode;
  /** 音源名称显示：align with 安卓版 common.sourceNameType */
  sourceNameType: SourceNameType;
  /** 音源启用顺序（靠前的优先；搜索聚合与自动跨源切换都按此顺序） */
  sourceOrder: BuiltinSource[];
  /** 已停用的音源（搜索聚合与自动切换都跳过） */
  disabledSources: BuiltinSource[];
  /** 取源失败时自动跨源切换（关闭则取不到就直接跳过） */
  autoSourceSwitch: boolean;
  /** 分享方式：系统分享 / 复制文本（安卓版 common.shareType，默认系统分享） */
  shareType: ShareType;
  /** 是否已同意许可协议（安卓版 common.isAgreePact），首次启动必须同意 */
  agreedPact: boolean;
  /** 是否允许拖动播放进度条（关闭后不可拖动，防误触） */
  allowProgressBarSeek: boolean;
  /** 歌词偏移（秒）：正值=歌词提前出现 */
  lyricOffset: number;
  /** 0-100 */
  volume: number;
  sleepTimerEnabled: boolean;
  sleepTimerMinutes: number;
  /** 定时退出时是否等待当前歌曲播放完（安卓版 player.timeoutExitPlayed） */
  sleepTimerWaitTrackEnd: boolean;
  showDesktopLyric: boolean;
  /** 系统实况窗（锁屏/胶囊歌词）：总开关，另受系统实况窗开关约束 */
  enableLiveView: boolean;
  desktopLyricPosition: DesktopLyricPosition;
  desktopLyricColor: string;
  /** 歌词窗口背景不透明度 0-100（0 = 全透明） */
  desktopLyricBgAlpha: number;
  /** 单行模式：只显示当前句（安卓版 desktopLyric.isSingleLine） */
  desktopLyricSingleLine: boolean;
  /** 当前句（已播放行）颜色（安卓版 desktopLyric.style.lyricPlayedColor） */
  desktopLyricPlayedColor: string;
  /** 歌词文字在窗口内的水平位置 left | center | right */
  desktopLyricTextPositionX: DesktopLyricTextPositionX;
  /** 歌词文字在窗口内的垂直位置 top | middle | bottom */
  desktopLyricTextPositionY: DesktopLyricTextPositionY;
  /** 歌词文字不透明度 0-100（安卓版 desktopLyric.style.opacity，默认 100） */
  desktopLyricTextOpacity: number;
  /** 歌词字号 14-32 */
  desktopLyricFontSize: number;
  /** 是否显示下一句 */
  desktopLyricShowNext: boolean;
  /** 锁定后不可拖动/点击穿透 */
  desktopLyricLocked: boolean;
  /** 自定义位置（position=custom 时生效），-1 表示未设置 */
  desktopLyricX: number;
  desktopLyricY: number;

  // 搜索
  searchSource: string;
  showHotSearch: boolean;
  /** 搜索面板是否显示搜索历史（安卓版 search.isShowHistorySearch） */
  showSearchHistory: boolean;
  searchHistoryCount: number;

  // 列表
  addMusicLocation: AddMusicLocation;
  autoCleanPlayedList: boolean;
  /** 点击列表项时是否整列表播放（安卓版 list.isClickPlayList） */
  listClickPlay: boolean;

  // 下载
  downloadPath: string;
  /** 下载时是否每次都拉起系统文件选择器（默认关闭：写不进配置目录时留在应用目录，不打扰） */
  downloadUseFilePicker: boolean;
  /** 下载文件名格式（安卓版 download.fileName）：歌名 - 歌手 / 歌手 - 歌名 / 歌名 */
  downloadFileName: DownloadFileNameFormat;
  autoStartDownload: boolean;
  maxConcurrentDownloads: number;

  // 同步
  syncEnabled: boolean;
  syncServer: string;
  syncKey: string;
  syncInterval: number;
  syncAutoSync: boolean;
  syncMode: SyncMode;

  // 外观
  fontSize: number;
  showAnimation: boolean;
}

/** 设置补丁：只写需要变更的字段 */
export interface SettingsPatch {
  language?: string;
  startupPage?: StartupPage;
  showExitDialog?: boolean;
  themeMode?: ThemeMode;
  themeId?: string;
  autoTheme?: boolean;
  themeLightId?: string;
  themeDarkId?: string;
  dynamicBg?: boolean;
  fontShadow?: boolean;
  hideBgDark?: boolean;

  autoPlay?: boolean;
  highQuality?: boolean;
  playQuality?: Quality;
  playMode?: PlayMode;
  playRate?: number;
  audioFocus?: boolean;
  audioOffload?: boolean;
  playerCacheSizeMb?: number;
  savePlayTime?: boolean;
  showNotificationImage?: boolean;
  showBluetoothLyric?: boolean;
  showLyricTranslation?: boolean;
  showLyricRoma?: boolean;
  autoMatchLocalLyric?: boolean;
  /** 逐字歌词（卡拉OK 高亮） */
  wordLyric?: boolean;
  lyricFontSize?: number;
  lyricAlign?: string;
  showLyricProgress?: boolean;
  desktopLyricWidth?: number;
  desktopLyricMaxLines?: number;
  desktopLyricSingleLine?: boolean;
  desktopLyricPlayedColor?: string;
  desktopLyricTextPositionX?: DesktopLyricTextPositionX;
  desktopLyricTextPositionY?: DesktopLyricTextPositionY;
  desktopLyricTextOpacity?: number;
  desktopLyricAnim?: boolean;
  desktopLyricShadowColor?: string;
  desktopLyricOutlineWidth?: number;
  desktopLyricOutlineColor?: string;
  desktopLyricFontWeight?: DesktopLyricFontWeight;
  desktopLyricCornerRadius?: number;
  desktopLyricPadding?: number;
  desktopLyricAnimStyle?: DesktopLyricAnimStyle;
  showListSource?: boolean;
  hapticFeedback?: boolean;
  showListAlbum?: boolean;
  showListDuration?: boolean;
  rememberScrollPosition?: boolean;
  enableVerboseLog?: boolean;
  s2tMode?: S2TMode;
  sourceNameType?: SourceNameType;
  sourceOrder?: BuiltinSource[];
  disabledSources?: BuiltinSource[];
  autoSourceSwitch?: boolean;
  shareType?: ShareType;
  agreedPact?: boolean;
  allowProgressBarSeek?: boolean;
  lyricOffset?: number;
  volume?: number;
  sleepTimerEnabled?: boolean;
  sleepTimerMinutes?: number;
  sleepTimerWaitTrackEnd?: boolean;
  showDesktopLyric?: boolean;
  enableLiveView?: boolean;
  desktopLyricPosition?: DesktopLyricPosition;
  desktopLyricColor?: string;
  desktopLyricBgAlpha?: number;
  desktopLyricFontSize?: number;
  desktopLyricShowNext?: boolean;
  desktopLyricLocked?: boolean;
  desktopLyricX?: number;
  desktopLyricY?: number;

  searchSource?: string;
  showHotSearch?: boolean;
  showSearchHistory?: boolean;
  searchHistoryCount?: number;

  addMusicLocation?: AddMusicLocation;
  autoCleanPlayedList?: boolean;
  listClickPlay?: boolean;

  downloadPath?: string;
  downloadUseFilePicker?: boolean;
  downloadFileName?: DownloadFileNameFormat;
  autoStartDownload?: boolean;
  maxConcurrentDownloads?: number;

  syncEnabled?: boolean;
  syncServer?: string;
  syncKey?: string;
  syncInterval?: number;
  syncAutoSync?: boolean;
  syncMode?: SyncMode;

  fontSize?: number;
  showAnimation?: boolean;
}

/** 默认值 */
export function createDefaultSettings(): AppSettings {
  return {
    language: 'zh-CN',
    startupPage: 'home',
    showExitDialog: true,
    themeMode: 'light',
    themeId: 'green',
    autoTheme: false,
    themeLightId: 'green',
    themeDarkId: 'black',
    dynamicBg: false,
    fontShadow: false,
    hideBgDark: false,

    autoPlay: true,
    highQuality: true,
    playQuality: '128k',
    playMode: 'listLoop',
    playRate: 1.0,
    audioFocus: true,
    audioOffload: false,
    playerCacheSizeMb: 4,
    savePlayTime: true,
    showNotificationImage: true,
    showBluetoothLyric: false,
    showLyricTranslation: true,
    wordLyric: true,
    showLyricRoma: false,
    autoMatchLocalLyric: true,
    lyricFontSize: 16,
    lyricAlign: 'center',
    showLyricProgress: false,
    desktopLyricWidth: 100,
    desktopLyricMaxLines: 2,
    desktopLyricSingleLine: false,
    desktopLyricPlayedColor: '#07C556',
    desktopLyricTextPositionX: 'left',
    desktopLyricTextPositionY: 'top',
    desktopLyricTextOpacity: 100,
    desktopLyricAnim: true,
    desktopLyricShadowColor: '#99000000',
    desktopLyricOutlineWidth: 1,
    desktopLyricOutlineColor: '#CC000000',
    desktopLyricFontWeight: 'medium',
    desktopLyricCornerRadius: 12,
    desktopLyricPadding: 16,
    desktopLyricAnimStyle: 'slide',
    showListSource: true,
    hapticFeedback: true,
    showListAlbum: true,
    showListDuration: true,
    rememberScrollPosition: true,
    enableVerboseLog: false,
    s2tMode: 'off',
    sourceNameType: 'alias',
    sourceOrder: ['kw', 'kg', 'tx', 'wy', 'mg'],
    disabledSources: [],
    autoSourceSwitch: true,
    shareType: 'system',
    agreedPact: false,
    allowProgressBarSeek: true,
    lyricOffset: 0,
    volume: 80,
    sleepTimerEnabled: false,
    sleepTimerMinutes: 30,
    sleepTimerWaitTrackEnd: true,
    showDesktopLyric: false,
    enableLiveView: false,
    desktopLyricPosition: 'top',
    desktopLyricColor: '#FFFFFF',
    desktopLyricBgAlpha: 0,
    desktopLyricFontSize: 18,
    desktopLyricShowNext: true,
    desktopLyricLocked: false,
    desktopLyricX: -1,
    desktopLyricY: -1,

    searchSource: 'kw',
    showHotSearch: true,
    showSearchHistory: false,
    searchHistoryCount: 20,

    addMusicLocation: 'top',
    autoCleanPlayedList: false,
    listClickPlay: false,

    downloadPath: '',
    downloadUseFilePicker: false,
    downloadFileName: 'name-singer',
    autoStartDownload: true,
    maxConcurrentDownloads: 1,

    syncEnabled: false,
    syncServer: '',
    syncKey: '',
    syncInterval: 30,
    syncAutoSync: true,
    syncMode: 'client',

    fontSize: 14,
    showAnimation: true,
  };
}

/** 旧版本使用的存储实例与键，仅用于一次性迁移 */
const LEGACY_SETTINGS_STORE = 'music_settings';
const LEGACY_DOWNLOAD_STORE = 'download_settings';

export function toPlayMode(value: string, fallback: PlayMode): PlayMode {
  if (value === 'listLoop' || value === 'singleLoop' || value === 'random' || value === 'sequential') {
    return value;
  }
  return fallback;
}

export function toThemeMode(value: string, fallback: ThemeMode): ThemeMode {
  return value === 'dark' ? 'dark' : (value === 'light' ? 'light' : fallback);
}

export function toStartupPage(value: string, fallback: StartupPage): StartupPage {
  return value === 'playdetail' ? 'playdetail' : (value === 'home' ? 'home' : fallback);
}

export function toAddMusicLocation(value: string, fallback: AddMusicLocation): AddMusicLocation {
  return value === 'bottom' ? 'bottom' : (value === 'top' ? 'top' : fallback);
}

export function toDesktopLyricPosition(value: string, fallback: DesktopLyricPosition): DesktopLyricPosition {
  if (value === 'top' || value === 'middle' || value === 'bottom' || value === 'custom') {
    return value;
  }
  return fallback;
}

/** 简繁转换模式容错（历史数据/非法值一律回到 off） */
export function normalizeS2TMode(value: string): S2TMode {
  if (value === 's2t' || value === 't2s') {
    return value;
  }
  return 'off';
}

/** 音源名称显示方式容错（默认别名） */
export function toSourceNameType(value: string): SourceNameType {
  return value === 'real' ? 'real' : 'alias';
}

/**
 * 音源列表容错：逗号分隔存储串 → 强类型列表。
 * 过滤非法 id、去重、保序；空串/全部非法时回退 fallback。
 */
export function toSourceList(value: string, fallback: BuiltinSource[]): BuiltinSource[] {
  const result: BuiltinSource[] = [];
  if (value && value.length > 0) {
    const parts = value.split(',');
    for (let i = 0; i < parts.length; i++) {
      const id = toBuiltinSourceId(parts[i].trim());
      if (id !== null && result.indexOf(id) < 0) {
        result.push(id);
      }
    }
  }
  return result.length > 0 ? result : fallback.slice();
}

/** 音源列表 → 逗号分隔存储串（与 toSourceList 互逆） */
export function sourceListToString(list: BuiltinSource[]): string {
  return list.join(',');
}

/** 两个音源列表是否完全一致（同序同元素；写入时用于「真的变化了才落盘」判断） */
export function isSameSourceList(a: BuiltinSource[], b: BuiltinSource[]): boolean {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}

/** 分享方式容错（默认系统分享，与安卓版一致） */
export function toShareType(value: string): ShareType {
  return value === 'clipboard' ? 'clipboard' : 'system';
}

/** 音质容错（非法值回落到 128k） */
export function toQuality(value: string, fallback: Quality): Quality {
  if (value === '320k' || value === 'flac' || value === 'flac24bit' || value === '128k') {
    return value;
  }
  return fallback;
}

/** 桌面歌词文字水平位置容错 */
export function toDlTextPosX(value: string): DesktopLyricTextPositionX {
  if (value === 'left' || value === 'right') {
    return value;
  }
  return 'center';
}

/** 桌面歌词文字垂直位置容错 */
export function toDlTextPosY(value: string): DesktopLyricTextPositionY {
  if (value === 'top' || value === 'bottom') {
    return value;
  }
  return 'middle';
}

/** 桌面歌词字重容错（非法值回落到 medium） */
export function toDlFontWeight(value: string): DesktopLyricFontWeight {
  if (value === 'light' || value === 'normal' || value === 'bold') {
    return value;
  }
  return 'medium';
}

/** 桌面歌词行切换动画容错（非法值回落到 slide） */
export function toDlAnimStyle(value: string): DesktopLyricAnimStyle {
  if (value === 'fade' || value === 'none') {
    return value;
  }
  return 'slide';
}

/** 数值收敛到 [min, max]，非法值用 fallback（滑块类设置共用） */
export function clampNumber(value: number, min: number, max: number, fallback: number): number {
  if (isNaN(value)) {
    return fallback;
  }
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}
