/**
 * 数据存储服务
 * 使用 HarmonyOS Preferences 实现数据持久化
 *
 * 全应用唯一 Preferences 实例：设置项、歌单、插件配置、搜索历史等都写在这里。
 * 对外暴露两种等价用法：默认导出的对象（StorageService.getString 等）与命名导出函数。
 */
import { preferences as dataPreferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import type { common } from '@kit.AbilityKit';
import {
  setStorageService,
  getStorageService,
  createMemoryStorageService,
  type IStorageService
} from '../core/interfaces/IStorageService';
import { CARD_PREFERENCES_NAME, CARD_FORM_IDS_KEY, CARD_SNAPSHOT_KEY } from '../utils/CardFormKeys';

const TAG = 'StorageService';
const DOMAIN = 0x0003;
// 值定义在 utils/CardFormKeys（卡片进程跨进程契约），这里转出保持既有引用不变
export const PREFERENCES_NAME = CARD_PREFERENCES_NAME;

// 全局上下文变量
let abilityContext: common.UIAbilityContext | null = null;

/**
 * 设置应用上下文
 */
export function setContext(context: common.UIAbilityContext): void {
  abilityContext = context;
}

/**
 * 获取应用上下文
 */
function getContext(): common.UIAbilityContext {
  if (abilityContext) {
    return abilityContext;
  }
  throw new Error('Unable to get context - context not set');
}

/**
 * 初始化存储服务
 */
export async function initStorage(): Promise<void> {
  try {
    // 获取应用首选项
    const context = getContext();
    const preferences = await dataPreferences.getPreferences(context, PREFERENCES_NAME);
    hilog.info(DOMAIN, TAG, 'StorageService initialized');

    // 键名迁移：theme.* 曾经直接作为键名写入，现统一为 setting.* 前缀
    await renameLegacyKey(preferences, 'theme.id', StorageKeys.THEME_ID);
    await renameLegacyKey(preferences, 'theme.mode', StorageKeys.THEME_MODE);

    // 注入存储服务到核心层
    const serviceImpl: IStorageService = new StorageServiceImpl(preferences);
    setStorageService(serviceImpl);
  } catch (err) {
    hilog.warn(
      DOMAIN,
      TAG,
      'Preferences unavailable (Previewer / no persistence), using in-memory storage: %{public}s',
      JSON.stringify(err)
    );
    setStorageService(createMemoryStorageService());
  }
}

/**
 * 把旧键名的值迁移到新键名（新键已存在时不覆盖，旧键保留以免数据丢失）
 */
async function renameLegacyKey(
  prefs: dataPreferences.Preferences, legacyKey: string, newKey: string
): Promise<void> {
  try {
    if (await prefs.has(newKey)) {
      return;
    }
    if (!(await prefs.has(legacyKey))) {
      return;
    }
    const value = await prefs.get(legacyKey, '');
    if (value !== undefined && value !== null) {
      await prefs.put(newKey, value);
      await prefs.flush();
      hilog.info(DOMAIN, TAG, 'Legacy key migrated: %{public}s -> %{public}s', legacyKey, newKey);
    }
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'Legacy key migration failed for %{public}s: %{public}s',
      legacyKey, JSON.stringify(err));
  }
}

// 存储服务实现类（实现IStorageService接口）
class StorageServiceImpl implements IStorageService {
  private prefs: dataPreferences.Preferences;

  constructor(prefs: dataPreferences.Preferences) {
    this.prefs = prefs;
  }

  async getString(key: string, defaultValue: string = ''): Promise<string> {
    try {
      const value = await this.prefs.get(key, defaultValue);
      return value as string;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getString failed: %{public}s', (e as Error)?.message);
      return defaultValue;
    }
  }

  async getNumber(key: string, defaultValue: number = 0): Promise<number> {
    try {
      const value = await this.prefs.get(key, defaultValue);
      return value as number;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getNumber failed: %{public}s', (e as Error)?.message);
      return defaultValue;
    }
  }

