/**
 * 设置写入器：把 update() 的 if 链按域拆开
 *
 * 背景：SettingsService.update() 原本是一个 505 行的 if 链（81 个字段各一段），
 * 找「下载文件名是怎么落盘的」要顺着屏幕翻十几屏。这里按域分组、逐段原样搬运，
 * 逻辑与顺序完全不变，只是把「一行字段一个判断」的搬运搬到独立文件里。
 *
 * 约定：每个函数只做三件事 —— 判断是否变化 → 写内存快照 values → 记下 changed 名；
 * 持久化细节（StorageKeys、clamp）与拆分前一致。
 */
import { StorageKeys } from '../StorageService';
import type { IStorageService } from '../../core/interfaces/IStorageService';
import {
  clampNumber,
  normalizeS2TMode,
  toDlTextPosX,
  toDlTextPosY,
  toQuality,
  toShareType,
  toSourceNameType,
} from './SettingsTypes';
import type { AppSettings, SettingsPatch } from './SettingsTypes';


/** 基础与外观主题（语言 / 启动页 / 主题 / 字体） */
export async function applyBasicSettings(
  patch: SettingsPatch, values: AppSettings, changed: string[],
  storage: IStorageService): Promise<void> {
    if (patch.language !== undefined && patch.language !== values.language) {
      values.language = patch.language;
      await storage.setString(StorageKeys.LANGUAGE, patch.language);
      changed.push('language');
    }
    if (patch.startupPage !== undefined && patch.startupPage !== values.startupPage) {
      values.startupPage = patch.startupPage;
      await storage.setString(StorageKeys.STARTUP_PAGE, patch.startupPage);
      changed.push('startupPage');
    }
    if (patch.showExitDialog !== undefined && patch.showExitDialog !== values.showExitDialog) {
      values.showExitDialog = patch.showExitDialog;
      await storage.setBoolean(StorageKeys.SHOW_EXIT_DIALOG, patch.showExitDialog);
      changed.push('showExitDialog');
    }
    if (patch.themeMode !== undefined && patch.themeMode !== values.themeMode) {
      values.themeMode = patch.themeMode;
      await storage.setString(StorageKeys.THEME_MODE, patch.themeMode);
      changed.push('themeMode');
    }
    if (patch.themeId !== undefined && patch.themeId !== values.themeId) {
      values.themeId = patch.themeId;
      await storage.setString(StorageKeys.THEME_ID, patch.themeId);
      changed.push('themeId');
    }
    if (patch.autoTheme !== undefined && patch.autoTheme !== values.autoTheme) {
      values.autoTheme = patch.autoTheme;
      await storage.setBoolean(StorageKeys.COMMON_AUTO_THEME, patch.autoTheme);
      changed.push('autoTheme');
    }
    if (patch.themeLightId !== undefined && patch.themeLightId !== values.themeLightId) {
      values.themeLightId = patch.themeLightId;
      await storage.setString(StorageKeys.THEME_LIGHT_ID, patch.themeLightId);
      changed.push('themeLightId');
    }
    if (patch.themeDarkId !== undefined && patch.themeDarkId !== values.themeDarkId) {
      values.themeDarkId = patch.themeDarkId;
      await storage.setString(StorageKeys.THEME_DARK_ID, patch.themeDarkId);
      changed.push('themeDarkId');
    }
    if (patch.dynamicBg !== undefined && patch.dynamicBg !== values.dynamicBg) {
      values.dynamicBg = patch.dynamicBg;
      await storage.setBoolean(StorageKeys.THEME_DYNAMIC_BG, patch.dynamicBg);
      changed.push('dynamicBg');
    }
    if (patch.fontShadow !== undefined && patch.fontShadow !== values.fontShadow) {
      values.fontShadow = patch.fontShadow;
      await storage.setBoolean(StorageKeys.THEME_FONT_SHADOW, patch.fontShadow);
      changed.push('fontShadow');
    }
    if (patch.hideBgDark !== undefined && patch.hideBgDark !== values.hideBgDark) {
      values.hideBgDark = patch.hideBgDark;
      await storage.setBoolean(StorageKeys.THEME_HIDE_BG_DARK, patch.hideBgDark);
      changed.push('hideBgDark');
    }
}

