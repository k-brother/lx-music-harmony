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
/** 同步模式 */
export type SyncMode = 'client' | 'server';

/** 设置快照（读取时使用，全部为已解析的强类型值） */
export interface AppSettings {
  // 基础
  language: string;
  startupPage: StartupPage;
  showExitDialog: boolean;
  themeMode: ThemeMode;
  themeId: string;

  // 播放
  autoPlay: boolean;
  highQuality: boolean;
  playMode: PlayMode;
  /** 播放倍速（0.5 - 2.0） */
  playRate: number;
  /** 歌词偏移（秒）：正值=歌词提前出现 */
  lyricOffset: number;
  /** 0-100 */
  volume: number;
  sleepTimerEnabled: boolean;
  sleepTimerMinutes: number;
  showDesktopLyric: boolean;
  desktopLyricPosition: DesktopLyricPosition;
  desktopLyricColor: string;
  /** 歌词窗口背景不透明度 0-100（0 = 全透明） */
  desktopLyricBgAlpha: number;
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
  searchHistoryCount: number;

  // 列表
  addMusicLocation: AddMusicLocation;
  autoCleanPlayedList: boolean;

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

  autoPlay?: boolean;
  highQuality?: boolean;
  playMode?: PlayMode;
  playRate?: number;
  lyricOffset?: number;
  volume?: number;
  sleepTimerEnabled?: boolean;
  sleepTimerMinutes?: number;
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
  searchHistoryCount?: number;

  addMusicLocation?: AddMusicLocation;
  autoCleanPlayedList?: boolean;

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

    autoPlay: true,
    highQuality: true,
    playMode: 'listLoop',
    playRate: 1.0,
    lyricOffset: 0,
    volume: 80,
    sleepTimerEnabled: false,
    sleepTimerMinutes: 30,
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
    searchHistoryCount: 20,

    addMusicLocation: 'top',
    autoCleanPlayedList: false,

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

    this.values.autoPlay = await storage.getBoolean(StorageKeys.PLAY_AUTO_PLAY, defaults.autoPlay);
    this.values.highQuality = await storage.getBoolean(StorageKeys.PLAY_HIGH_QUALITY, defaults.highQuality);
    this.values.playMode = toPlayMode(
      await storage.getString(StorageKeys.PLAY_MODE, defaults.playMode), defaults.playMode);
    this.values.playRate = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_RATE, defaults.playRate), 0.5, 2.0, defaults.playRate);
    this.values.lyricOffset = clampNumber(
      await storage.getNumber(StorageKeys.LYRIC_OFFSET, defaults.lyricOffset), -5, 5, defaults.lyricOffset);
    this.values.volume = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_VOLUME, defaults.volume), 0, 100, defaults.volume);
    this.values.sleepTimerEnabled = await storage.getBoolean(
      StorageKeys.PLAY_SLEEP_ENABLED, defaults.sleepTimerEnabled);
    this.values.sleepTimerMinutes = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_SLEEP_MINUTES, defaults.sleepTimerMinutes), 1, 600,
      defaults.sleepTimerMinutes);
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
    copy.autoPlay = source.autoPlay;
    copy.highQuality = source.highQuality;
    copy.playMode = source.playMode;
    copy.playRate = source.playRate;
    copy.lyricOffset = source.lyricOffset;
    copy.volume = source.volume;
    copy.sleepTimerEnabled = source.sleepTimerEnabled;
    copy.sleepTimerMinutes = source.sleepTimerMinutes;
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
    copy.searchHistoryCount = source.searchHistoryCount;
    copy.addMusicLocation = source.addMusicLocation;
    copy.autoCleanPlayedList = source.autoCleanPlayedList;
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
      autoPlay: defaults.autoPlay,
      highQuality: defaults.highQuality,
      playMode: defaults.playMode,
      playRate: defaults.playRate,
      lyricOffset: defaults.lyricOffset,
      volume: defaults.volume,
      sleepTimerEnabled: defaults.sleepTimerEnabled,
      sleepTimerMinutes: defaults.sleepTimerMinutes,
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