  async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    try {
      const value = await this.prefs.get(key, defaultValue);
      return value as boolean;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'getBoolean failed: %{public}s', (e as Error)?.message);
      return defaultValue;
    }
  }

  async setString(key: string, value: string): Promise<void> {
    try {
      await this.prefs.put(key, value);
      await this.prefs.flush();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setString failed: %{public}s', JSON.stringify(e));
    }
  }

  async setNumber(key: string, value: number): Promise<void> {
    try {
      await this.prefs.put(key, value);
      await this.prefs.flush();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setNumber failed: %{public}s', JSON.stringify(e));
    }
  }

  async setBoolean(key: string, value: boolean): Promise<void> {
    try {
      await this.prefs.put(key, value);
      await this.prefs.flush();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'setBoolean failed: %{public}s', JSON.stringify(e));
    }
  }

  async remove(key: string): Promise<void> {
    try {
      await this.prefs.delete(key);
      await this.prefs.flush();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'remove failed: %{public}s', JSON.stringify(e));
    }
  }

  async clear(): Promise<void> {
    try {
      await this.prefs.clear();
      await this.prefs.flush();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'clear failed: %{public}s', JSON.stringify(e));
    }
  }

  async has(key: string): Promise<boolean> {
    try {
      return await this.prefs.has(key);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'has failed: %{public}s', JSON.stringify(e));
      return false;
    }
  }
}

/**
 * 获取字符串值
 */
export async function getString(key: string, defaultValue: string = ''): Promise<string> {
  return getStorageService().getString(key, defaultValue);
}

/**
 * 获取数字值
 */
export async function getNumber(key: string, defaultValue: number = 0): Promise<number> {
  return getStorageService().getNumber(key, defaultValue);
}

/**
 * 获取布尔值
 */
export async function getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
  return getStorageService().getBoolean(key, defaultValue);
}

/**
 * 设置字符串值
 */
export async function setString(key: string, value: string): Promise<void> {
  return getStorageService().setString(key, value);
}

/**
 * 设置数字值
 */
export async function setNumber(key: string, value: number): Promise<void> {
  return getStorageService().setNumber(key, value);
}

/**
 * 设置布尔值
 */
export async function setBoolean(key: string, value: boolean): Promise<void> {
  return getStorageService().setBoolean(key, value);
}

/**
 * 删除值
 */
export async function remove(key: string): Promise<void> {
  return getStorageService().remove(key);
}

/**
 * 清空所有数据
 */
export async function clear(): Promise<void> {
  return getStorageService().clear();
}

/**
 * 检查键是否存在
 */
export async function has(key: string): Promise<boolean> {
  return getStorageService().has(key);
}

/**
 * 存储键名接口
 * 约定：设置类键统一使用 setting.* 前缀，业务数据使用各自前缀。
 */
interface StorageKeysInterface {
  // 基础设置
  SETTINGS_MIGRATED: string;
  LANGUAGE: string;
  STARTUP_PAGE: string;
  SHOW_EXIT_DIALOG: string;
  THEME_MODE: string;
  THEME_ID: string;
  COMMON_AUTO_THEME: string;
  THEME_LIGHT_ID: string;
  THEME_DARK_ID: string;
  THEME_DYNAMIC_BG: string;
  THEME_FONT_SHADOW: string;
  THEME_HIDE_BG_DARK: string;