/** 播放相关（音质 / 模式 / 倍速 / 音量 / 播控） */
export async function applyPlaybackSettings(
  patch: SettingsPatch, values: AppSettings, changed: string[],
  storage: IStorageService): Promise<void> {
    if (patch.autoPlay !== undefined && patch.autoPlay !== values.autoPlay) {
      values.autoPlay = patch.autoPlay;
      await storage.setBoolean(StorageKeys.PLAY_AUTO_PLAY, patch.autoPlay);
      changed.push('autoPlay');
    }
    if (patch.highQuality !== undefined && patch.highQuality !== values.highQuality) {
      values.highQuality = patch.highQuality;
      await storage.setBoolean(StorageKeys.PLAY_HIGH_QUALITY, patch.highQuality);
      changed.push('highQuality');
    }
    if (patch.playQuality !== undefined) {
      const next = toQuality(patch.playQuality, values.playQuality);
      if (next !== values.playQuality) {
        values.playQuality = next;
        await storage.setString(StorageKeys.PLAY_QUALITY, next);
        // 与旧的「高品质」开关保持同步，避免两处读到不同音质
        values.highQuality = next !== '128k';
        await storage.setBoolean(StorageKeys.PLAY_HIGH_QUALITY, values.highQuality);
        changed.push('playQuality');
        changed.push('highQuality');
      }
    }
    if (patch.playMode !== undefined && patch.playMode !== values.playMode) {
      values.playMode = patch.playMode;
      await storage.setString(StorageKeys.PLAY_MODE, patch.playMode);
      changed.push('playMode');
    }
    if (patch.playRate !== undefined) {
      const next = clampNumber(patch.playRate, 0.5, 2.0, values.playRate);
      if (Math.abs(next - values.playRate) > 0.001) {
        values.playRate = next;
        await storage.setNumber(StorageKeys.PLAY_RATE, next);
        changed.push('playRate');
      }
    }
    if (patch.savePlayTime !== undefined && patch.savePlayTime !== values.savePlayTime) {
      values.savePlayTime = patch.savePlayTime;
      await storage.setBoolean(StorageKeys.PLAY_SAVE_TIME, patch.savePlayTime);
      changed.push('savePlayTime');
    }
    if (patch.showNotificationImage !== undefined
      && patch.showNotificationImage !== values.showNotificationImage) {
      values.showNotificationImage = patch.showNotificationImage;
      await storage.setBoolean(StorageKeys.PLAY_NOTIFICATION_IMAGE, patch.showNotificationImage);
      changed.push('showNotificationImage');
    }
    if (patch.showBluetoothLyric !== undefined && patch.showBluetoothLyric !== values.showBluetoothLyric) {
      values.showBluetoothLyric = patch.showBluetoothLyric;
      await storage.setBoolean(StorageKeys.PLAY_BLUETOOTH_LYRIC, patch.showBluetoothLyric);
      changed.push('showBluetoothLyric');
    }
    if (patch.audioFocus !== undefined && patch.audioFocus !== values.audioFocus) {
      values.audioFocus = patch.audioFocus;
      await storage.setBoolean(StorageKeys.PLAY_AUDIO_FOCUS, patch.audioFocus);
      changed.push('audioFocus');
    }
    if (patch.audioOffload !== undefined && patch.audioOffload !== values.audioOffload) {
      values.audioOffload = patch.audioOffload;
      await storage.setBoolean(StorageKeys.PLAY_AUDIO_OFFLOAD, patch.audioOffload);
      changed.push('audioOffload');
    }
    if (patch.playerCacheSizeMb !== undefined) {
      const nextCache = clampNumber(patch.playerCacheSizeMb, 1, 64, values.playerCacheSizeMb);
      if (nextCache !== values.playerCacheSizeMb) {
        values.playerCacheSizeMb = nextCache;
        await storage.setNumber(StorageKeys.PLAY_CACHE_SIZE_MB, nextCache);
        changed.push('playerCacheSizeMb');
      }
    }
    if (patch.volume !== undefined) {
      const next = clampNumber(patch.volume, 0, 100, values.volume);
      if (next !== values.volume) {
        values.volume = next;
        await storage.setNumber(StorageKeys.PLAY_VOLUME, next);
        changed.push('volume');
      }
    }
    if (patch.sleepTimerEnabled !== undefined && patch.sleepTimerEnabled !== values.sleepTimerEnabled) {
      values.sleepTimerEnabled = patch.sleepTimerEnabled;
      await storage.setBoolean(StorageKeys.PLAY_SLEEP_ENABLED, patch.sleepTimerEnabled);
      changed.push('sleepTimerEnabled');
    }
    if (patch.sleepTimerMinutes !== undefined) {
      const next = clampNumber(patch.sleepTimerMinutes, 1, 600, values.sleepTimerMinutes);
      if (next !== values.sleepTimerMinutes) {
        values.sleepTimerMinutes = next;
        await storage.setNumber(StorageKeys.PLAY_SLEEP_MINUTES, next);
        changed.push('sleepTimerMinutes');
      }
    }
    if (patch.sleepTimerWaitTrackEnd !== undefined
      && patch.sleepTimerWaitTrackEnd !== values.sleepTimerWaitTrackEnd) {
      values.sleepTimerWaitTrackEnd = patch.sleepTimerWaitTrackEnd;
      await storage.setBoolean(StorageKeys.PLAY_SLEEP_WAIT_TRACK_END, patch.sleepTimerWaitTrackEnd);
      changed.push('sleepTimerWaitTrackEnd');
    }
    if (patch.showDesktopLyric !== undefined && patch.showDesktopLyric !== values.showDesktopLyric) {
      values.showDesktopLyric = patch.showDesktopLyric;
      await storage.setBoolean(StorageKeys.PLAY_DESKTOP_LYRIC, patch.showDesktopLyric);
      changed.push('showDesktopLyric');
    }
    if (patch.desktopLyricPosition !== undefined &&
      patch.desktopLyricPosition !== values.desktopLyricPosition) {
      values.desktopLyricPosition = patch.desktopLyricPosition;
      await storage.setString(StorageKeys.PLAY_DESKTOP_LYRIC_POSITION, patch.desktopLyricPosition);
      changed.push('desktopLyricPosition');
    }
    if (patch.desktopLyricColor !== undefined && patch.desktopLyricColor !== values.desktopLyricColor) {
      values.desktopLyricColor = patch.desktopLyricColor;
      await storage.setString(StorageKeys.PLAY_DESKTOP_LYRIC_COLOR, patch.desktopLyricColor);
      changed.push('desktopLyricColor');
    }
    if (patch.desktopLyricBgAlpha !== undefined) {
      const next = clampNumber(patch.desktopLyricBgAlpha, 0, 100, values.desktopLyricBgAlpha);
      if (next !== values.desktopLyricBgAlpha) {
        values.desktopLyricBgAlpha = next;
        await storage.setNumber(StorageKeys.PLAY_DESKTOP_LYRIC_BG_ALPHA, next);
        changed.push('desktopLyricBgAlpha');
      }
    }
    if (patch.desktopLyricFontSize !== undefined) {
      const next = clampNumber(patch.desktopLyricFontSize, 14, 32, values.desktopLyricFontSize);
      if (next !== values.desktopLyricFontSize) {
        values.desktopLyricFontSize = next;
        await storage.setNumber(StorageKeys.PLAY_DESKTOP_LYRIC_FONT_SIZE, next);
        changed.push('desktopLyricFontSize');
      }
    }
    if (patch.desktopLyricShowNext !== undefined && patch.desktopLyricShowNext !== values.desktopLyricShowNext) {
      values.desktopLyricShowNext = patch.desktopLyricShowNext;
      await storage.setBoolean(StorageKeys.PLAY_DESKTOP_LYRIC_SHOW_NEXT, patch.desktopLyricShowNext);
      changed.push('desktopLyricShowNext');
    }
    if (patch.desktopLyricLocked !== undefined && patch.desktopLyricLocked !== values.desktopLyricLocked) {
      values.desktopLyricLocked = patch.desktopLyricLocked;
      await storage.setBoolean(StorageKeys.PLAY_DESKTOP_LYRIC_LOCKED, patch.desktopLyricLocked);
      changed.push('desktopLyricLocked');
    }
    if (patch.desktopLyricX !== undefined && patch.desktopLyricX !== values.desktopLyricX) {
      values.desktopLyricX = patch.desktopLyricX;
      await storage.setNumber(StorageKeys.PLAY_DESKTOP_LYRIC_X, patch.desktopLyricX);
      changed.push('desktopLyricX');
    }
    if (patch.desktopLyricY !== undefined && patch.desktopLyricY !== values.desktopLyricY) {
      values.desktopLyricY = patch.desktopLyricY;
      await storage.setNumber(StorageKeys.PLAY_DESKTOP_LYRIC_Y, patch.desktopLyricY);
      changed.push('desktopLyricY');
    }
}

