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
import { StorageKeys } from './StorageService';
import { appLog as hilog } from '../core/log/AppLogger';
import {
  createDefaultSettings,
  clampNumber,
  normalizeS2TMode,
  toDlTextPosX,
  toDlTextPosY,
  toQuality,
  toShareType,
  toSourceNameType,
  type AppSettings,
  type SettingsPatch,
} from './settings/SettingsTypes';
import { loadSettingsFromStorage, migrateLegacySettings } from './settings/SettingsStorage';

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
    if (patch.hapticFeedback !== undefined && patch.hapticFeedback !== this.values.hapticFeedback) {
      this.values.hapticFeedback = patch.hapticFeedback;
      await storage.setBoolean(StorageKeys.HAPTIC_FEEDBACK, patch.hapticFeedback);
      changed.push('hapticFeedback');
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

    if (patch.downloadUseFilePicker !== undefined
      && patch.downloadUseFilePicker !== this.values.downloadUseFilePicker) {
      this.values.downloadUseFilePicker = patch.downloadUseFilePicker;
      await storage.setBoolean(StorageKeys.DOWNLOAD_USE_FILE_PICKER, patch.downloadUseFilePicker);
      changed.push('downloadUseFilePicker');
    }
    if (patch.downloadPath !== undefined && patch.downloadPath !== this.values.downloadPath) {
      this.values.downloadPath = patch.downloadPath;
      await storage.setString(StorageKeys.DOWNLOAD_PATH, patch.downloadPath);
      changed.push('downloadPath');
    }
    if (patch.downloadFileName !== undefined && patch.downloadFileName !== this.values.downloadFileName) {
      this.values.downloadFileName = patch.downloadFileName;
      await storage.setString(StorageKeys.DOWNLOAD_FILE_NAME, patch.downloadFileName);
      changed.push('downloadFileName');
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
    AppStorage.setOrCreate('hapticFeedback', this.values.hapticFeedback);
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