  // 播放设置
  PLAY_AUTO_PLAY: string;
  PLAY_HIGH_QUALITY: string;
  PLAY_QUALITY: string;
  PLAY_MODE: string;
  PLAY_RATE: string;
  LYRIC_OFFSET: string;
  PLAY_SAVE_TIME: string;
  PLAY_NOTIFICATION_IMAGE: string;
  PLAY_BLUETOOTH_LYRIC: string;
  LYRIC_SHOW_TRANSLATION: string;
  LYRIC_FONT_SIZE: string;
  LYRIC_ALIGN: string;
  LYRIC_SHOW_PROGRESS: string;
  LIST_SHOW_SOURCE: string;
  LIST_SHOW_ALBUM: string;
  LIST_SHOW_DURATION: string;
  LIST_REMEMBER_SCROLL: string;
  LYRIC_SHOW_ROMA: string;
  /** 逐字歌词（卡拉OK 高亮） */
  LYRIC_SHOW_WORD: string;
  LOG_VERBOSE: string;
  LYRIC_S2T_MODE: string;
  HAPTIC_FEEDBACK: string;
  COMMON_SOURCE_NAME_TYPE: string;
  /** 音源启用顺序（逗号分隔的音源 id，见 core/music/SourcePolicy） */
  COMMON_SOURCE_ORDER: string;
  /** 已停用的音源（逗号分隔的音源 id） */
  COMMON_SOURCES_DISABLED: string;
  COMMON_SHARE_TYPE: string;
  COMMON_AGREE_PACT: string;
  COMMON_ALLOW_PROGRESS_SEEK: string;
  SEARCH_SHOW_HISTORY: string;
  LIST_CLICK_PLAY: string;
  PLAY_AUDIO_FOCUS: string;
  PLAY_AUDIO_OFFLOAD: string;
  PLAY_CACHE_SIZE_MB: string;
  PLAY_VOLUME: string;
  PLAY_SLEEP_ENABLED: string;
  PLAY_SLEEP_MINUTES: string;
  PLAY_SLEEP_WAIT_TRACK_END: string;
  /** 取源失败时自动跨源切换 */
  PLAY_AUTO_SOURCE_SWITCH: string;
  PLAY_DESKTOP_LYRIC: string;
  PLAY_DESKTOP_LYRIC_POSITION: string;
  PLAY_DESKTOP_LYRIC_COLOR: string;
  PLAY_DESKTOP_LYRIC_BG_ALPHA: string;
  PLAY_DESKTOP_LYRIC_FONT_SIZE: string;
  PLAY_DESKTOP_LYRIC_SHOW_NEXT: string;
  PLAY_DESKTOP_LYRIC_LOCKED: string;
  PLAY_DESKTOP_LYRIC_X: string;
  PLAY_DL_WIDTH: string;
  PLAY_DL_MAX_LINES: string;
  PLAY_DL_SINGLE_LINE: string;
  PLAY_DL_PLAYED_COLOR: string;
  PLAY_DL_TEXT_POS_X: string;
  PLAY_DL_TEXT_POS_Y: string;
  PLAY_DL_TEXT_OPACITY: string;
  PLAY_DL_ANIM: string;
  PLAY_DL_SHADOW_COLOR: string;
  PLAY_DL_OUTLINE_WIDTH: string;
  PLAY_DL_OUTLINE_COLOR: string;
  PLAY_DL_FONT_WEIGHT: string;
  PLAY_DL_CORNER_RADIUS: string;
  PLAY_DL_PADDING: string;
  PLAY_DL_ANIM_STYLE: string;
  PLAY_DESKTOP_LYRIC_Y: string;

  // 搜索设置
  SEARCH_SOURCE: string;
  SEARCH_SHOW_HOT: string;
  SEARCH_HISTORY_LIMIT: string;

  // 列表设置
  LIST_ADD_LOCATION: string;
  LIST_AUTO_CLEAN_PLAYED: string;

  // 下载设置
  DOWNLOAD_PATH: string;
  DOWNLOAD_USE_FILE_PICKER: string;
  DOWNLOAD_FILE_NAME: string;
  DOWNLOAD_AUTO_START: string;
  DOWNLOAD_MAX_CONCURRENT: string;

  // 同步设置
  SYNC_ENABLED: string;
  SYNC_SERVER: string;
  SYNC_KEY: string;
  SYNC_INTERVAL: string;
  SYNC_AUTO_SYNC: string;
  SYNC_MODE: string;

  // 外观设置
  APPEARANCE_FONT_SIZE: string;
  APPEARANCE_SHOW_ANIMATION: string;

  // 列表数据
  LIST_DEFAULT: string;
  LIST_LOVE: string;
  LIST_USER: string;
  /** 收藏的在线歌单 */
  COLLECTION_SONGLISTS: string;
  /** 本地音乐曲库 */
  LOCAL_MUSIC_LIST: string;

  // 桌面卡片（CardFormAbility 运行在独立进程，经 preferences 共享；见 widget/CardFormPrefs）
  /** 已注册卡片的 formId 列表（JSON 字符串数组，由卡片进程写，UI 进程只读） */
  CARD_FORM_IDS: string;
  /** 卡片快照（JSON：title/singer/cover/playing/lyric，仅 UI 进程写，卡片进程只读） */
  CARD_SNAPSHOT: string;
}