/** 歌词相关（字号 / 对齐 / 桌面歌词外观） */
export async function applyLyricSettings(
  patch: SettingsPatch, values: AppSettings, changed: string[],
  storage: IStorageService): Promise<void> {
    if (patch.desktopLyricWidth !== undefined) {
      const nextW = clampNumber(patch.desktopLyricWidth, 40, 100, values.desktopLyricWidth);
      if (nextW !== values.desktopLyricWidth) {
        values.desktopLyricWidth = nextW;
        await storage.setNumber(StorageKeys.PLAY_DL_WIDTH, nextW);
        changed.push('desktopLyricWidth');
      }
    }
    if (patch.desktopLyricMaxLines !== undefined) {
      const nextL = clampNumber(patch.desktopLyricMaxLines, 1, 3, values.desktopLyricMaxLines);
      if (nextL !== values.desktopLyricMaxLines) {
        values.desktopLyricMaxLines = nextL;
        await storage.setNumber(StorageKeys.PLAY_DL_MAX_LINES, nextL);
        changed.push('desktopLyricMaxLines');
      }
    }
    if (patch.desktopLyricAnim !== undefined && patch.desktopLyricAnim !== values.desktopLyricAnim) {
      values.desktopLyricAnim = patch.desktopLyricAnim;
      await storage.setBoolean(StorageKeys.PLAY_DL_ANIM, patch.desktopLyricAnim);
      changed.push('desktopLyricAnim');
    }
    if (patch.desktopLyricShadowColor !== undefined && patch.desktopLyricShadowColor !== values.desktopLyricShadowColor) {
      values.desktopLyricShadowColor = patch.desktopLyricShadowColor;
      await storage.setString(StorageKeys.PLAY_DL_SHADOW_COLOR, patch.desktopLyricShadowColor);
      changed.push('desktopLyricShadowColor');
    }
    if (patch.desktopLyricOutlineWidth !== undefined) {
      const nextOutline = clampNumber(patch.desktopLyricOutlineWidth, 0, 3, values.desktopLyricOutlineWidth);
      if (nextOutline !== values.desktopLyricOutlineWidth) {
        values.desktopLyricOutlineWidth = nextOutline;
        await storage.setNumber(StorageKeys.PLAY_DL_OUTLINE_WIDTH, nextOutline);
        changed.push('desktopLyricOutlineWidth');
      }
    }
    if (patch.desktopLyricOutlineColor !== undefined
      && patch.desktopLyricOutlineColor !== values.desktopLyricOutlineColor) {
      values.desktopLyricOutlineColor = patch.desktopLyricOutlineColor;
      await storage.setString(StorageKeys.PLAY_DL_OUTLINE_COLOR, patch.desktopLyricOutlineColor);
      changed.push('desktopLyricOutlineColor');
    }
    if (patch.desktopLyricFontWeight !== undefined && patch.desktopLyricFontWeight !== values.desktopLyricFontWeight) {
      values.desktopLyricFontWeight = patch.desktopLyricFontWeight;
      await storage.setString(StorageKeys.PLAY_DL_FONT_WEIGHT, patch.desktopLyricFontWeight);
      changed.push('desktopLyricFontWeight');
    }
    if (patch.desktopLyricCornerRadius !== undefined) {
      const nextRadius = clampNumber(patch.desktopLyricCornerRadius, 0, 28, values.desktopLyricCornerRadius);
      if (nextRadius !== values.desktopLyricCornerRadius) {
        values.desktopLyricCornerRadius = nextRadius;
        await storage.setNumber(StorageKeys.PLAY_DL_CORNER_RADIUS, nextRadius);
        changed.push('desktopLyricCornerRadius');
      }
    }
    if (patch.desktopLyricPadding !== undefined) {
      const nextPadding = clampNumber(patch.desktopLyricPadding, 0, 32, values.desktopLyricPadding);
      if (nextPadding !== values.desktopLyricPadding) {
        values.desktopLyricPadding = nextPadding;
        await storage.setNumber(StorageKeys.PLAY_DL_PADDING, nextPadding);
        changed.push('desktopLyricPadding');
      }
    }
    if (patch.desktopLyricAnimStyle !== undefined && patch.desktopLyricAnimStyle !== values.desktopLyricAnimStyle) {
      values.desktopLyricAnimStyle = patch.desktopLyricAnimStyle;
      await storage.setString(StorageKeys.PLAY_DL_ANIM_STYLE, patch.desktopLyricAnimStyle);
      changed.push('desktopLyricAnimStyle');
    }
    if (patch.lyricFontSize !== undefined) {
      const nextSize = clampNumber(patch.lyricFontSize, 14, 24, values.lyricFontSize);
      if (nextSize !== values.lyricFontSize) {
        values.lyricFontSize = nextSize;
        await storage.setNumber(StorageKeys.LYRIC_FONT_SIZE, nextSize);
        changed.push('lyricFontSize');
      }
    }
    if (patch.lyricAlign !== undefined && patch.lyricAlign !== values.lyricAlign) {
      values.lyricAlign = patch.lyricAlign;
      await storage.setString(StorageKeys.LYRIC_ALIGN, patch.lyricAlign);
      changed.push('lyricAlign');
    }
    if (patch.showLyricProgress !== undefined && patch.showLyricProgress !== values.showLyricProgress) {
      values.showLyricProgress = patch.showLyricProgress;
      await storage.setBoolean(StorageKeys.LYRIC_SHOW_PROGRESS, patch.showLyricProgress);
      changed.push('showLyricProgress');
    }
    if (patch.s2tMode !== undefined) {
      const mode = normalizeS2TMode(patch.s2tMode);
      if (mode !== values.s2tMode) {
        values.s2tMode = mode;
        await storage.setString(StorageKeys.LYRIC_S2T_MODE, mode);
        changed.push('s2tMode');
      }
    }
    if (patch.showLyricTranslation !== undefined && patch.showLyricTranslation !== values.showLyricTranslation) {
      values.showLyricTranslation = patch.showLyricTranslation;
      await storage.setBoolean(StorageKeys.LYRIC_SHOW_TRANSLATION, patch.showLyricTranslation);
      changed.push('showLyricTranslation');
    }
    if (patch.showLyricRoma !== undefined && patch.showLyricRoma !== values.showLyricRoma) {
      values.showLyricRoma = patch.showLyricRoma;
      await storage.setBoolean(StorageKeys.LYRIC_SHOW_ROMA, patch.showLyricRoma);
      changed.push('showLyricRoma');
    }
    if (patch.wordLyric !== undefined && patch.wordLyric !== values.wordLyric) {
      values.wordLyric = patch.wordLyric;
      await storage.setBoolean(StorageKeys.LYRIC_SHOW_WORD, patch.wordLyric);
      changed.push('wordLyric');
    }
    if (patch.lyricOffset !== undefined) {
      const next = clampNumber(patch.lyricOffset, -5, 5, values.lyricOffset);
      if (Math.abs(next - values.lyricOffset) > 0.001) {
        values.lyricOffset = next;
        await storage.setNumber(StorageKeys.LYRIC_OFFSET, next);
        changed.push('lyricOffset');
      }
    }
    if (patch.desktopLyricSingleLine !== undefined
      && patch.desktopLyricSingleLine !== values.desktopLyricSingleLine) {
      values.desktopLyricSingleLine = patch.desktopLyricSingleLine;
      await storage.setBoolean(StorageKeys.PLAY_DL_SINGLE_LINE, patch.desktopLyricSingleLine);
      changed.push('desktopLyricSingleLine');
    }
    if (patch.desktopLyricPlayedColor !== undefined
      && patch.desktopLyricPlayedColor !== values.desktopLyricPlayedColor) {
      values.desktopLyricPlayedColor = patch.desktopLyricPlayedColor;
      await storage.setString(StorageKeys.PLAY_DL_PLAYED_COLOR, patch.desktopLyricPlayedColor);
      changed.push('desktopLyricPlayedColor');
    }
    if (patch.desktopLyricTextPositionX !== undefined) {
      const next = toDlTextPosX(patch.desktopLyricTextPositionX);
      if (next !== values.desktopLyricTextPositionX) {
        values.desktopLyricTextPositionX = next;
        await storage.setString(StorageKeys.PLAY_DL_TEXT_POS_X, next);
        changed.push('desktopLyricTextPositionX');
      }
    }
    if (patch.desktopLyricTextPositionY !== undefined) {
      const next = toDlTextPosY(patch.desktopLyricTextPositionY);
      if (next !== values.desktopLyricTextPositionY) {
        values.desktopLyricTextPositionY = next;
        await storage.setString(StorageKeys.PLAY_DL_TEXT_POS_Y, next);
        changed.push('desktopLyricTextPositionY');
      }
    }
    if (patch.desktopLyricTextOpacity !== undefined) {
      const next = clampNumber(patch.desktopLyricTextOpacity, 20, 100, values.desktopLyricTextOpacity);
      if (next !== values.desktopLyricTextOpacity) {
        values.desktopLyricTextOpacity = next;
        await storage.setNumber(StorageKeys.PLAY_DL_TEXT_OPACITY, next);
        changed.push('desktopLyricTextOpacity');
      }
    }
}

