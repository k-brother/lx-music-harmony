/**
 * 数据存储服务
 * 使用 HarmonyOS Preferences 实现数据持久化
 *
 * 全应用唯一 Preferences 实例：设置项、歌单、插件配置、搜索历史等都写在这里。
 * 对外暴露两种等价用法：默认导出的对象（StorageService.getString 等）与命名导出函数。
 */
import dataPreferences from '@ohos.data.preferences';
import hilog from '@ohos.hilog';
import type { common } from '@kit.AbilityKit';
import {
  setStorageService,
  getStorageService,
  createMemoryStorageService,
  type IStorageService
} from '../core/interfaces/IStorageService';

const TAG = 'StorageService';
const DOMAIN = 0x0003;
const PREFERENCES_NAME = 'lx_music_preferences';

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

  // 播放设置
  PLAY_AUTO_PLAY: string;
  PLAY_HIGH_QUALITY: string;
  PLAY_MODE: string;
  PLAY_VOLUME: string;
  PLAY_SLEEP_ENABLED: string;
  PLAY_SLEEP_MINUTES: string;
  PLAY_DESKTOP_LYRIC: string;
  PLAY_DESKTOP_LYRIC_POSITION: string;
  PLAY_DESKTOP_LYRIC_COLOR: string;

  // 搜索设置
  SEARCH_SOURCE: string;
  SEARCH_SHOW_HOT: string;
  SEARCH_HISTORY_LIMIT: string;

  // 列表设置
  LIST_ADD_LOCATION: string;
  LIST_AUTO_CLEAN_PLAYED: string;

  // 下载设置
  DOWNLOAD_PATH: string;
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

  // 播放设置
  PLAY_AUTO_PLAY: 'setting.play.autoPlay',
  PLAY_HIGH_QUALITY: 'setting.play.highQuality',
  PLAY_MODE: 'setting.play.playMode',
  PLAY_VOLUME: 'setting.play.volume',
  PLAY_SLEEP_ENABLED: 'setting.play.sleepTimerEnabled',
  PLAY_SLEEP_MINUTES: 'setting.play.sleepTimerMinutes',
  PLAY_DESKTOP_LYRIC: 'setting.play.desktopLyric',
  PLAY_DESKTOP_LYRIC_POSITION: 'setting.play.desktopLyricPosition',
  PLAY_DESKTOP_LYRIC_COLOR: 'setting.play.desktopLyricColor',

  // 搜索设置
  SEARCH_SOURCE: 'setting.search.source',
  SEARCH_SHOW_HOT: 'setting.search.showHotSearch',
  SEARCH_HISTORY_LIMIT: 'setting.search.historyLimit',

  // 列表设置
  LIST_ADD_LOCATION: 'setting.list.addMusicLocation',
  LIST_AUTO_CLEAN_PLAYED: 'setting.list.autoCleanPlayedList',

  // 下载设置
  DOWNLOAD_PATH: 'setting.download.path',
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