// 存储键名常量
export const StorageKeys: StorageKeysInterface = {
  // 基础设置
  SETTINGS_MIGRATED: 'setting.internal.migrated',
  LANGUAGE: 'setting.common.language',
  STARTUP_PAGE: 'setting.common.startupPage',
  SHOW_EXIT_DIALOG: 'setting.common.showExitDialog',
  THEME_MODE: 'setting.common.themeMode',
  THEME_ID: 'setting.common.themeId',
  COMMON_AUTO_THEME: 'setting.common.isAutoTheme',
  THEME_LIGHT_ID: 'setting.theme.lightId',
  THEME_DARK_ID: 'setting.theme.darkId',
  THEME_DYNAMIC_BG: 'setting.theme.dynamicBg',
  THEME_FONT_SHADOW: 'setting.theme.fontShadow',
  THEME_HIDE_BG_DARK: 'setting.theme.hideBgDark',

  // 播放设置
  PLAY_AUTO_PLAY: 'setting.play.autoPlay',
  PLAY_HIGH_QUALITY: 'setting.play.highQuality',
  PLAY_QUALITY: 'setting.play.playQuality',
  PLAY_MODE: 'setting.play.playMode',
  PLAY_RATE: 'setting.play.playRate',
  LYRIC_OFFSET: 'setting.play.lyricOffset',
  PLAY_SAVE_TIME: 'setting.play.savePlayTime',
  PLAY_NOTIFICATION_IMAGE: 'setting.play.notificationImage',
  PLAY_BLUETOOTH_LYRIC: 'setting.play.bluetoothLyric',
  LYRIC_SHOW_TRANSLATION: 'setting.lyric.showTranslation',
  LYRIC_FONT_SIZE: 'setting.lyric.fontSize',
  LYRIC_ALIGN: 'setting.lyric.align',
  LYRIC_SHOW_PROGRESS: 'setting.lyric.showProgress',
  LIST_SHOW_SOURCE: 'setting.list.showSource',
  LIST_SHOW_ALBUM: 'setting.list.showAlbum',
  LIST_SHOW_DURATION: 'setting.list.showDuration',
  LIST_REMEMBER_SCROLL: 'setting.list.rememberScroll',
  LYRIC_SHOW_ROMA: 'setting.lyric.showRoma',
  LYRIC_SHOW_WORD: 'setting.lyric.showWord',
  LOG_VERBOSE: 'setting.log.verbose',
  LYRIC_S2T_MODE: 'setting.lyric.s2tMode',
  HAPTIC_FEEDBACK: 'setting.ui.hapticFeedback',
  COMMON_SOURCE_NAME_TYPE: 'setting.common.sourceNameType',
  COMMON_SOURCE_ORDER: 'setting.common.sourceOrder',
  COMMON_SOURCES_DISABLED: 'setting.common.sourcesDisabled',
  COMMON_SHARE_TYPE: 'setting.common.shareType',
  COMMON_AGREE_PACT: 'setting.common.isAgreePact',
  COMMON_ALLOW_PROGRESS_SEEK: 'setting.common.allowProgressBarSeek',
  SEARCH_SHOW_HISTORY: 'setting.search.showHistorySearch',
  LIST_CLICK_PLAY: 'setting.list.isClickPlayList',
  PLAY_AUDIO_FOCUS: 'setting.play.audioFocus',
  PLAY_AUDIO_OFFLOAD: 'setting.play.audioOffload',
  PLAY_CACHE_SIZE_MB: 'setting.play.cacheSizeMb',
  PLAY_VOLUME: 'setting.play.volume',
  PLAY_SLEEP_ENABLED: 'setting.play.sleepTimerEnabled',
  PLAY_SLEEP_MINUTES: 'setting.play.sleepTimerMinutes',
  PLAY_SLEEP_WAIT_TRACK_END: 'setting.play.sleepTimerWaitTrackEnd',
  PLAY_AUTO_SOURCE_SWITCH: 'setting.play.autoSourceSwitch',
  PLAY_DESKTOP_LYRIC: 'setting.play.desktopLyric',
  PLAY_DESKTOP_LYRIC_POSITION: 'setting.play.desktopLyricPosition',
  PLAY_DESKTOP_LYRIC_COLOR: 'setting.play.desktopLyricColor',
  PLAY_DESKTOP_LYRIC_BG_ALPHA: 'setting.play.desktopLyricBgAlpha',
  PLAY_DESKTOP_LYRIC_FONT_SIZE: 'setting.play.desktopLyricFontSize',
  PLAY_DESKTOP_LYRIC_SHOW_NEXT: 'setting.play.desktopLyricShowNext',
  PLAY_DESKTOP_LYRIC_LOCKED: 'setting.play.desktopLyricLocked',
  PLAY_DESKTOP_LYRIC_X: 'setting.play.desktopLyricX',
  PLAY_DL_WIDTH: 'setting.play.desktopLyricWidth',
  PLAY_DL_MAX_LINES: 'setting.play.desktopLyricMaxLines',
  PLAY_DL_SINGLE_LINE: 'setting.play.desktopLyricSingleLine',
  PLAY_DL_PLAYED_COLOR: 'setting.play.desktopLyricPlayedColor',
  PLAY_DL_TEXT_POS_X: 'setting.play.desktopLyricTextPositionX',
  PLAY_DL_TEXT_POS_Y: 'setting.play.desktopLyricTextPositionY',
  PLAY_DL_TEXT_OPACITY: 'setting.play.desktopLyricTextOpacity',
  PLAY_DL_ANIM: 'setting.play.desktopLyricAnim',
  PLAY_DL_SHADOW_COLOR: 'setting.play.desktopLyricShadowColor',
  PLAY_DL_OUTLINE_WIDTH: 'setting.play.desktopLyricOutlineWidth',
  PLAY_DL_OUTLINE_COLOR: 'setting.play.desktopLyricOutlineColor',
  PLAY_DL_FONT_WEIGHT: 'setting.play.desktopLyricFontWeight',
  PLAY_DL_CORNER_RADIUS: 'setting.play.desktopLyricCornerRadius',
  PLAY_DL_PADDING: 'setting.play.desktopLyricPadding',
  PLAY_DL_ANIM_STYLE: 'setting.play.desktopLyricAnimStyle',
  PLAY_DESKTOP_LYRIC_Y: 'setting.play.desktopLyricY',

  // 搜索设置
  SEARCH_SOURCE: 'setting.search.source',
  SEARCH_SHOW_HOT: 'setting.search.showHotSearch',
  SEARCH_HISTORY_LIMIT: 'setting.search.historyLimit',

  // 列表设置
  LIST_ADD_LOCATION: 'setting.list.addMusicLocation',
  LIST_AUTO_CLEAN_PLAYED: 'setting.list.autoCleanPlayedList',

  // 下载设置
  DOWNLOAD_PATH: 'setting.download.path',
  DOWNLOAD_USE_FILE_PICKER: 'setting.download.useFilePicker',
  DOWNLOAD_FILE_NAME: 'setting.download.fileName',
  DOWNLOAD_AUTO_START: 'setting.download.autoStart',
  DOWNLOAD_MAX_CONCURRENT: 'setting.download.maxConcurrent',

  // 同步设置
  SYNC_ENABLED: 'setting.sync.enabled',
  SYNC_SERVER: 'setting.sync.server',
  SYNC_KEY: 'setting.sync.key',
  SYNC_INTERVAL: 'setting.sync.interval',
  SYNC_AUTO_SYNC: 'setting.sync.autoSync',
  SYNC_MODE: 'setting.sync.mode',

  // 外观设置
  APPEARANCE_FONT_SIZE: 'setting.appearance.fontSize',
  APPEARANCE_SHOW_ANIMATION: 'setting.appearance.showAnimation',

  // 列表数据
  LIST_DEFAULT: 'list.default',
  LIST_LOVE: 'list.love',
  LIST_USER: 'list.user',

  // 收藏
  COLLECTION_SONGLISTS: 'collection.songlists',

  // 本地音乐
  LOCAL_MUSIC_LIST: 'local.music.list',

  // 桌面卡片（跨进程桥接键，值定义在 utils/CardFormKeys，写入方约定见 StorageKeysInterface 注释）
  CARD_FORM_IDS: CARD_FORM_IDS_KEY,
  CARD_SNAPSHOT: CARD_SNAPSHOT_KEY,
};

// 存储服务接口
export interface StorageServiceInterface {
  setContext: (context: common.UIAbilityContext) => void;
  initStorage: () => Promise<void>;
  getString: (key: string, defaultValue?: string) => Promise<string>;
  getNumber: (key: string, defaultValue?: number) => Promise<number>;
  getBoolean: (key: string, defaultValue?: boolean) => Promise<boolean>;
  setString: (key: string, value: string) => Promise<void>;
  setNumber: (key: string, value: number) => Promise<void>;
  setBoolean: (key: string, value: boolean) => Promise<void>;
  remove: (key: string) => Promise<void>;
  clear: () => Promise<void>;
  has: (key: string) => Promise<boolean>;
  StorageKeys: StorageKeysInterface;
}

// 导出存储服务（默认导出）
const storageService: StorageServiceInterface = {
  setContext,
  initStorage,
  getString,
  getNumber,
  getBoolean,
  setString,
  setNumber,
  setBoolean,
  remove,
  clear,
  has,
  StorageKeys,
};

export default storageService;

// 命名导出
export { storageService };