/** 搜索相关 */
export async function applySearchSettings(
  patch: SettingsPatch, values: AppSettings, changed: string[],
  storage: IStorageService): Promise<void> {
    if (patch.showSearchHistory !== undefined
      && patch.showSearchHistory !== values.showSearchHistory) {
      values.showSearchHistory = patch.showSearchHistory;
      await storage.setBoolean(StorageKeys.SEARCH_SHOW_HISTORY, patch.showSearchHistory);
      changed.push('showSearchHistory');
    }
    if (patch.searchSource !== undefined && patch.searchSource !== values.searchSource) {
      values.searchSource = patch.searchSource;
      await storage.setString(StorageKeys.SEARCH_SOURCE, patch.searchSource);
      changed.push('searchSource');
    }
    if (patch.showHotSearch !== undefined && patch.showHotSearch !== values.showHotSearch) {
      values.showHotSearch = patch.showHotSearch;
      await storage.setBoolean(StorageKeys.SEARCH_SHOW_HOT, patch.showHotSearch);
      changed.push('showHotSearch');
    }
    if (patch.searchHistoryCount !== undefined) {
      const next = clampNumber(patch.searchHistoryCount, 1, 100, values.searchHistoryCount);
      if (next !== values.searchHistoryCount) {
        values.searchHistoryCount = next;
        await storage.setNumber(StorageKeys.SEARCH_HISTORY_LIMIT, next);
        changed.push('searchHistoryCount');
      }
    }
}

