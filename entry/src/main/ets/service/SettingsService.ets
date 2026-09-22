/**
 * 应用设置服务 - 全应用唯一的设置读写入口。
 *
 * 设计约定：
 * 1. 所有设置项都持久化在 StorageService 使用的同一个 Preferences 实例中，
 *    不再各页面自行 getPreferences('music_settings')，避免出现"设置只写不读、
 *    或读到另一个存储实例"的问题。
 * 2. 首次启动时会把历史版本写在 music_settings / download_settings 里的旧值
 *    迁移过来，保证升级后用户设置不丢。
 * 3. 写设置后统一：更新内存快照 -> 镜像到 AppStorage（驱动 @StorageProp 刷新）
 *    -> 广播 SETTING_CHANGED 事件（驱动服务层刷新）。
 */
import hilog from '@ohos.hilog';
import preferences from '@ohos.data.preferences';
import type { common } from '@kit.AbilityKit';
import { getStorageService } from '../core/interfaces/IStorageService';
import { emitSettingChanged } from './EventBus';
import { StorageKeys } from './StorageService';
import type { S2TMode } from '../core/lyric/ChineseConvert';
import type { Quality } from '../types/MusicTypes';

export type { S2TMode };

const TAG = 'SettingsService';
const DOMAIN = 0x0005;
/** 字号设置 1.0 倍对应的基准值 */
const BASE_FONT_SIZE = 14;

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
  /** 桌面歌词阴影/描边色 */
  desktopLyricShadowColor: string;
  /** 列表是否显示音源 */
  showListSource: boolean;
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
  showListSource?: boolean;
  showListAlbum?: boolean;
  showListDuration?: boolean;
  rememberScrollPosition?: boolean;
  enableVerboseLog?: boolean;
  s2tMode?: S2TMode;
  sourceNameType?: SourceNameType;
  shareType?: ShareType;
  agreedPact?: boolean;
  allowProgressBarSeek?: boolean;
  lyricOffset?: number;
  volume?: number;
  sleepTimerEnabled?: boolean;
  sleepTimerMinutes?: number;
  sleepTimerWaitTrackEnd?: boolean;
  showDesktopLyric?: boolean;
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
function createDefaultSettings(): AppSettings {
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
    showLyricRoma: false,
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
    showListSource: true,
    showListAlbum: true,
    showListDuration: true,
    rememberScrollPosition: true,
    enableVerboseLog: false,
    s2tMode: 'off',
    sourceNameType: 'alias',
    shareType: 'system',
    agreedPact: false,
    allowProgressBarSeek: true,
    lyricOffset: 0,
    volume: 80,
    sleepTimerEnabled: false,
    sleepTimerMinutes: 30,
    sleepTimerWaitTrackEnd: true,
    showDesktopLyric: false,
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

function toPlayMode(value: string, fallback: PlayMode): PlayMode {
  if (value === 'listLoop' || value === 'singleLoop' || value === 'random' || value === 'sequential') {
    return value;
  }
  return fallback;
}

function toThemeMode(value: string, fallback: ThemeMode): ThemeMode {
  return value === 'dark' ? 'dark' : (value === 'light' ? 'light' : fallback);
}

function toStartupPage(value: string, fallback: StartupPage): StartupPage {
  return value === 'playdetail' ? 'playdetail' : (value === 'home' ? 'home' : fallback);
}

function toAddMusicLocation(value: string, fallback: AddMusicLocation): AddMusicLocation {
  return value === 'bottom' ? 'bottom' : (value === 'top' ? 'top' : fallback);
}

function toDesktopLyricPosition(value: string, fallback: DesktopLyricPosition): DesktopLyricPosition {
  if (value === 'top' || value === 'middle' || value === 'bottom' || value === 'custom') {
    return value;
  }
  return fallback;
}

/** 简繁转换模式容错（历史数据/非法值一律回到 off） */
function normalizeS2TMode(value: string): S2TMode {
  if (value === 's2t' || value === 't2s') {
    return value;
  }
  return 'off';
}

/** 音源名称显示方式容错（默认别名） */
function toSourceNameType(value: string): SourceNameType {
  return value === 'real' ? 'real' : 'alias';
}

/** 分享方式容错（默认系统分享，与安卓版一致） */
function toShareType(value: string): ShareType {
  return value === 'clipboard' ? 'clipboard' : 'system';
}

/** 音质容错（非法值回落到 128k） */
function toQuality(value: string, fallback: Quality): Quality {
  if (value === '320k' || value === 'flac' || value === 'flac24bit' || value === '128k') {
    return value;
  }
  return fallback;
}

/** 桌面歌词文字水平位置容错 */
function toDlTextPosX(value: string): DesktopLyricTextPositionX {
  if (value === 'left' || value === 'right') {
    return value;
  }
  return 'center';
}

/** 桌面歌词文字垂直位置容错 */
function toDlTextPosY(value: string): DesktopLyricTextPositionY {
  if (value === 'top' || value === 'bottom') {
    return value;
  }
  return 'middle';
}

function clampNumber(value: number, min: number, max: number, fallback: number): number {
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

class SettingsServiceImpl {
  private values: AppSettings = createDefaultSettings();
  private context: common.UIAbilityContext | null = null;
  private initialized: boolean = false;
  private initPromise: Promise<void> | null = null;

  setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /**
   * 初始化：迁移历史数据 -> 读取设置 -> 同步到 AppStorage / 事件总线。
   * 可重复调用（并发调用共享同一个 Promise）。
   */
  async init(context?: common.UIAbilityContext): Promise<void> {
    if (context) {
      this.setContext(context);
    }
    if (this.initialized) {
      return;
    }
    if (this.initPromise) {
      return this.initPromise;
    }
    this.initPromise = this.doInit();
    try {
      await this.initPromise;
    } finally {
      this.initPromise = null;
    }
  }

  private async doInit(): Promise<void> {
    try {
      await this.migrateLegacySettings();
      await this.loadFromStorage();
      this.initialized = true;
      this.applyToAppStorage();
      this.applyFontScale();
      this.notifyAll();
      hilog.info(DOMAIN, TAG, 'Settings initialized (volume=%{public}d, playMode=%{public}s)',
        this.values.volume, this.values.playMode);
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to initialize settings: %{public}s', msg);
      // 读取失败时保持默认值，避免阻塞启动
      this.initialized = true;
      this.applyToAppStorage();
      this.applyFontScale();
      this.notifyAll();
    }
  }

  /** 迁移旧存储实例中的设置（只执行一次） */
  private async migrateLegacySettings(): Promise<void> {
    if (!this.context) {
      return;
    }
    const storage = getStorageService();
    try {
      const migrated = await storage.getBoolean(StorageKeys.SETTINGS_MIGRATED, false);
      if (migrated) {
        return;
      }

      const legacy = await preferences.getPreferences(this.context, LEGACY_SETTINGS_STORE);
      await this.migrateString(legacy, 'language', StorageKeys.LANGUAGE);
      await this.migrateString(legacy, 'startupPage', StorageKeys.STARTUP_PAGE);
      await this.migrateBoolean(legacy, 'showExitDialog', StorageKeys.SHOW_EXIT_DIALOG);
      await this.migrateString(legacy, 'theme', StorageKeys.THEME_MODE);

      await this.migrateBoolean(legacy, 'autoPlay', StorageKeys.PLAY_AUTO_PLAY);
      await this.migrateBoolean(legacy, 'highQuality', StorageKeys.PLAY_HIGH_QUALITY);
      await this.migrateString(legacy, 'playMode', StorageKeys.PLAY_MODE);
      await this.migrateNumber(legacy, 'volume', StorageKeys.PLAY_VOLUME);
      await this.migrateBoolean(legacy, 'timeoutExit', StorageKeys.PLAY_SLEEP_ENABLED);
      await this.migrateNumber(legacy, 'timeoutMinutes', StorageKeys.PLAY_SLEEP_MINUTES);
      await this.migrateBoolean(legacy, 'showDesktopLyric', StorageKeys.PLAY_DESKTOP_LYRIC);

      await this.migrateString(legacy, 'searchSource', StorageKeys.SEARCH_SOURCE);
      await this.migrateBoolean(legacy, 'showHotSearch', StorageKeys.SEARCH_SHOW_HOT);
      await this.migrateNumber(legacy, 'searchHistoryCount', StorageKeys.SEARCH_HISTORY_LIMIT);

      await this.migrateString(legacy, 'listAddMusicLocation', StorageKeys.LIST_ADD_LOCATION);
      await this.migrateBoolean(legacy, 'autoCleanPlayedList', StorageKeys.LIST_AUTO_CLEAN_PLAYED);

      await this.migrateBoolean(legacy, 'syncEnable', StorageKeys.SYNC_ENABLED);
      await this.migrateString(legacy, 'syncServer', StorageKeys.SYNC_SERVER);
      await this.migrateString(legacy, 'syncKey', StorageKeys.SYNC_KEY);

      await this.migrateNumber(legacy, 'fontSize', StorageKeys.APPEARANCE_FONT_SIZE);
      await this.migrateBoolean(legacy, 'showAnimation', StorageKeys.APPEARANCE_SHOW_ANIMATION);

      // 下载设置历史上存在独立的存储实例
      const legacyDownload = await preferences.getPreferences(this.context, LEGACY_DOWNLOAD_STORE);
      await this.migrateString(legacyDownload, 'downloadPath', StorageKeys.DOWNLOAD_PATH);
      await this.migrateBoolean(legacyDownload, 'autoStartDownload', StorageKeys.DOWNLOAD_AUTO_START);
      await this.migrateNumber(legacyDownload, 'maxConcurrentDownloads', StorageKeys.DOWNLOAD_MAX_CONCURRENT);

      // 旧版同步配置独立存储在 sync_config
      const legacySync = await preferences.getPreferences(this.context, 'sync_config');
      await this.migrateBoolean(legacySync, 'enabled', StorageKeys.SYNC_ENABLED);
      await this.migrateString(legacySync, 'serverUrl', StorageKeys.SYNC_SERVER);
      await this.migrateString(legacySync, 'syncKey', StorageKeys.SYNC_KEY);
      await this.migrateNumber(legacySync, 'syncInterval', StorageKeys.SYNC_INTERVAL);
      await this.migrateBoolean(legacySync, 'autoSync', StorageKeys.SYNC_AUTO_SYNC);

      await storage.setBoolean(StorageKeys.SETTINGS_MIGRATED, true);
      hilog.info(DOMAIN, TAG, 'Legacy settings migrated');
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.warn(DOMAIN, TAG, 'Legacy settings migration skipped: %{public}s', msg);
    }
  }

  private async migrateString(
    legacy: preferences.Preferences, legacyKey: string, targetKey: string
  ): Promise<void> {
    const storage = getStorageService();
    if (await storage.has(targetKey)) {
      return;
    }
    const value = await legacy.get(legacyKey, '') as string;
    if (value && value.length > 0) {
      await storage.setString(targetKey, value);
    }
  }

  private async migrateNumber(
    legacy: preferences.Preferences, legacyKey: string, targetKey: string
  ): Promise<void> {
    const storage = getStorageService();
    if (await storage.has(targetKey)) {
      return;
    }
    const value = await legacy.get(legacyKey, NaN) as number;
    if (!isNaN(value)) {
      await storage.setNumber(targetKey, value);
    }
  }

  private async migrateBoolean(
    legacy: preferences.Preferences, legacyKey: string, targetKey: string
  ): Promise<void> {
    const storage = getStorageService();
    if (await storage.has(targetKey)) {
      return;
    }
    const hasValue = await legacy.has(legacyKey);
    if (hasValue) {
      const value = await legacy.get(legacyKey, false) as boolean;
      await storage.setBoolean(targetKey, value);
    }
  }

  private async loadFromStorage(): Promise<void> {
    const storage = getStorageService();
    const defaults = createDefaultSettings();

    this.values.language = await storage.getString(StorageKeys.LANGUAGE, defaults.language);
    this.values.startupPage = toStartupPage(
      await storage.getString(StorageKeys.STARTUP_PAGE, defaults.startupPage), defaults.startupPage);
    this.values.showExitDialog = await storage.getBoolean(StorageKeys.SHOW_EXIT_DIALOG, defaults.showExitDialog);
    this.values.themeMode = toThemeMode(
      await storage.getString(StorageKeys.THEME_MODE, defaults.themeMode), defaults.themeMode);
    this.values.themeId = await storage.getString(StorageKeys.THEME_ID, defaults.themeId);
    this.values.autoTheme = await storage.getBoolean(StorageKeys.COMMON_AUTO_THEME, defaults.autoTheme);
    this.values.themeLightId = await storage.getString(StorageKeys.THEME_LIGHT_ID, defaults.themeLightId);
    this.values.themeDarkId = await storage.getString(StorageKeys.THEME_DARK_ID, defaults.themeDarkId);
    this.values.dynamicBg = await storage.getBoolean(StorageKeys.THEME_DYNAMIC_BG, defaults.dynamicBg);
    this.values.fontShadow = await storage.getBoolean(StorageKeys.THEME_FONT_SHADOW, defaults.fontShadow);
    this.values.hideBgDark = await storage.getBoolean(StorageKeys.THEME_HIDE_BG_DARK, defaults.hideBgDark);

    this.values.autoPlay = await storage.getBoolean(StorageKeys.PLAY_AUTO_PLAY, defaults.autoPlay);
    this.values.highQuality = await storage.getBoolean(StorageKeys.PLAY_HIGH_QUALITY, defaults.highQuality);
    // 音质：旧版本只有「高品质」开关，首次读不到 playQuality 时按开关值迁移
    const legacyQualityKey = await storage.getString(StorageKeys.PLAY_QUALITY, '');
    this.values.playQuality = legacyQualityKey.length > 0
      ? toQuality(legacyQualityKey, defaults.playQuality)
      : (this.values.highQuality ? 'flac24bit' : defaults.playQuality);
    this.values.playMode = toPlayMode(
      await storage.getString(StorageKeys.PLAY_MODE, defaults.playMode), defaults.playMode);
    this.values.playRate = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_RATE, defaults.playRate), 0.5, 2.0, defaults.playRate);
    this.values.savePlayTime = await storage.getBoolean(StorageKeys.PLAY_SAVE_TIME, defaults.savePlayTime);
    this.values.showNotificationImage = await storage.getBoolean(
      StorageKeys.PLAY_NOTIFICATION_IMAGE, defaults.showNotificationImage);
    this.values.showBluetoothLyric = await storage.getBoolean(
      StorageKeys.PLAY_BLUETOOTH_LYRIC, defaults.showBluetoothLyric);
    this.values.showLyricTranslation = await storage.getBoolean(
      StorageKeys.LYRIC_SHOW_TRANSLATION, defaults.showLyricTranslation);
    this.values.showLyricRoma = await storage.getBoolean(StorageKeys.LYRIC_SHOW_ROMA, defaults.showLyricRoma);
    this.values.lyricFontSize = clampNumber(
      await storage.getNumber(StorageKeys.LYRIC_FONT_SIZE, defaults.lyricFontSize), 14, 24, defaults.lyricFontSize);
    this.values.lyricAlign = await storage.getString(StorageKeys.LYRIC_ALIGN, defaults.lyricAlign);
    this.values.showLyricProgress = await storage.getBoolean(StorageKeys.LYRIC_SHOW_PROGRESS, defaults.showLyricProgress);
    this.values.desktopLyricWidth = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_DL_WIDTH, defaults.desktopLyricWidth), 40, 100, defaults.desktopLyricWidth);
    this.values.desktopLyricMaxLines = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_DL_MAX_LINES, defaults.desktopLyricMaxLines), 1, 3,
      defaults.desktopLyricMaxLines);
    this.values.desktopLyricSingleLine = await storage.getBoolean(
      StorageKeys.PLAY_DL_SINGLE_LINE, defaults.desktopLyricSingleLine);
    this.values.desktopLyricPlayedColor = await storage.getString(
      StorageKeys.PLAY_DL_PLAYED_COLOR, defaults.desktopLyricPlayedColor);
    this.values.desktopLyricTextPositionX = toDlTextPosX(
      await storage.getString(StorageKeys.PLAY_DL_TEXT_POS_X, defaults.desktopLyricTextPositionX));
    this.values.desktopLyricTextPositionY = toDlTextPosY(
      await storage.getString(StorageKeys.PLAY_DL_TEXT_POS_Y, defaults.desktopLyricTextPositionY));
    this.values.desktopLyricTextOpacity = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_DL_TEXT_OPACITY, defaults.desktopLyricTextOpacity), 20, 100,
      defaults.desktopLyricTextOpacity);
    this.values.desktopLyricAnim = await storage.getBoolean(StorageKeys.PLAY_DL_ANIM, defaults.desktopLyricAnim);
    this.values.desktopLyricShadowColor = await storage.getString(
      StorageKeys.PLAY_DL_SHADOW_COLOR, defaults.desktopLyricShadowColor);
    this.values.showListSource = await storage.getBoolean(StorageKeys.LIST_SHOW_SOURCE, defaults.showListSource);
    this.values.showListAlbum = await storage.getBoolean(StorageKeys.LIST_SHOW_ALBUM, defaults.showListAlbum);
    this.values.showListDuration = await storage.getBoolean(StorageKeys.LIST_SHOW_DURATION, defaults.showListDuration);
    this.values.rememberScrollPosition = await storage.getBoolean(
      StorageKeys.LIST_REMEMBER_SCROLL, defaults.rememberScrollPosition);
    this.values.enableVerboseLog = await storage.getBoolean(
      StorageKeys.LOG_VERBOSE, defaults.enableVerboseLog);
    this.values.s2tMode = normalizeS2TMode(
      await storage.getString(StorageKeys.LYRIC_S2T_MODE, defaults.s2tMode));
    this.values.sourceNameType = toSourceNameType(
      await storage.getString(StorageKeys.COMMON_SOURCE_NAME_TYPE, defaults.sourceNameType));
    this.values.shareType = toShareType(
      await storage.getString(StorageKeys.COMMON_SHARE_TYPE, defaults.shareType));
    this.values.agreedPact = await storage.getBoolean(StorageKeys.COMMON_AGREE_PACT, defaults.agreedPact);
    this.values.allowProgressBarSeek = await storage.getBoolean(
      StorageKeys.COMMON_ALLOW_PROGRESS_SEEK, defaults.allowProgressBarSeek);
    this.values.showSearchHistory = await storage.getBoolean(
      StorageKeys.SEARCH_SHOW_HISTORY, defaults.showSearchHistory);
    this.values.listClickPlay = await storage.getBoolean(
      StorageKeys.LIST_CLICK_PLAY, defaults.listClickPlay);
    this.values.audioFocus = await storage.getBoolean(StorageKeys.PLAY_AUDIO_FOCUS, defaults.audioFocus);
    this.values.audioOffload = await storage.getBoolean(StorageKeys.PLAY_AUDIO_OFFLOAD, defaults.audioOffload);
    this.values.playerCacheSizeMb = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_CACHE_SIZE_MB, defaults.playerCacheSizeMb), 1, 64,
      defaults.playerCacheSizeMb);
    this.values.lyricOffset = clampNumber(
      await storage.getNumber(StorageKeys.LYRIC_OFFSET, defaults.lyricOffset), -5, 5, defaults.lyricOffset);
    this.values.volume = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_VOLUME, defaults.volume), 0, 100, defaults.volume);
    this.values.sleepTimerEnabled = await storage.getBoolean(
      StorageKeys.PLAY_SLEEP_ENABLED, defaults.sleepTimerEnabled);
    this.values.sleepTimerMinutes = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_SLEEP_MINUTES, defaults.sleepTimerMinutes), 1, 600,
      defaults.sleepTimerMinutes);
    this.values.sleepTimerWaitTrackEnd = await storage.getBoolean(
      StorageKeys.PLAY_SLEEP_WAIT_TRACK_END, defaults.sleepTimerWaitTrackEnd);
    this.values.showDesktopLyric = await storage.getBoolean(
      StorageKeys.PLAY_DESKTOP_LYRIC, defaults.showDesktopLyric);
    this.values.desktopLyricPosition = toDesktopLyricPosition(
      await storage.getString(StorageKeys.PLAY_DESKTOP_LYRIC_POSITION, defaults.desktopLyricPosition),
      defaults.desktopLyricPosition);
    this.values.desktopLyricColor = await storage.getString(
      StorageKeys.PLAY_DESKTOP_LYRIC_COLOR, defaults.desktopLyricColor);
    this.values.desktopLyricBgAlpha = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_DESKTOP_LYRIC_BG_ALPHA, defaults.desktopLyricBgAlpha),
      0, 100, defaults.desktopLyricBgAlpha);
    this.values.desktopLyricFontSize = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_DESKTOP_LYRIC_FONT_SIZE, defaults.desktopLyricFontSize),
      14, 32, defaults.desktopLyricFontSize);
    this.values.desktopLyricShowNext = await storage.getBoolean(
      StorageKeys.PLAY_DESKTOP_LYRIC_SHOW_NEXT, defaults.desktopLyricShowNext);
    this.values.desktopLyricLocked = await storage.getBoolean(
      StorageKeys.PLAY_DESKTOP_LYRIC_LOCKED, defaults.desktopLyricLocked);
    this.values.desktopLyricX = await storage.getNumber(StorageKeys.PLAY_DESKTOP_LYRIC_X, defaults.desktopLyricX);
    this.values.desktopLyricY = await storage.getNumber(StorageKeys.PLAY_DESKTOP_LYRIC_Y, defaults.desktopLyricY);

    this.values.searchSource = await storage.getString(StorageKeys.SEARCH_SOURCE, defaults.searchSource);
    this.values.showHotSearch = await storage.getBoolean(StorageKeys.SEARCH_SHOW_HOT, defaults.showHotSearch);
    this.values.searchHistoryCount = clampNumber(
      await storage.getNumber(StorageKeys.SEARCH_HISTORY_LIMIT, defaults.searchHistoryCount), 1, 100,
      defaults.searchHistoryCount);

    this.values.addMusicLocation = toAddMusicLocation(
      await storage.getString(StorageKeys.LIST_ADD_LOCATION, defaults.addMusicLocation),
      defaults.addMusicLocation);
    this.values.autoCleanPlayedList = await storage.getBoolean(
      StorageKeys.LIST_AUTO_CLEAN_PLAYED, defaults.autoCleanPlayedList);

    this.values.downloadPath = await storage.getString(StorageKeys.DOWNLOAD_PATH, defaults.downloadPath);
    this.values.autoStartDownload = await storage.getBoolean(
      StorageKeys.DOWNLOAD_AUTO_START, defaults.autoStartDownload);
    this.values.maxConcurrentDownloads = clampNumber(
      await storage.getNumber(StorageKeys.DOWNLOAD_MAX_CONCURRENT, defaults.maxConcurrentDownloads), 1, 3,
      defaults.maxConcurrentDownloads);

    this.values.syncEnabled = await storage.getBoolean(StorageKeys.SYNC_ENABLED, defaults.syncEnabled);
    this.values.syncServer = await storage.getString(StorageKeys.SYNC_SERVER, defaults.syncServer);
    this.values.syncKey = await storage.getString(StorageKeys.SYNC_KEY, defaults.syncKey);
    this.values.syncInterval = clampNumber(
      await storage.getNumber(StorageKeys.SYNC_INTERVAL, defaults.syncInterval), 1, 1440, defaults.syncInterval);
    this.values.syncAutoSync = await storage.getBoolean(StorageKeys.SYNC_AUTO_SYNC, defaults.syncAutoSync);
    this.values.syncMode = await storage.getString(StorageKeys.SYNC_MODE, defaults.syncMode) === 'server'
      ? 'server' : 'client';

    this.values.fontSize = clampNumber(
      await storage.getNumber(StorageKeys.APPEARANCE_FONT_SIZE, defaults.fontSize), 12, 24, defaults.fontSize);
    this.values.showAnimation = await storage.getBoolean(
      StorageKeys.APPEARANCE_SHOW_ANIMATION, defaults.showAnimation);
  }

  /** 读取设置快照（同步，返回副本） */
  get(): AppSettings {
    return this.copyOf(this.values);
  }

  private copyOf(source: AppSettings): AppSettings {
    const copy: AppSettings = createDefaultSettings();
    copy.language = source.language;
    copy.startupPage = source.startupPage;
    copy.showExitDialog = source.showExitDialog;
    copy.themeMode = source.themeMode;
    copy.themeId = source.themeId;
    copy.autoTheme = source.autoTheme;
    copy.themeLightId = source.themeLightId;
    copy.themeDarkId = source.themeDarkId;
    copy.dynamicBg = source.dynamicBg;
    copy.fontShadow = source.fontShadow;
    copy.hideBgDark = source.hideBgDark;
    copy.autoPlay = source.autoPlay;
    copy.highQuality = source.highQuality;
    copy.playQuality = source.playQuality;
    copy.playMode = source.playMode;
    copy.playRate = source.playRate;
    copy.savePlayTime = source.savePlayTime;
    copy.showNotificationImage = source.showNotificationImage;
    copy.showBluetoothLyric = source.showBluetoothLyric;
    copy.showLyricTranslation = source.showLyricTranslation;
    copy.showLyricRoma = source.showLyricRoma;
    copy.lyricFontSize = source.lyricFontSize;
    copy.lyricAlign = source.lyricAlign;
    copy.showLyricProgress = source.showLyricProgress;
    copy.desktopLyricWidth = source.desktopLyricWidth;
    copy.desktopLyricMaxLines = source.desktopLyricMaxLines;
    copy.desktopLyricSingleLine = source.desktopLyricSingleLine;
    copy.desktopLyricPlayedColor = source.desktopLyricPlayedColor;
    copy.desktopLyricTextPositionX = source.desktopLyricTextPositionX;
    copy.desktopLyricTextPositionY = source.desktopLyricTextPositionY;
    copy.desktopLyricTextOpacity = source.desktopLyricTextOpacity;
    copy.desktopLyricAnim = source.desktopLyricAnim;
    copy.desktopLyricShadowColor = source.desktopLyricShadowColor;
    copy.showListSource = source.showListSource;
    copy.showListAlbum = source.showListAlbum;
    copy.showListDuration = source.showListDuration;
    copy.rememberScrollPosition = source.rememberScrollPosition;
    copy.enableVerboseLog = source.enableVerboseLog;
    copy.s2tMode = source.s2tMode;
    copy.sourceNameType = source.sourceNameType;
    copy.shareType = source.shareType;
    copy.agreedPact = source.agreedPact;
    copy.allowProgressBarSeek = source.allowProgressBarSeek;
    copy.audioFocus = source.audioFocus;
    copy.audioOffload = source.audioOffload;
    copy.playerCacheSizeMb = source.playerCacheSizeMb;
    copy.lyricOffset = source.lyricOffset;
    copy.volume = source.volume;
    copy.sleepTimerEnabled = source.sleepTimerEnabled;
    copy.sleepTimerMinutes = source.sleepTimerMinutes;
    copy.sleepTimerWaitTrackEnd = source.sleepTimerWaitTrackEnd;
    copy.showDesktopLyric = source.showDesktopLyric;
    copy.desktopLyricPosition = source.desktopLyricPosition;
    copy.desktopLyricColor = source.desktopLyricColor;
    copy.desktopLyricBgAlpha = source.desktopLyricBgAlpha;
    copy.desktopLyricFontSize = source.desktopLyricFontSize;
    copy.desktopLyricShowNext = source.desktopLyricShowNext;
    copy.desktopLyricLocked = source.desktopLyricLocked;
    copy.desktopLyricX = source.desktopLyricX;
    copy.desktopLyricY = source.desktopLyricY;
    copy.searchSource = source.searchSource;
    copy.showHotSearch = source.showHotSearch;
    copy.showSearchHistory = source.showSearchHistory;
    copy.searchHistoryCount = source.searchHistoryCount;
    copy.addMusicLocation = source.addMusicLocation;
    copy.autoCleanPlayedList = source.autoCleanPlayedList;
    copy.listClickPlay = source.listClickPlay;
    copy.downloadPath = source.downloadPath;
    copy.autoStartDownload = source.autoStartDownload;
    copy.maxConcurrentDownloads = source.maxConcurrentDownloads;
    copy.syncEnabled = source.syncEnabled;
    copy.syncServer = source.syncServer;
    copy.syncKey = source.syncKey;
    copy.syncInterval = source.syncInterval;
    copy.syncAutoSync = source.syncAutoSync;
    copy.syncMode = source.syncMode;
    copy.fontSize = source.fontSize;
    copy.showAnimation = source.showAnimation;
    return copy;
  }

  /**
   * 写入设置。
   * 只处理 patch 中出现的字段，且只有值真正变化时才落盘并广播，
   * 避免一次保存触发几十次无意义的事件与 flash 写入。
   */
  async update(patch: SettingsPatch): Promise<void> {
    const storage = getStorageService();
    const changed: string[] = [];

    if (patch.language !== undefined && patch.language !== this.values.language) {
      this.values.language = patch.language;
      await storage.setString(StorageKeys.LANGUAGE, patch.language);
      changed.push('language');
    }
    if (patch.startupPage !== undefined && patch.startupPage !== this.values.startupPage) {
      this.values.startupPage = patch.startupPage;
      await storage.setString(StorageKeys.STARTUP_PAGE, patch.startupPage);
      changed.push('startupPage');
    }
    if (patch.showExitDialog !== undefined && patch.showExitDialog !== this.values.showExitDialog) {
      this.values.showExitDialog = patch.showExitDialog;
      await storage.setBoolean(StorageKeys.SHOW_EXIT_DIALOG, patch.showExitDialog);
      changed.push('showExitDialog');
    }
    if (patch.themeMode !== undefined && patch.themeMode !== this.values.themeMode) {
      this.values.themeMode = patch.themeMode;
      await storage.setString(StorageKeys.THEME_MODE, patch.themeMode);
      changed.push('themeMode');
    }
    if (patch.themeId !== undefined && patch.themeId !== this.values.themeId) {
      this.values.themeId = patch.themeId;
      await storage.setString(StorageKeys.THEME_ID, patch.themeId);
      changed.push('themeId');
    }
    if (patch.autoTheme !== undefined && patch.autoTheme !== this.values.autoTheme) {
      this.values.autoTheme = patch.autoTheme;
      await storage.setBoolean(StorageKeys.COMMON_AUTO_THEME, patch.autoTheme);
      changed.push('autoTheme');
    }
    if (patch.themeLightId !== undefined && patch.themeLightId !== this.values.themeLightId) {
      this.values.themeLightId = patch.themeLightId;
      await storage.setString(StorageKeys.THEME_LIGHT_ID, patch.themeLightId);
      changed.push('themeLightId');
    }
    if (patch.themeDarkId !== undefined && patch.themeDarkId !== this.values.themeDarkId) {
      this.values.themeDarkId = patch.themeDarkId;
      await storage.setString(StorageKeys.THEME_DARK_ID, patch.themeDarkId);
      changed.push('themeDarkId');
    }
    if (patch.dynamicBg !== undefined && patch.dynamicBg !== this.values.dynamicBg) {
      this.values.dynamicBg = patch.dynamicBg;
      await storage.setBoolean(StorageKeys.THEME_DYNAMIC_BG, patch.dynamicBg);
      changed.push('dynamicBg');
    }
    if (patch.fontShadow !== undefined && patch.fontShadow !== this.values.fontShadow) {
      this.values.fontShadow = patch.fontShadow;
      await storage.setBoolean(StorageKeys.THEME_FONT_SHADOW, patch.fontShadow);
      changed.push('fontShadow');
    }
    if (patch.hideBgDark !== undefined && patch.hideBgDark !== this.values.hideBgDark) {
      this.values.hideBgDark = patch.hideBgDark;
      await storage.setBoolean(StorageKeys.THEME_HIDE_BG_DARK, patch.hideBgDark);
      changed.push('hideBgDark');
    }

    if (patch.autoPlay !== undefined && patch.autoPlay !== this.values.autoPlay) {
      this.values.autoPlay = patch.autoPlay;
      await storage.setBoolean(StorageKeys.PLAY_AUTO_PLAY, patch.autoPlay);
      changed.push('autoPlay');
    }
    if (patch.highQuality !== undefined && patch.highQuality !== this.values.highQuality) {
      this.values.highQuality = patch.highQuality;
      await storage.setBoolean(StorageKeys.PLAY_HIGH_QUALITY, patch.highQuality);
      changed.push('highQuality');
    }
    if (patch.playQuality !== undefined) {
      const next = toQuality(patch.playQuality, this.values.playQuality);
      if (next !== this.values.playQuality) {
        this.values.playQuality = next;
        await storage.setString(StorageKeys.PLAY_QUALITY, next);
        // 与旧的「高品质」开关保持同步，避免两处读到不同音质
        this.values.highQuality = next !== '128k';
        await storage.setBoolean(StorageKeys.PLAY_HIGH_QUALITY, this.values.highQuality);
        changed.push('playQuality');
        changed.push('highQuality');
      }
    }
    if (patch.playMode !== undefined && patch.playMode !== this.values.playMode) {
      this.values.playMode = patch.playMode;
      await storage.setString(StorageKeys.PLAY_MODE, patch.playMode);
      changed.push('playMode');
    }
    if (patch.playRate !== undefined) {
      const next = clampNumber(patch.playRate, 0.5, 2.0, this.values.playRate);
      if (Math.abs(next - this.values.playRate) > 0.001) {
        this.values.playRate = next;
        await storage.setNumber(StorageKeys.PLAY_RATE, next);
        changed.push('playRate');
      }
    }
    if (patch.desktopLyricWidth !== undefined) {
      const nextW = clampNumber(patch.desktopLyricWidth, 40, 100, this.values.desktopLyricWidth);
      if (nextW !== this.values.desktopLyricWidth) {
        this.values.desktopLyricWidth = nextW;
        await storage.setNumber(StorageKeys.PLAY_DL_WIDTH, nextW);
        changed.push('desktopLyricWidth');
      }
    }
    if (patch.desktopLyricMaxLines !== undefined) {
      const nextL = clampNumber(patch.desktopLyricMaxLines, 1, 3, this.values.desktopLyricMaxLines);
      if (nextL !== this.values.desktopLyricMaxLines) {
        this.values.desktopLyricMaxLines = nextL;
        await storage.setNumber(StorageKeys.PLAY_DL_MAX_LINES, nextL);
        changed.push('desktopLyricMaxLines');
      }
    }
    if (patch.desktopLyricAnim !== undefined && patch.desktopLyricAnim !== this.values.desktopLyricAnim) {
      this.values.desktopLyricAnim = patch.desktopLyricAnim;
      await storage.setBoolean(StorageKeys.PLAY_DL_ANIM, patch.desktopLyricAnim);
      changed.push('desktopLyricAnim');
    }
    if (patch.desktopLyricShadowColor !== undefined && patch.desktopLyricShadowColor !== this.values.desktopLyricShadowColor) {
      this.values.desktopLyricShadowColor = patch.desktopLyricShadowColor;
      await storage.setString(StorageKeys.PLAY_DL_SHADOW_COLOR, patch.desktopLyricShadowColor);
      changed.push('desktopLyricShadowColor');
    }
    if (patch.lyricFontSize !== undefined) {
      const nextSize = clampNumber(patch.lyricFontSize, 14, 24, this.values.lyricFontSize);
      if (nextSize !== this.values.lyricFontSize) {
        this.values.lyricFontSize = nextSize;
        await storage.setNumber(StorageKeys.LYRIC_FONT_SIZE, nextSize);
        changed.push('lyricFontSize');
      }
    }
    if (patch.lyricAlign !== undefined && patch.lyricAlign !== this.values.lyricAlign) {
      this.values.lyricAlign = patch.lyricAlign;
      await storage.setString(StorageKeys.LYRIC_ALIGN, patch.lyricAlign);
      changed.push('lyricAlign');
    }
    if (patch.showLyricProgress !== undefined && patch.showLyricProgress !== this.values.showLyricProgress) {
      this.values.showLyricProgress = patch.showLyricProgress;
      await storage.setBoolean(StorageKeys.LYRIC_SHOW_PROGRESS, patch.showLyricProgress);
      changed.push('showLyricProgress');
    }
    if (patch.showListSource !== undefined && patch.showListSource !== this.values.showListSource) {
      this.values.showListSource = patch.showListSource;
      await storage.setBoolean(StorageKeys.LIST_SHOW_SOURCE, patch.showListSource);
      changed.push('showListSource');
    }
    if (patch.showListAlbum !== undefined && patch.showListAlbum !== this.values.showListAlbum) {
      this.values.showListAlbum = patch.showListAlbum;
      await storage.setBoolean(StorageKeys.LIST_SHOW_ALBUM, patch.showListAlbum);
      changed.push('showListAlbum');
    }
    if (patch.showListDuration !== undefined && patch.showListDuration !== this.values.showListDuration) {
      this.values.showListDuration = patch.showListDuration;
      await storage.setBoolean(StorageKeys.LIST_SHOW_DURATION, patch.showListDuration);
      changed.push('showListDuration');
    }
    if (patch.rememberScrollPosition !== undefined && patch.rememberScrollPosition !== this.values.rememberScrollPosition) {
      this.values.rememberScrollPosition = patch.rememberScrollPosition;
      await storage.setBoolean(StorageKeys.LIST_REMEMBER_SCROLL, patch.rememberScrollPosition);
      changed.push('rememberScrollPosition');
    }
    if (patch.enableVerboseLog !== undefined && patch.enableVerboseLog !== this.values.enableVerboseLog) {
      this.values.enableVerboseLog = patch.enableVerboseLog;
      await storage.setBoolean(StorageKeys.LOG_VERBOSE, patch.enableVerboseLog);
      changed.push('enableVerboseLog');
    }
    if (patch.s2tMode !== undefined) {
      const mode = normalizeS2TMode(patch.s2tMode);
      if (mode !== this.values.s2tMode) {
        this.values.s2tMode = mode;
        await storage.setString(StorageKeys.LYRIC_S2T_MODE, mode);
        changed.push('s2tMode');
      }
    }
    if (patch.sourceNameType !== undefined) {
      const next = toSourceNameType(patch.sourceNameType);
      if (next !== this.values.sourceNameType) {
        this.values.sourceNameType = next;
        await storage.setString(StorageKeys.COMMON_SOURCE_NAME_TYPE, next);
        changed.push('sourceNameType');
      }
    }
    if (patch.shareType !== undefined) {
      const next = toShareType(patch.shareType);
      if (next !== this.values.shareType) {
        this.values.shareType = next;
        await storage.setString(StorageKeys.COMMON_SHARE_TYPE, next);
        changed.push('shareType');
      }
    }
    if (patch.agreedPact !== undefined && patch.agreedPact !== this.values.agreedPact) {
      this.values.agreedPact = patch.agreedPact;
      await storage.setBoolean(StorageKeys.COMMON_AGREE_PACT, patch.agreedPact);
      changed.push('agreedPact');
    }
    if (patch.allowProgressBarSeek !== undefined
      && patch.allowProgressBarSeek !== this.values.allowProgressBarSeek) {
      this.values.allowProgressBarSeek = patch.allowProgressBarSeek;
      await storage.setBoolean(StorageKeys.COMMON_ALLOW_PROGRESS_SEEK, patch.allowProgressBarSeek);
      changed.push('allowProgressBarSeek');
    }
    if (patch.showSearchHistory !== undefined
      && patch.showSearchHistory !== this.values.showSearchHistory) {
      this.values.showSearchHistory = patch.showSearchHistory;
      await storage.setBoolean(StorageKeys.SEARCH_SHOW_HISTORY, patch.showSearchHistory);
      changed.push('showSearchHistory');
    }
    if (patch.listClickPlay !== undefined && patch.listClickPlay !== this.values.listClickPlay) {
      this.values.listClickPlay = patch.listClickPlay;
      await storage.setBoolean(StorageKeys.LIST_CLICK_PLAY, patch.listClickPlay);
      changed.push('listClickPlay');
    }
    if (patch.showLyricTranslation !== undefined && patch.showLyricTranslation !== this.values.showLyricTranslation) {
      this.values.showLyricTranslation = patch.showLyricTranslation;
      await storage.setBoolean(StorageKeys.LYRIC_SHOW_TRANSLATION, patch.showLyricTranslation);
      changed.push('showLyricTranslation');
    }
    if (patch.showLyricRoma !== undefined && patch.showLyricRoma !== this.values.showLyricRoma) {
      this.values.showLyricRoma = patch.showLyricRoma;
      await storage.setBoolean(StorageKeys.LYRIC_SHOW_ROMA, patch.showLyricRoma);
      changed.push('showLyricRoma');
    }
    if (patch.savePlayTime !== undefined && patch.savePlayTime !== this.values.savePlayTime) {
      this.values.savePlayTime = patch.savePlayTime;
      await storage.setBoolean(StorageKeys.PLAY_SAVE_TIME, patch.savePlayTime);
      changed.push('savePlayTime');
    }
    if (patch.showNotificationImage !== undefined
      && patch.showNotificationImage !== this.values.showNotificationImage) {
      this.values.showNotificationImage = patch.showNotificationImage;
      await storage.setBoolean(StorageKeys.PLAY_NOTIFICATION_IMAGE, patch.showNotificationImage);
      changed.push('showNotificationImage');
    }
    if (patch.showBluetoothLyric !== undefined && patch.showBluetoothLyric !== this.values.showBluetoothLyric) {
      this.values.showBluetoothLyric = patch.showBluetoothLyric;
      await storage.setBoolean(StorageKeys.PLAY_BLUETOOTH_LYRIC, patch.showBluetoothLyric);
      changed.push('showBluetoothLyric');
    }
    if (patch.audioFocus !== undefined && patch.audioFocus !== this.values.audioFocus) {
      this.values.audioFocus = patch.audioFocus;
      await storage.setBoolean(StorageKeys.PLAY_AUDIO_FOCUS, patch.audioFocus);
      changed.push('audioFocus');
    }
    if (patch.audioOffload !== undefined && patch.audioOffload !== this.values.audioOffload) {
      this.values.audioOffload = patch.audioOffload;
      await storage.setBoolean(StorageKeys.PLAY_AUDIO_OFFLOAD, patch.audioOffload);
      changed.push('audioOffload');
    }
    if (patch.playerCacheSizeMb !== undefined) {
      const nextCache = clampNumber(patch.playerCacheSizeMb, 1, 64, this.values.playerCacheSizeMb);
      if (nextCache !== this.values.playerCacheSizeMb) {
        this.values.playerCacheSizeMb = nextCache;
        await storage.setNumber(StorageKeys.PLAY_CACHE_SIZE_MB, nextCache);
        changed.push('playerCacheSizeMb');
      }
    }
    if (patch.lyricOffset !== undefined) {
      const next = clampNumber(patch.lyricOffset, -5, 5, this.values.lyricOffset);
      if (Math.abs(next - this.values.lyricOffset) > 0.001) {
        this.values.lyricOffset = next;
        await storage.setNumber(StorageKeys.LYRIC_OFFSET, next);
        changed.push('lyricOffset');
      }
    }
    if (patch.volume !== undefined) {
      const next = clampNumber(patch.volume, 0, 100, this.values.volume);
      if (next !== this.values.volume) {
        this.values.volume = next;
        await storage.setNumber(StorageKeys.PLAY_VOLUME, next);
        changed.push('volume');
      }
    }
    if (patch.sleepTimerEnabled !== undefined && patch.sleepTimerEnabled !== this.values.sleepTimerEnabled) {
      this.values.sleepTimerEnabled = patch.sleepTimerEnabled;
      await storage.setBoolean(StorageKeys.PLAY_SLEEP_ENABLED, patch.sleepTimerEnabled);
      changed.push('sleepTimerEnabled');
    }
    if (patch.sleepTimerMinutes !== undefined) {
      const next = clampNumber(patch.sleepTimerMinutes, 1, 600, this.values.sleepTimerMinutes);
      if (next !== this.values.sleepTimerMinutes) {
        this.values.sleepTimerMinutes = next;
        await storage.setNumber(StorageKeys.PLAY_SLEEP_MINUTES, next);
        changed.push('sleepTimerMinutes');
      }
    }
    if (patch.sleepTimerWaitTrackEnd !== undefined
      && patch.sleepTimerWaitTrackEnd !== this.values.sleepTimerWaitTrackEnd) {
      this.values.sleepTimerWaitTrackEnd = patch.sleepTimerWaitTrackEnd;
      await storage.setBoolean(StorageKeys.PLAY_SLEEP_WAIT_TRACK_END, patch.sleepTimerWaitTrackEnd);
      changed.push('sleepTimerWaitTrackEnd');
    }
    if (patch.desktopLyricSingleLine !== undefined
      && patch.desktopLyricSingleLine !== this.values.desktopLyricSingleLine) {
      this.values.desktopLyricSingleLine = patch.desktopLyricSingleLine;
      await storage.setBoolean(StorageKeys.PLAY_DL_SINGLE_LINE, patch.desktopLyricSingleLine);
      changed.push('desktopLyricSingleLine');
    }
    if (patch.desktopLyricPlayedColor !== undefined
      && patch.desktopLyricPlayedColor !== this.values.desktopLyricPlayedColor) {
      this.values.desktopLyricPlayedColor = patch.desktopLyricPlayedColor;
      await storage.setString(StorageKeys.PLAY_DL_PLAYED_COLOR, patch.desktopLyricPlayedColor);
      changed.push('desktopLyricPlayedColor');
    }
    if (patch.desktopLyricTextPositionX !== undefined) {
      const next = toDlTextPosX(patch.desktopLyricTextPositionX);
      if (next !== this.values.desktopLyricTextPositionX) {
        this.values.desktopLyricTextPositionX = next;
        await storage.setString(StorageKeys.PLAY_DL_TEXT_POS_X, next);
        changed.push('desktopLyricTextPositionX');
      }
    }
    if (patch.desktopLyricTextPositionY !== undefined) {
      const next = toDlTextPosY(patch.desktopLyricTextPositionY);
      if (next !== this.values.desktopLyricTextPositionY) {
        this.values.desktopLyricTextPositionY = next;
        await storage.setString(StorageKeys.PLAY_DL_TEXT_POS_Y, next);
        changed.push('desktopLyricTextPositionY');
      }
    }
    if (patch.desktopLyricTextOpacity !== undefined) {
      const next = clampNumber(patch.desktopLyricTextOpacity, 20, 100, this.values.desktopLyricTextOpacity);
      if (next !== this.values.desktopLyricTextOpacity) {
        this.values.desktopLyricTextOpacity = next;
        await storage.setNumber(StorageKeys.PLAY_DL_TEXT_OPACITY, next);
        changed.push('desktopLyricTextOpacity');
      }
    }
    if (patch.showDesktopLyric !== undefined && patch.showDesktopLyric !== this.values.showDesktopLyric) {
      this.values.showDesktopLyric = patch.showDesktopLyric;
      await storage.setBoolean(StorageKeys.PLAY_DESKTOP_LYRIC, patch.showDesktopLyric);
      changed.push('showDesktopLyric');
    }
    if (patch.desktopLyricPosition !== undefined &&
      patch.desktopLyricPosition !== this.values.desktopLyricPosition) {
      this.values.desktopLyricPosition = patch.desktopLyricPosition;
      await storage.setString(StorageKeys.PLAY_DESKTOP_LYRIC_POSITION, patch.desktopLyricPosition);
      changed.push('desktopLyricPosition');
    }
    if (patch.desktopLyricColor !== undefined && patch.desktopLyricColor !== this.values.desktopLyricColor) {
      this.values.desktopLyricColor = patch.desktopLyricColor;
      await storage.setString(StorageKeys.PLAY_DESKTOP_LYRIC_COLOR, patch.desktopLyricColor);
      changed.push('desktopLyricColor');
    }
    if (patch.desktopLyricBgAlpha !== undefined) {
      const next = clampNumber(patch.desktopLyricBgAlpha, 0, 100, this.values.desktopLyricBgAlpha);
      if (next !== this.values.desktopLyricBgAlpha) {
        this.values.desktopLyricBgAlpha = next;
        await storage.setNumber(StorageKeys.PLAY_DESKTOP_LYRIC_BG_ALPHA, next);
        changed.push('desktopLyricBgAlpha');
      }
    }
    if (patch.desktopLyricFontSize !== undefined) {
      const next = clampNumber(patch.desktopLyricFontSize, 14, 32, this.values.desktopLyricFontSize);
      if (next !== this.values.desktopLyricFontSize) {
        this.values.desktopLyricFontSize = next;
        await storage.setNumber(StorageKeys.PLAY_DESKTOP_LYRIC_FONT_SIZE, next);
        changed.push('desktopLyricFontSize');
      }
    }
    if (patch.desktopLyricShowNext !== undefined && patch.desktopLyricShowNext !== this.values.desktopLyricShowNext) {
      this.values.desktopLyricShowNext = patch.desktopLyricShowNext;
      await storage.setBoolean(StorageKeys.PLAY_DESKTOP_LYRIC_SHOW_NEXT, patch.desktopLyricShowNext);
      changed.push('desktopLyricShowNext');
    }
    if (patch.desktopLyricLocked !== undefined && patch.desktopLyricLocked !== this.values.desktopLyricLocked) {
      this.values.desktopLyricLocked = patch.desktopLyricLocked;
      await storage.setBoolean(StorageKeys.PLAY_DESKTOP_LYRIC_LOCKED, patch.desktopLyricLocked);
      changed.push('desktopLyricLocked');
    }
    if (patch.desktopLyricX !== undefined && patch.desktopLyricX !== this.values.desktopLyricX) {
      this.values.desktopLyricX = patch.desktopLyricX;
      await storage.setNumber(StorageKeys.PLAY_DESKTOP_LYRIC_X, patch.desktopLyricX);
      changed.push('desktopLyricX');
    }
    if (patch.desktopLyricY !== undefined && patch.desktopLyricY !== this.values.desktopLyricY) {
      this.values.desktopLyricY = patch.desktopLyricY;
      await storage.setNumber(StorageKeys.PLAY_DESKTOP_LYRIC_Y, patch.desktopLyricY);
      changed.push('desktopLyricY');
    }

    if (patch.searchSource !== undefined && patch.searchSource !== this.values.searchSource) {
      this.values.searchSource = patch.searchSource;
      await storage.setString(StorageKeys.SEARCH_SOURCE, patch.searchSource);
      changed.push('searchSource');
    }
    if (patch.showHotSearch !== undefined && patch.showHotSearch !== this.values.showHotSearch) {
      this.values.showHotSearch = patch.showHotSearch;
      await storage.setBoolean(StorageKeys.SEARCH_SHOW_HOT, patch.showHotSearch);
      changed.push('showHotSearch');
    }
    if (patch.searchHistoryCount !== undefined) {
      const next = clampNumber(patch.searchHistoryCount, 1, 100, this.values.searchHistoryCount);
      if (next !== this.values.searchHistoryCount) {
        this.values.searchHistoryCount = next;
        await storage.setNumber(StorageKeys.SEARCH_HISTORY_LIMIT, next);
        changed.push('searchHistoryCount');
      }
    }

    if (patch.addMusicLocation !== undefined && patch.addMusicLocation !== this.values.addMusicLocation) {
      this.values.addMusicLocation = patch.addMusicLocation;
      await storage.setString(StorageKeys.LIST_ADD_LOCATION, patch.addMusicLocation);
      changed.push('addMusicLocation');
    }
    if (patch.autoCleanPlayedList !== undefined &&
      patch.autoCleanPlayedList !== this.values.autoCleanPlayedList) {
      this.values.autoCleanPlayedList = patch.autoCleanPlayedList;
      await storage.setBoolean(StorageKeys.LIST_AUTO_CLEAN_PLAYED, patch.autoCleanPlayedList);
      changed.push('autoCleanPlayedList');
    }

    if (patch.downloadPath !== undefined && patch.downloadPath !== this.values.downloadPath) {
      this.values.downloadPath = patch.downloadPath;
      await storage.setString(StorageKeys.DOWNLOAD_PATH, patch.downloadPath);
      changed.push('downloadPath');
    }
    if (patch.autoStartDownload !== undefined && patch.autoStartDownload !== this.values.autoStartDownload) {
      this.values.autoStartDownload = patch.autoStartDownload;
      await storage.setBoolean(StorageKeys.DOWNLOAD_AUTO_START, patch.autoStartDownload);
      changed.push('autoStartDownload');
    }
    if (patch.maxConcurrentDownloads !== undefined) {
      const next = clampNumber(patch.maxConcurrentDownloads, 1, 3, this.values.maxConcurrentDownloads);
      if (next !== this.values.maxConcurrentDownloads) {
        this.values.maxConcurrentDownloads = next;
        await storage.setNumber(StorageKeys.DOWNLOAD_MAX_CONCURRENT, next);
        changed.push('maxConcurrentDownloads');
      }
    }

    if (patch.syncEnabled !== undefined && patch.syncEnabled !== this.values.syncEnabled) {
      this.values.syncEnabled = patch.syncEnabled;
      await storage.setBoolean(StorageKeys.SYNC_ENABLED, patch.syncEnabled);
      changed.push('syncEnabled');
    }
    if (patch.syncServer !== undefined && patch.syncServer !== this.values.syncServer) {
      this.values.syncServer = patch.syncServer;
      await storage.setString(StorageKeys.SYNC_SERVER, patch.syncServer);
      changed.push('syncServer');
    }
    if (patch.syncKey !== undefined && patch.syncKey !== this.values.syncKey) {
      this.values.syncKey = patch.syncKey;
      await storage.setString(StorageKeys.SYNC_KEY, patch.syncKey);
      changed.push('syncKey');
    }
    if (patch.syncInterval !== undefined) {
      const next = clampNumber(patch.syncInterval, 1, 1440, this.values.syncInterval);
      if (next !== this.values.syncInterval) {
        this.values.syncInterval = next;
        await storage.setNumber(StorageKeys.SYNC_INTERVAL, next);
        changed.push('syncInterval');
      }
    }
    if (patch.syncAutoSync !== undefined && patch.syncAutoSync !== this.values.syncAutoSync) {
      this.values.syncAutoSync = patch.syncAutoSync;
      await storage.setBoolean(StorageKeys.SYNC_AUTO_SYNC, patch.syncAutoSync);
      changed.push('syncAutoSync');
    }
    if (patch.syncMode !== undefined && patch.syncMode !== this.values.syncMode) {
      this.values.syncMode = patch.syncMode;
      await storage.setString(StorageKeys.SYNC_MODE, patch.syncMode);
      changed.push('syncMode');
    }

    if (patch.fontSize !== undefined) {
      const next = clampNumber(patch.fontSize, 12, 24, this.values.fontSize);
      if (next !== this.values.fontSize) {
        this.values.fontSize = next;
        await storage.setNumber(StorageKeys.APPEARANCE_FONT_SIZE, next);
        changed.push('fontSize');
        this.applyFontScale();
      }
    }
    if (patch.showAnimation !== undefined && patch.showAnimation !== this.values.showAnimation) {
      this.values.showAnimation = patch.showAnimation;
      await storage.setBoolean(StorageKeys.APPEARANCE_SHOW_ANIMATION, patch.showAnimation);
      changed.push('showAnimation');
    }

    if (changed.length === 0) {
      return;
    }

    this.applyToAppStorage();
    for (let i = 0; i < changed.length; i++) {
      emitSettingChanged(changed[i]);
    }
    hilog.info(DOMAIN, TAG, 'Settings updated: %{public}s', changed.join(','));
  }

  /** 恢复默认设置 */
  async resetToDefaults(): Promise<void> {
    const defaults = createDefaultSettings();
    await this.update({
      language: defaults.language,
      startupPage: defaults.startupPage,
      showExitDialog: defaults.showExitDialog,
      themeMode: defaults.themeMode,
      themeId: defaults.themeId,
      autoTheme: defaults.autoTheme,
      themeLightId: defaults.themeLightId,
      themeDarkId: defaults.themeDarkId,
      dynamicBg: defaults.dynamicBg,
      fontShadow: defaults.fontShadow,
      hideBgDark: defaults.hideBgDark,
      autoPlay: defaults.autoPlay,
      highQuality: defaults.highQuality,
      playQuality: defaults.playQuality,
      playMode: defaults.playMode,
      playRate: defaults.playRate,
      lyricOffset: defaults.lyricOffset,
      savePlayTime: defaults.savePlayTime,
      showNotificationImage: defaults.showNotificationImage,
      showBluetoothLyric: defaults.showBluetoothLyric,
      showLyricTranslation: defaults.showLyricTranslation,
      showLyricRoma: defaults.showLyricRoma,
      lyricFontSize: defaults.lyricFontSize,
      lyricAlign: defaults.lyricAlign,
      showLyricProgress: defaults.showLyricProgress,
      desktopLyricWidth: defaults.desktopLyricWidth,
      desktopLyricMaxLines: defaults.desktopLyricMaxLines,
      desktopLyricSingleLine: defaults.desktopLyricSingleLine,
      desktopLyricPlayedColor: defaults.desktopLyricPlayedColor,
      desktopLyricTextPositionX: defaults.desktopLyricTextPositionX,
      desktopLyricTextPositionY: defaults.desktopLyricTextPositionY,
      desktopLyricTextOpacity: defaults.desktopLyricTextOpacity,
      desktopLyricAnim: defaults.desktopLyricAnim,
      desktopLyricShadowColor: defaults.desktopLyricShadowColor,
      showListSource: defaults.showListSource,
      showListAlbum: defaults.showListAlbum,
      showListDuration: defaults.showListDuration,
      rememberScrollPosition: defaults.rememberScrollPosition,
      enableVerboseLog: defaults.enableVerboseLog,
      s2tMode: defaults.s2tMode,
      sourceNameType: defaults.sourceNameType,
      shareType: defaults.shareType,
      agreedPact: defaults.agreedPact,
      allowProgressBarSeek: defaults.allowProgressBarSeek,
      showSearchHistory: defaults.showSearchHistory,
      listClickPlay: defaults.listClickPlay,
      audioFocus: defaults.audioFocus,
      audioOffload: defaults.audioOffload,
      playerCacheSizeMb: defaults.playerCacheSizeMb,
      volume: defaults.volume,
      sleepTimerEnabled: defaults.sleepTimerEnabled,
      sleepTimerMinutes: defaults.sleepTimerMinutes,
      sleepTimerWaitTrackEnd: defaults.sleepTimerWaitTrackEnd,
      showDesktopLyric: defaults.showDesktopLyric,
      desktopLyricPosition: defaults.desktopLyricPosition,
      desktopLyricColor: defaults.desktopLyricColor,
      desktopLyricBgAlpha: defaults.desktopLyricBgAlpha,
      desktopLyricFontSize: defaults.desktopLyricFontSize,
      desktopLyricShowNext: defaults.desktopLyricShowNext,
      desktopLyricLocked: defaults.desktopLyricLocked,
      searchSource: defaults.searchSource,
      showHotSearch: defaults.showHotSearch,
      searchHistoryCount: defaults.searchHistoryCount,
      addMusicLocation: defaults.addMusicLocation,
      autoCleanPlayedList: defaults.autoCleanPlayedList,
      autoStartDownload: defaults.autoStartDownload,
      maxConcurrentDownloads: defaults.maxConcurrentDownloads,
      syncAutoSync: defaults.syncAutoSync,
      syncInterval: defaults.syncInterval,
      syncMode: defaults.syncMode,
      fontSize: defaults.fontSize,
      showAnimation: defaults.showAnimation,
    });
  }

  /** 镜像到 AppStorage，驱动 @StorageProp / @StorageLink 组件刷新 */
  private applyToAppStorage(): void {
    AppStorage.setOrCreate('settingsReady', true);
    AppStorage.setOrCreate('theme', this.values.themeMode);
    AppStorage.setOrCreate('startupPage', this.values.startupPage);
    AppStorage.setOrCreate('autoPlay', this.values.autoPlay);
    AppStorage.setOrCreate('highQuality', this.values.highQuality);
    AppStorage.setOrCreate('playQuality', this.values.playQuality);
    AppStorage.setOrCreate('volume', this.values.volume);
    AppStorage.setOrCreate('defaultSearchSource', this.values.searchSource);
    AppStorage.setOrCreate('showHotSearch', this.values.showHotSearch);
    AppStorage.setOrCreate('searchHistoryCount', this.values.searchHistoryCount);
    AppStorage.setOrCreate('addMusicLocation', this.values.addMusicLocation);
    AppStorage.setOrCreate('autoCleanPlayedList', this.values.autoCleanPlayedList);
    AppStorage.setOrCreate('showDesktopLyric', this.values.showDesktopLyric);
    AppStorage.setOrCreate('desktopLyricPosition', this.values.desktopLyricPosition);
    AppStorage.setOrCreate('desktopLyricColor', this.values.desktopLyricColor);
    AppStorage.setOrCreate('desktopLyricBgAlpha', this.values.desktopLyricBgAlpha);
    AppStorage.setOrCreate('desktopLyricFontSize', this.values.desktopLyricFontSize);
    AppStorage.setOrCreate('desktopLyricShowNext', this.values.desktopLyricShowNext);
    AppStorage.setOrCreate('desktopLyricLocked', this.values.desktopLyricLocked);
    AppStorage.setOrCreate('appFontSize', this.values.fontSize);
    AppStorage.setOrCreate('showAnimation', this.values.showAnimation);
    AppStorage.setOrCreate('showLyricTranslation', this.values.showLyricTranslation);
    AppStorage.setOrCreate('showLyricRoma', this.values.showLyricRoma);
    AppStorage.setOrCreate('lyricFontSize', this.values.lyricFontSize);
    AppStorage.setOrCreate('lyricAlign', this.values.lyricAlign);
    AppStorage.setOrCreate('showLyricProgress', this.values.showLyricProgress);
    AppStorage.setOrCreate('desktopLyricWidth', this.values.desktopLyricWidth);
    AppStorage.setOrCreate('desktopLyricMaxLines', this.values.desktopLyricMaxLines);
    AppStorage.setOrCreate('desktopLyricAnim', this.values.desktopLyricAnim);
    AppStorage.setOrCreate('desktopLyricShadowColor', this.values.desktopLyricShadowColor);
    AppStorage.setOrCreate('showListSource', this.values.showListSource);
    AppStorage.setOrCreate('showListAlbum', this.values.showListAlbum);
    AppStorage.setOrCreate('showListDuration', this.values.showListDuration);
    AppStorage.setOrCreate('rememberScrollPosition', this.values.rememberScrollPosition);
    AppStorage.setOrCreate('enableVerboseLog', this.values.enableVerboseLog);
    AppStorage.setOrCreate('s2tMode', this.values.s2tMode);
    AppStorage.setOrCreate('showNotificationImage', this.values.showNotificationImage);
    AppStorage.setOrCreate('showBluetoothLyric', this.values.showBluetoothLyric);
    AppStorage.setOrCreate('sleepTimerWaitTrackEnd', this.values.sleepTimerWaitTrackEnd);
    AppStorage.setOrCreate('sourceNameType', this.values.sourceNameType);
    AppStorage.setOrCreate('shareType', this.values.shareType);
    AppStorage.setOrCreate('agreedPact', this.values.agreedPact);
    AppStorage.setOrCreate('allowProgressBarSeek', this.values.allowProgressBarSeek);
    AppStorage.setOrCreate('showSearchHistory', this.values.showSearchHistory);
    AppStorage.setOrCreate('listClickPlay', this.values.listClickPlay);
    AppStorage.setOrCreate('autoTheme', this.values.autoTheme);
    AppStorage.setOrCreate('dynamicBg', this.values.dynamicBg);
    AppStorage.setOrCreate('fontShadow', this.values.fontShadow);
    AppStorage.setOrCreate('hideBgDark', this.values.hideBgDark);
    AppStorage.setOrCreate('desktopLyricSingleLine', this.values.desktopLyricSingleLine);
    AppStorage.setOrCreate('desktopLyricPlayedColor', this.values.desktopLyricPlayedColor);
    AppStorage.setOrCreate('desktopLyricTextPositionX', this.values.desktopLyricTextPositionX);
    AppStorage.setOrCreate('desktopLyricTextPositionY', this.values.desktopLyricTextPositionY);
    AppStorage.setOrCreate('desktopLyricTextOpacity', this.values.desktopLyricTextOpacity);
  }

  /** 应用字号缩放（设置 -> 外观 -> 字体大小） */
  private applyFontScale(): void {
    if (!this.context) {
      return;
    }
    try {
      const scale = this.values.fontSize / BASE_FONT_SIZE;
      this.context.getApplicationContext().setFontSizeScale(scale);
      hilog.info(DOMAIN, TAG, 'Font scale applied: %{public}s', scale.toString());
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.warn(DOMAIN, TAG, 'Font scale not supported: %{public}s', msg);
    }
  }

  private notifyAll(): void {
    emitSettingChanged('all');
  }
}

export const settingsService = new SettingsServiceImpl();
export default settingsService;

/** 初始化设置服务（等价于 settingsService.init） */
export async function initSettings(context?: common.UIAbilityContext): Promise<void> {
  return settingsService.init(context);
}
