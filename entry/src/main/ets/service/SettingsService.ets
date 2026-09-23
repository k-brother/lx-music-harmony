/**
 * 应用设置服务 - 全应用唯一的设置读写入口。
 *
 * 设计约定：
 * 1. 类型与默认值在 settings/SettingsTypes，存储加载与旧数据迁移在 settings/SettingsStorage，
 *    本文件只负责「写设置 -> 更新内存快照 -> 镜像 AppStorage -> 广播 SETTINGS_CHANGED」。
 * 2. 所有设置项持久化在 StorageService 的同一个 Preferences 实例里，
 *    不再各页面自行 getPreferences，避免"写一个实例读另一个实例"。
 */
import type { common } from '@kit.AbilityKit';
import { getStorageService } from '../core/interfaces/IStorageService';
import { emitSettingChanged } from './EventBus';
import { appLog as hilog } from '../core/log/AppLogger';
import {
  createDefaultSettings,
  type AppSettings,
  type SettingsPatch,
} from './settings/SettingsTypes';
import { loadSettingsFromStorage, migrateLegacySettings } from './settings/SettingsStorage';
import {
  applyBasicSettings,
  applyPlaybackSettings,
  applyLyricSettings,
  applySearchSettings,
  applyListSettings,
  applyDownloadSettings,
  applySyncSettings,
  applyAppearanceSettings,
  applyMiscSettings,
} from './settings/SettingsWriters';

// 类型对外仍从本模块导出，调用方 import 路径不变
export type {
  AppSettings,
  SettingsPatch,
  PlayMode,
  ThemeMode,
  StartupPage,
  AddMusicLocation,
  DesktopLyricPosition,
  DesktopLyricTextPositionX,
  DesktopLyricTextPositionY,
  SyncMode,
  DownloadFileNameFormat,
  SourceNameType,
  ShareType,
} from './settings/SettingsTypes';
export type { S2TMode } from '../core/lyric/ChineseConvert';

const TAG = 'SettingsService';
const DOMAIN = 0x0005;
/** 字号设置 1.0 倍对应的基准值 */
const BASE_FONT_SIZE = 14;

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
      // 旧数据迁移与读取都在 settings/SettingsStorage（服务只负责写与广播）
      await migrateLegacySettings(this.context);
      this.values = await loadSettingsFromStorage();
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
    copy.wordLyric = source.wordLyric;
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
    copy.hapticFeedback = source.hapticFeedback;
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
    copy.downloadUseFilePicker = source.downloadUseFilePicker;
    copy.downloadFileName = source.downloadFileName;
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

    // 字段写入按域拆到 settings/SettingsWriters（逐段原样搬运，顺序不变）
    await applyBasicSettings(patch, this.values, changed, storage);
    await applyPlaybackSettings(patch, this.values, changed, storage);
    await applyLyricSettings(patch, this.values, changed, storage);
    await applySearchSettings(patch, this.values, changed, storage);
    await applyListSettings(patch, this.values, changed, storage);
    await applyDownloadSettings(patch, this.values, changed, storage);
    await applySyncSettings(patch, this.values, changed, storage);
    await applyAppearanceSettings(patch, this.values, changed, storage);
    await applyMiscSettings(patch, this.values, changed, storage);
    if (changed.indexOf('fontSize') >= 0) {
      this.applyFontScale();
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

  /**
   * 恢复默认设置。
   *
   * 只还原「外观 / 播放 / 列表 / 搜索 / 下载 / 桌面歌词」等可调项；
   * 下面四类属于用户身份或凭据，静默清掉会很伤（误触一次就要重新配置），因此保留：
   * syncEnabled / syncServer / syncKey（同步服务器与密钥）、agreedPact（已同意协议）。
   * 完整性由 scripts/check_settings_reset.py 守住：AppSettings 新增字段时，
   * 要么在这里出现，要么显式列进保留名单。
   */
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
      wordLyric: defaults.wordLyric,
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
      desktopLyricX: defaults.desktopLyricX,
      desktopLyricY: defaults.desktopLyricY,
      desktopLyricShadowColor: defaults.desktopLyricShadowColor,
      showListSource: defaults.showListSource,
      hapticFeedback: defaults.hapticFeedback,
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
      downloadPath: defaults.downloadPath,
      downloadUseFilePicker: defaults.downloadUseFilePicker,
      downloadFileName: defaults.downloadFileName,
      syncAutoSync: defaults.syncAutoSync,
      syncInterval: defaults.syncInterval,
      syncMode: defaults.syncMode,
      fontSize: defaults.fontSize,
      showAnimation: defaults.showAnimation,
    });
  }

  /**
   * 镜像到 AppStorage，驱动 @StorageProp / @StorageLink 组件刷新。
   *
   * 只镜像**真的有人读**的键（绑定或 AppStorage.get）：此前把 55 个设置项无差别镜像，
   * 其中 25 个全项目没有任何读取方，看代码会误以为"这些设置会自动流到界面"。
   * 新增需要 @StorageProp 的项时，在这里补一行（scripts/check_storage_bindings.py 会提示）。
   */
  /** 镜像到 AppStorage，驱动 @StorageProp / @StorageLink 组件刷新 */
  private applyToAppStorage(): void {
    AppStorage.setOrCreate('settingsReady', true);
    AppStorage.setOrCreate('theme', this.values.themeMode);
    AppStorage.setOrCreate('desktopLyricColor', this.values.desktopLyricColor);
    AppStorage.setOrCreate('desktopLyricBgAlpha', this.values.desktopLyricBgAlpha);
    AppStorage.setOrCreate('desktopLyricFontSize', this.values.desktopLyricFontSize);
    AppStorage.setOrCreate('desktopLyricLocked', this.values.desktopLyricLocked);
    AppStorage.setOrCreate('showAnimation', this.values.showAnimation);
    AppStorage.setOrCreate('showLyricTranslation', this.values.showLyricTranslation);
    AppStorage.setOrCreate('showLyricRoma', this.values.showLyricRoma);
    AppStorage.setOrCreate('wordLyric', this.values.wordLyric);
    AppStorage.setOrCreate('lyricFontSize', this.values.lyricFontSize);
    AppStorage.setOrCreate('lyricAlign', this.values.lyricAlign);
    AppStorage.setOrCreate('showLyricProgress', this.values.showLyricProgress);
    AppStorage.setOrCreate('desktopLyricMaxLines', this.values.desktopLyricMaxLines);
    AppStorage.setOrCreate('desktopLyricAnim', this.values.desktopLyricAnim);
    AppStorage.setOrCreate('desktopLyricShadowColor', this.values.desktopLyricShadowColor);
    AppStorage.setOrCreate('showListSource', this.values.showListSource);
    AppStorage.setOrCreate('showListAlbum', this.values.showListAlbum);
    AppStorage.setOrCreate('showListDuration', this.values.showListDuration);
    AppStorage.setOrCreate('rememberScrollPosition', this.values.rememberScrollPosition);
    AppStorage.setOrCreate('sourceNameType', this.values.sourceNameType);
    AppStorage.setOrCreate('allowProgressBarSeek', this.values.allowProgressBarSeek);
    AppStorage.setOrCreate('listClickPlay', this.values.listClickPlay);
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