/** 列表相关 */
export async function applyListSettings(
  patch: SettingsPatch, values: AppSettings, changed: string[],
  storage: IStorageService): Promise<void> {
    if (patch.showListSource !== undefined && patch.showListSource !== values.showListSource) {
      values.showListSource = patch.showListSource;
      await storage.setBoolean(StorageKeys.LIST_SHOW_SOURCE, patch.showListSource);
      changed.push('showListSource');
    }
    if (patch.showListAlbum !== undefined && patch.showListAlbum !== values.showListAlbum) {
      values.showListAlbum = patch.showListAlbum;
      await storage.setBoolean(StorageKeys.LIST_SHOW_ALBUM, patch.showListAlbum);
      changed.push('showListAlbum');
    }
    if (patch.showListDuration !== undefined && patch.showListDuration !== values.showListDuration) {
      values.showListDuration = patch.showListDuration;
      await storage.setBoolean(StorageKeys.LIST_SHOW_DURATION, patch.showListDuration);
      changed.push('showListDuration');
    }
    if (patch.rememberScrollPosition !== undefined && patch.rememberScrollPosition !== values.rememberScrollPosition) {
      values.rememberScrollPosition = patch.rememberScrollPosition;
      await storage.setBoolean(StorageKeys.LIST_REMEMBER_SCROLL, patch.rememberScrollPosition);
      changed.push('rememberScrollPosition');
    }
    if (patch.listClickPlay !== undefined && patch.listClickPlay !== values.listClickPlay) {
      values.listClickPlay = patch.listClickPlay;
      await storage.setBoolean(StorageKeys.LIST_CLICK_PLAY, patch.listClickPlay);
      changed.push('listClickPlay');
    }
    if (patch.addMusicLocation !== undefined && patch.addMusicLocation !== values.addMusicLocation) {
      values.addMusicLocation = patch.addMusicLocation;
      await storage.setString(StorageKeys.LIST_ADD_LOCATION, patch.addMusicLocation);
      changed.push('addMusicLocation');
    }
    if (patch.autoCleanPlayedList !== undefined &&
      patch.autoCleanPlayedList !== values.autoCleanPlayedList) {
      values.autoCleanPlayedList = patch.autoCleanPlayedList;
      await storage.setBoolean(StorageKeys.LIST_AUTO_CLEAN_PLAYED, patch.autoCleanPlayedList);
      changed.push('autoCleanPlayedList');
    }
}

