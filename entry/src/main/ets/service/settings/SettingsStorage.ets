/**
 * 设置项的存储加载与旧版本迁移
 *
 * 职责：把 Preferences 里的键值读成 AppSettings，并在首次启动时把历史版本
 * （music_settings / download_settings）里的旧值迁移过来。
 * 从 SettingsService 拆出后，服务类只关心「写设置 + 广播」，加载细节独立成文件。
 */
import preferences from '@ohos.data.preferences';
import type { common } from '@kit.AbilityKit';
import { getStorageService } from '../../core/interfaces/IStorageService';
import { StorageKeys } from '../StorageService';
import { appLog as hilog } from '../../core/log/AppLogger';
import {
  createDefaultSettings,
  clampNumber,
  toAddMusicLocation,
  toDesktopLyricPosition,
  toDlTextPosX,
  toDlTextPosY,
  toPlayMode,
  toQuality,
  toShareType,
  toSourceNameType,
  toStartupPage,
  toThemeMode,
  normalizeS2TMode,
  type AppSettings,
} from './SettingsTypes';

const TAG = 'SettingsStorage';
const DOMAIN = 0x0005;

const LEGACY_SETTINGS_STORE = 'music_settings';
const LEGACY_DOWNLOAD_STORE = 'download_settings';




export async function migrateLegacySettings(context: common.UIAbilityContext | null): Promise<void> {
    if (!context) {
      return;
    }
    const storage = getStorageService();
    try {
      const migrated = await storage.getBoolean(StorageKeys.SETTINGS_MIGRATED, false);
      if (migrated) {
        return;
      }

      const legacy = await preferences.getPreferences(context, LEGACY_SETTINGS_STORE);
      await migrateString(legacy, 'language', StorageKeys.LANGUAGE);
      await migrateString(legacy, 'startupPage', StorageKeys.STARTUP_PAGE);
      await migrateBoolean(legacy, 'showExitDialog', StorageKeys.SHOW_EXIT_DIALOG);
      await migrateString(legacy, 'theme', StorageKeys.THEME_MODE);

      await migrateBoolean(legacy, 'autoPlay', StorageKeys.PLAY_AUTO_PLAY);
      await migrateBoolean(legacy, 'highQuality', StorageKeys.PLAY_HIGH_QUALITY);
      await migrateString(legacy, 'playMode', StorageKeys.PLAY_MODE);
      await migrateNumber(legacy, 'volume', StorageKeys.PLAY_VOLUME);
      await migrateBoolean(legacy, 'timeoutExit', StorageKeys.PLAY_SLEEP_ENABLED);
      await migrateNumber(legacy, 'timeoutMinutes', StorageKeys.PLAY_SLEEP_MINUTES);
      await migrateBoolean(legacy, 'showDesktopLyric', StorageKeys.PLAY_DESKTOP_LYRIC);

      await migrateString(legacy, 'searchSource', StorageKeys.SEARCH_SOURCE);
      await migrateBoolean(legacy, 'showHotSearch', StorageKeys.SEARCH_SHOW_HOT);
      await migrateNumber(legacy, 'searchHistoryCount', StorageKeys.SEARCH_HISTORY_LIMIT);

      await migrateString(legacy, 'listAddMusicLocation', StorageKeys.LIST_ADD_LOCATION);
      await migrateBoolean(legacy, 'autoCleanPlayedList', StorageKeys.LIST_AUTO_CLEAN_PLAYED);

      await migrateBoolean(legacy, 'syncEnable', StorageKeys.SYNC_ENABLED);
      await migrateString(legacy, 'syncServer', StorageKeys.SYNC_SERVER);
      await migrateString(legacy, 'syncKey', StorageKeys.SYNC_KEY);

      await migrateNumber(legacy, 'fontSize', StorageKeys.APPEARANCE_FONT_SIZE);
      await migrateBoolean(legacy, 'showAnimation', StorageKeys.APPEARANCE_SHOW_ANIMATION);

      // 下载设置历史上存在独立的存储实例
      const legacyDownload = await preferences.getPreferences(context, LEGACY_DOWNLOAD_STORE);
      await migrateString(legacyDownload, 'downloadPath', StorageKeys.DOWNLOAD_PATH);
      await migrateBoolean(legacyDownload, 'autoStartDownload', StorageKeys.DOWNLOAD_AUTO_START);
      await migrateNumber(legacyDownload, 'maxConcurrentDownloads', StorageKeys.DOWNLOAD_MAX_CONCURRENT);

      // 旧版同步配置独立存储在 sync_config
      const legacySync = await preferences.getPreferences(context, 'sync_config');
      await migrateBoolean(legacySync, 'enabled', StorageKeys.SYNC_ENABLED);
      await migrateString(legacySync, 'serverUrl', StorageKeys.SYNC_SERVER);
      await migrateString(legacySync, 'syncKey', StorageKeys.SYNC_KEY);
      await migrateNumber(legacySync, 'syncInterval', StorageKeys.SYNC_INTERVAL);
      await migrateBoolean(legacySync, 'autoSync', StorageKeys.SYNC_AUTO_SYNC);

      await storage.setBoolean(StorageKeys.SETTINGS_MIGRATED, true);
      hilog.info(DOMAIN, TAG, 'Legacy settings migrated');
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.warn(DOMAIN, TAG, 'Legacy settings migration skipped: %{public}s', msg);
    }
  }