/** 下载相关 */
export async function applyDownloadSettings(
  patch: SettingsPatch, values: AppSettings, changed: string[],
  storage: IStorageService): Promise<void> {
    if (patch.downloadUseFilePicker !== undefined
      && patch.downloadUseFilePicker !== values.downloadUseFilePicker) {
      values.downloadUseFilePicker = patch.downloadUseFilePicker;
      await storage.setBoolean(StorageKeys.DOWNLOAD_USE_FILE_PICKER, patch.downloadUseFilePicker);
      changed.push('downloadUseFilePicker');
    }
    if (patch.downloadPath !== undefined && patch.downloadPath !== values.downloadPath) {
      values.downloadPath = patch.downloadPath;
      await storage.setString(StorageKeys.DOWNLOAD_PATH, patch.downloadPath);
      changed.push('downloadPath');
    }
    if (patch.downloadFileName !== undefined && patch.downloadFileName !== values.downloadFileName) {
      values.downloadFileName = patch.downloadFileName;
      await storage.setString(StorageKeys.DOWNLOAD_FILE_NAME, patch.downloadFileName);
      changed.push('downloadFileName');
    }
    if (patch.autoStartDownload !== undefined && patch.autoStartDownload !== values.autoStartDownload) {
      values.autoStartDownload = patch.autoStartDownload;
      await storage.setBoolean(StorageKeys.DOWNLOAD_AUTO_START, patch.autoStartDownload);
      changed.push('autoStartDownload');
    }
    if (patch.maxConcurrentDownloads !== undefined) {
      const next = clampNumber(patch.maxConcurrentDownloads, 1, 3, values.maxConcurrentDownloads);
      if (next !== values.maxConcurrentDownloads) {
        values.maxConcurrentDownloads = next;
        await storage.setNumber(StorageKeys.DOWNLOAD_MAX_CONCURRENT, next);
        changed.push('maxConcurrentDownloads');
      }
    }
}

/** 同步相关 */
export async function applySyncSettings(
  patch: SettingsPatch, values: AppSettings, changed: string[],
  storage: IStorageService): Promise<void> {
    if (patch.syncEnabled !== undefined && patch.syncEnabled !== values.syncEnabled) {
      values.syncEnabled = patch.syncEnabled;
      await storage.setBoolean(StorageKeys.SYNC_ENABLED, patch.syncEnabled);
      changed.push('syncEnabled');
    }
    if (patch.syncServer !== undefined && patch.syncServer !== values.syncServer) {
      values.syncServer = patch.syncServer;
      await storage.setString(StorageKeys.SYNC_SERVER, patch.syncServer);
      changed.push('syncServer');
    }
    if (patch.syncKey !== undefined && patch.syncKey !== values.syncKey) {
      values.syncKey = patch.syncKey;
      await storage.setString(StorageKeys.SYNC_KEY, patch.syncKey);
      changed.push('syncKey');
    }
    if (patch.syncInterval !== undefined) {
      const next = clampNumber(patch.syncInterval, 1, 1440, values.syncInterval);
      if (next !== values.syncInterval) {
        values.syncInterval = next;
        await storage.setNumber(StorageKeys.SYNC_INTERVAL, next);
        changed.push('syncInterval');
      }
    }
    if (patch.syncAutoSync !== undefined && patch.syncAutoSync !== values.syncAutoSync) {
      values.syncAutoSync = patch.syncAutoSync;
      await storage.setBoolean(StorageKeys.SYNC_AUTO_SYNC, patch.syncAutoSync);
      changed.push('syncAutoSync');
    }
    if (patch.syncMode !== undefined && patch.syncMode !== values.syncMode) {
      values.syncMode = patch.syncMode;
      await storage.setString(StorageKeys.SYNC_MODE, patch.syncMode);
      changed.push('syncMode');
    }
}