async function migrateString(
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


async function migrateNumber(
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


async function migrateBoolean(
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

export async function loadSettingsFromStorage(): Promise<AppSettings> {
    const storage = getStorageService();
    const defaults = createDefaultSettings();
    const settings = defaults;

    settings.language = await storage.getString(StorageKeys.LANGUAGE, defaults.language);
    settings.startupPage = toStartupPage(
      await storage.getString(StorageKeys.STARTUP_PAGE, defaults.startupPage), defaults.startupPage);
    settings.showExitDialog = await storage.getBoolean(StorageKeys.SHOW_EXIT_DIALOG, defaults.showExitDialog);
    settings.themeMode = toThemeMode(
      await storage.getString(StorageKeys.THEME_MODE, defaults.themeMode), defaults.themeMode);
    settings.themeId = await storage.getString(StorageKeys.THEME_ID, defaults.themeId);
    settings.autoTheme = await storage.getBoolean(StorageKeys.COMMON_AUTO_THEME, defaults.autoTheme);
    settings.themeLightId = await storage.getString(StorageKeys.THEME_LIGHT_ID, defaults.themeLightId);
    settings.themeDarkId = await storage.getString(StorageKeys.THEME_DARK_ID, defaults.themeDarkId);
    settings.dynamicBg = await storage.getBoolean(StorageKeys.THEME_DYNAMIC_BG, defaults.dynamicBg);
    settings.fontShadow = await storage.getBoolean(StorageKeys.THEME_FONT_SHADOW, defaults.fontShadow);
    settings.hideBgDark = await storage.getBoolean(StorageKeys.THEME_HIDE_BG_DARK, defaults.hideBgDark);

    settings.autoPlay = await storage.getBoolean(StorageKeys.PLAY_AUTO_PLAY, defaults.autoPlay);
    settings.highQuality = await storage.getBoolean(StorageKeys.PLAY_HIGH_QUALITY, defaults.highQuality);
    // 音质：旧版本只有「高品质」开关，首次读不到 playQuality 时按开关值迁移
    const legacyQualityKey = await storage.getString(StorageKeys.PLAY_QUALITY, '');
    settings.playQuality = legacyQualityKey.length > 0
      ? toQuality(legacyQualityKey, defaults.playQuality)
      : (settings.highQuality ? 'flac24bit' : defaults.playQuality);
    settings.playMode = toPlayMode(
      await storage.getString(StorageKeys.PLAY_MODE, defaults.playMode), defaults.playMode);
    settings.playRate = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_RATE, defaults.playRate), 0.5, 2.0, defaults.playRate);
    settings.savePlayTime = await storage.getBoolean(StorageKeys.PLAY_SAVE_TIME, defaults.savePlayTime);
    settings.showNotificationImage = await storage.getBoolean(
      StorageKeys.PLAY_NOTIFICATION_IMAGE, defaults.showNotificationImage);
    settings.showBluetoothLyric = await storage.getBoolean(
      StorageKeys.PLAY_BLUETOOTH_LYRIC, defaults.showBluetoothLyric);
    settings.showLyricTranslation = await storage.getBoolean(
      StorageKeys.LYRIC_SHOW_TRANSLATION, defaults.showLyricTranslation);
    settings.showLyricRoma = await storage.getBoolean(StorageKeys.LYRIC_SHOW_ROMA, defaults.showLyricRoma);
    settings.lyricFontSize = clampNumber(
      await storage.getNumber(StorageKeys.LYRIC_FONT_SIZE, defaults.lyricFontSize), 14, 24, defaults.lyricFontSize);
    settings.lyricAlign = await storage.getString(StorageKeys.LYRIC_ALIGN, defaults.lyricAlign);
    settings.showLyricProgress = await storage.getBoolean(StorageKeys.LYRIC_SHOW_PROGRESS, defaults.showLyricProgress);
    settings.desktopLyricWidth = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_DL_WIDTH, defaults.desktopLyricWidth), 40, 100, defaults.desktopLyricWidth);
    settings.desktopLyricMaxLines = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_DL_MAX_LINES, defaults.desktopLyricMaxLines), 1, 3,
      defaults.desktopLyricMaxLines);
    settings.desktopLyricSingleLine = await storage.getBoolean(
      StorageKeys.PLAY_DL_SINGLE_LINE, defaults.desktopLyricSingleLine);
    settings.desktopLyricPlayedColor = await storage.getString(
      StorageKeys.PLAY_DL_PLAYED_COLOR, defaults.desktopLyricPlayedColor);
    settings.desktopLyricTextPositionX = toDlTextPosX(
      await storage.getString(StorageKeys.PLAY_DL_TEXT_POS_X, defaults.desktopLyricTextPositionX));
    settings.desktopLyricTextPositionY = toDlTextPosY(
      await storage.getString(StorageKeys.PLAY_DL_TEXT_POS_Y, defaults.desktopLyricTextPositionY));
    settings.desktopLyricTextOpacity = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_DL_TEXT_OPACITY, defaults.desktopLyricTextOpacity), 20, 100,
      defaults.desktopLyricTextOpacity);
    settings.desktopLyricAnim = await storage.getBoolean(StorageKeys.PLAY_DL_ANIM, defaults.desktopLyricAnim);
    settings.desktopLyricShadowColor = await storage.getString(
      StorageKeys.PLAY_DL_SHADOW_COLOR, defaults.desktopLyricShadowColor);
    settings.showListSource = await storage.getBoolean(StorageKeys.LIST_SHOW_SOURCE, defaults.showListSource);
    settings.hapticFeedback = await storage.getBoolean(StorageKeys.HAPTIC_FEEDBACK, defaults.hapticFeedback);
    settings.showListAlbum = await storage.getBoolean(StorageKeys.LIST_SHOW_ALBUM, defaults.showListAlbum);
    settings.showListDuration = await storage.getBoolean(StorageKeys.LIST_SHOW_DURATION, defaults.showListDuration);
    settings.rememberScrollPosition = await storage.getBoolean(
      StorageKeys.LIST_REMEMBER_SCROLL, defaults.rememberScrollPosition);
    settings.enableVerboseLog = await storage.getBoolean(
      StorageKeys.LOG_VERBOSE, defaults.enableVerboseLog);
    settings.s2tMode = normalizeS2TMode(
      await storage.getString(StorageKeys.LYRIC_S2T_MODE, defaults.s2tMode));
    settings.sourceNameType = toSourceNameType(
      await storage.getString(StorageKeys.COMMON_SOURCE_NAME_TYPE, defaults.sourceNameType));
    settings.shareType = toShareType(
      await storage.getString(StorageKeys.COMMON_SHARE_TYPE, defaults.shareType));
    settings.agreedPact = await storage.getBoolean(StorageKeys.COMMON_AGREE_PACT, defaults.agreedPact);
    settings.allowProgressBarSeek = await storage.getBoolean(
      StorageKeys.COMMON_ALLOW_PROGRESS_SEEK, defaults.allowProgressBarSeek);
    settings.showSearchHistory = await storage.getBoolean(
      StorageKeys.SEARCH_SHOW_HISTORY, defaults.showSearchHistory);
    settings.listClickPlay = await storage.getBoolean(
      StorageKeys.LIST_CLICK_PLAY, defaults.listClickPlay);
    settings.audioFocus = await storage.getBoolean(StorageKeys.PLAY_AUDIO_FOCUS, defaults.audioFocus);
    settings.audioOffload = await storage.getBoolean(StorageKeys.PLAY_AUDIO_OFFLOAD, defaults.audioOffload);
    settings.playerCacheSizeMb = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_CACHE_SIZE_MB, defaults.playerCacheSizeMb), 1, 64,
      defaults.playerCacheSizeMb);
    settings.lyricOffset = clampNumber(
      await storage.getNumber(StorageKeys.LYRIC_OFFSET, defaults.lyricOffset), -5, 5, defaults.lyricOffset);
    settings.volume = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_VOLUME, defaults.volume), 0, 100, defaults.volume);
    settings.sleepTimerEnabled = await storage.getBoolean(
      StorageKeys.PLAY_SLEEP_ENABLED, defaults.sleepTimerEnabled);
    settings.sleepTimerMinutes = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_SLEEP_MINUTES, defaults.sleepTimerMinutes), 1, 600,
      defaults.sleepTimerMinutes);
    settings.sleepTimerWaitTrackEnd = await storage.getBoolean(
      StorageKeys.PLAY_SLEEP_WAIT_TRACK_END, defaults.sleepTimerWaitTrackEnd);
    settings.showDesktopLyric = await storage.getBoolean(
      StorageKeys.PLAY_DESKTOP_LYRIC, defaults.showDesktopLyric);
    settings.desktopLyricPosition = toDesktopLyricPosition(
      await storage.getString(StorageKeys.PLAY_DESKTOP_LYRIC_POSITION, defaults.desktopLyricPosition),
      defaults.desktopLyricPosition);
    settings.desktopLyricColor = await storage.getString(
      StorageKeys.PLAY_DESKTOP_LYRIC_COLOR, defaults.desktopLyricColor);
    settings.desktopLyricBgAlpha = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_DESKTOP_LYRIC_BG_ALPHA, defaults.desktopLyricBgAlpha),
      0, 100, defaults.desktopLyricBgAlpha);
    settings.desktopLyricFontSize = clampNumber(
      await storage.getNumber(StorageKeys.PLAY_DESKTOP_LYRIC_FONT_SIZE, defaults.desktopLyricFontSize),
      14, 32, defaults.desktopLyricFontSize);
    settings.desktopLyricShowNext = await storage.getBoolean(
      StorageKeys.PLAY_DESKTOP_LYRIC_SHOW_NEXT, defaults.desktopLyricShowNext);
    settings.desktopLyricLocked = await storage.getBoolean(
      StorageKeys.PLAY_DESKTOP_LYRIC_LOCKED, defaults.desktopLyricLocked);
    settings.desktopLyricX = await storage.getNumber(StorageKeys.PLAY_DESKTOP_LYRIC_X, defaults.desktopLyricX);
    settings.desktopLyricY = await storage.getNumber(StorageKeys.PLAY_DESKTOP_LYRIC_Y, defaults.desktopLyricY);

    settings.searchSource = await storage.getString(StorageKeys.SEARCH_SOURCE, defaults.searchSource);
    settings.showHotSearch = await storage.getBoolean(StorageKeys.SEARCH_SHOW_HOT, defaults.showHotSearch);
    settings.searchHistoryCount = clampNumber(
      await storage.getNumber(StorageKeys.SEARCH_HISTORY_LIMIT, defaults.searchHistoryCount), 1, 100,
      defaults.searchHistoryCount);

    settings.addMusicLocation = toAddMusicLocation(
      await storage.getString(StorageKeys.LIST_ADD_LOCATION, defaults.addMusicLocation),
      defaults.addMusicLocation);
    settings.autoCleanPlayedList = await storage.getBoolean(
      StorageKeys.LIST_AUTO_CLEAN_PLAYED, defaults.autoCleanPlayedList);

    settings.downloadPath = await storage.getString(StorageKeys.DOWNLOAD_PATH, defaults.downloadPath);
    settings.downloadUseFilePicker = await storage.getBoolean(
      StorageKeys.DOWNLOAD_USE_FILE_PICKER, defaults.downloadUseFilePicker);
    settings.autoStartDownload = await storage.getBoolean(
      StorageKeys.DOWNLOAD_AUTO_START, defaults.autoStartDownload);
    settings.maxConcurrentDownloads = clampNumber(
      await storage.getNumber(StorageKeys.DOWNLOAD_MAX_CONCURRENT, defaults.maxConcurrentDownloads), 1, 3,
      defaults.maxConcurrentDownloads);

    settings.syncEnabled = await storage.getBoolean(StorageKeys.SYNC_ENABLED, defaults.syncEnabled);
    settings.syncServer = await storage.getString(StorageKeys.SYNC_SERVER, defaults.syncServer);
    settings.syncKey = await storage.getString(StorageKeys.SYNC_KEY, defaults.syncKey);
    settings.syncInterval = clampNumber(
      await storage.getNumber(StorageKeys.SYNC_INTERVAL, defaults.syncInterval), 1, 1440, defaults.syncInterval);
    settings.syncAutoSync = await storage.getBoolean(StorageKeys.SYNC_AUTO_SYNC, defaults.syncAutoSync);
    settings.syncMode = await storage.getString(StorageKeys.SYNC_MODE, defaults.syncMode) === 'server'
      ? 'server' : 'client';

    settings.fontSize = clampNumber(
      await storage.getNumber(StorageKeys.APPEARANCE_FONT_SIZE, defaults.fontSize), 12, 24, defaults.fontSize);
    settings.showAnimation = await storage.getBoolean(
      StorageKeys.APPEARANCE_SHOW_ANIMATION, defaults.showAnimation);
    return settings;
  }