/** 外观（字号缩放 / 动画开关） */
export async function applyAppearanceSettings(
  patch: SettingsPatch, values: AppSettings, changed: string[],
  storage: IStorageService): Promise<void> {
    if (patch.fontSize !== undefined) {
      const next = clampNumber(patch.fontSize, 12, 24, values.fontSize);
      if (next !== values.fontSize) {
        values.fontSize = next;
        await storage.setNumber(StorageKeys.APPEARANCE_FONT_SIZE, next);
        changed.push('fontSize');
      }
    }
    if (patch.showAnimation !== undefined && patch.showAnimation !== values.showAnimation) {
      values.showAnimation = patch.showAnimation;
      await storage.setBoolean(StorageKeys.APPEARANCE_SHOW_ANIMATION, patch.showAnimation);
      changed.push('showAnimation');
    }
}

/** 其它（触感反馈 / 日志 / 源名显示 / 分享方式等） */
export async function applyMiscSettings(
  patch: SettingsPatch, values: AppSettings, changed: string[],
  storage: IStorageService): Promise<void> {
    if (patch.hapticFeedback !== undefined && patch.hapticFeedback !== values.hapticFeedback) {
      values.hapticFeedback = patch.hapticFeedback;
      await storage.setBoolean(StorageKeys.HAPTIC_FEEDBACK, patch.hapticFeedback);
      changed.push('hapticFeedback');
    }
    if (patch.enableVerboseLog !== undefined && patch.enableVerboseLog !== values.enableVerboseLog) {
      values.enableVerboseLog = patch.enableVerboseLog;
      await storage.setBoolean(StorageKeys.LOG_VERBOSE, patch.enableVerboseLog);
      changed.push('enableVerboseLog');
    }
    if (patch.sourceNameType !== undefined) {
      const next = toSourceNameType(patch.sourceNameType);
      if (next !== values.sourceNameType) {
        values.sourceNameType = next;
        await storage.setString(StorageKeys.COMMON_SOURCE_NAME_TYPE, next);
        changed.push('sourceNameType');
      }
    }
    if (patch.shareType !== undefined) {
      const next = toShareType(patch.shareType);
      if (next !== values.shareType) {
        values.shareType = next;
        await storage.setString(StorageKeys.COMMON_SHARE_TYPE, next);
        changed.push('shareType');
      }
    }
    if (patch.agreedPact !== undefined && patch.agreedPact !== values.agreedPact) {
      values.agreedPact = patch.agreedPact;
      await storage.setBoolean(StorageKeys.COMMON_AGREE_PACT, patch.agreedPact);
      changed.push('agreedPact');
    }
    if (patch.allowProgressBarSeek !== undefined
      && patch.allowProgressBarSeek !== values.allowProgressBarSeek) {
      values.allowProgressBarSeek = patch.allowProgressBarSeek;
      await storage.setBoolean(StorageKeys.COMMON_ALLOW_PROGRESS_SEEK, patch.allowProgressBarSeek);
      changed.push('allowProgressBarSeek');
    }
}
