/**
 * 数据存储服务
 * 使用 HarmonyOS Preferences 实现数据持久化
 */
import dataPreferences from '@ohos.data.preferences';
import hilog from '@ohos.hilog';
import type { common } from '@kit.AbilityKit';
import { setStorageService, type IStorageService } from '../core/interfaces/IStorageService';

const TAG = 'StorageService';
const DOMAIN = 0x0003;

// 存储实例
let preferences: dataPreferences.Preferences | null = null;

// 默认值接口
interface DefaultValues {
  'setting.common.apiSource': string;
  'setting.common.sourceNames.kw': string;
  'setting.common.sourceNames.tx': string;
  'setting.common.sourceNames.mg': string;
  'setting.common.sourceNames.wy': string;
  'setting.play.autoPlay': boolean;
  'setting.play.volume': number;
  'setting.search.searchHistory': boolean;
  'setting.search.maxSearchHistory': number;
  'theme.mode': string;
}

// 默认值
const DEFAULT_VALUES: DefaultValues = {
  'setting.common.apiSource': 'kw',
  'setting.common.sourceNames.kw': '酷我',
  'setting.common.sourceNames.tx': 'QQ音乐',
  'setting.common.sourceNames.mg': '咪咕',
  'setting.common.sourceNames.wy': '网易',
  'setting.play.autoPlay': false,
  'setting.play.volume': 1.0,
  'setting.search.searchHistory': true,
  'setting.search.maxSearchHistory': 50,
  'theme.mode': 'light',
};

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
    preferences = await dataPreferences.getPreferences(context, 'lx_music_preferences');
    hilog.info(DOMAIN, TAG, 'StorageService initialized');

    // 注入存储服务到核心层
    const serviceImpl: IStorageService = new StorageServiceImpl(preferences!);
    setStorageService(serviceImpl);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to init storage: %{public}s', JSON.stringify(err));
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
    } catch {
      return defaultValue;
    }
  }

  async getNumber(key: string, defaultValue: number = 0): Promise<number> {
    try {
      const value = await this.prefs.get(key, defaultValue);
      return value as number;
    } catch {
      return defaultValue;
    }
  }

  async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    try {
      const value = await this.prefs.get(key, defaultValue);
      return value as boolean;
    } catch {
      return defaultValue;
    }
  }

  async setString(key: string, value: string): Promise<void> {
    await this.prefs.put(key, value);
    await this.prefs.flush();
  }

  async setNumber(key: string, value: number): Promise<void> {
    await this.prefs.put(key, value);
    await this.prefs.flush();
  }

  async setBoolean(key: string, value: boolean): Promise<void> {
    await this.prefs.put(key, value);
    await this.prefs.flush();
  }

  async remove(key: string): Promise<void> {
    await this.prefs.delete(key);
    await this.prefs.flush();
  }

  async clear(): Promise<void> {
    await this.prefs.clear();
    await this.prefs.flush();
  }

  async has(key: string): Promise<boolean> {
    return await this.prefs.has(key);
  }
}

/**
 * 获取字符串值
 */
export async function getString(key: string, defaultValue: string = ''): Promise<string> {
  if (!preferences) return defaultValue;
  try {
    const value = await preferences.get(key, defaultValue);
    return value as string;
  } catch (e) {
    return defaultValue;
  }
}

/**
 * 获取数字值
 */
export async function getNumber(key: string, defaultValue: number = 0): Promise<number> {
  if (!preferences) return defaultValue;
  try {
    const value = await preferences.get(key, defaultValue);
    return value as number;
  } catch (e) {
    return defaultValue;
  }
}

/**
 * 获取布尔值
 */
export async function getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
  if (!preferences) return defaultValue;
  try {
    const value = await preferences.get(key, defaultValue);
    return value as boolean;
  } catch (e) {
    return defaultValue;
  }
}

/**
 * 设置字符串值
 */
export async function setString(key: string, value: string): Promise<void> {
  if (!preferences) return;
  try {
    await preferences.put(key, value);
    await preferences.flush();
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to set string: %{public}s', JSON.stringify(err));
  }
}

/**
 * 设置数字值
 */
export async function setNumber(key: string, value: number): Promise<void> {
  if (!preferences) return;
  try {
    await preferences.put(key, value);
    await preferences.flush();
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to set number: %{public}s', JSON.stringify(err));
  }
}

/**
 * 设置布尔值
 */
export async function setBoolean(key: string, value: boolean): Promise<void> {
  if (!preferences) return;
  try {
    await preferences.put(key, value);
    await preferences.flush();
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to set boolean: %{public}s', JSON.stringify(err));
  }
}

/**
 * 删除值
 */
export async function remove(key: string): Promise<void> {
  if (!preferences) return;
  try {
    await preferences.delete(key);
    await preferences.flush();
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to remove: %{public}s', JSON.stringify(err));
  }
}

/**
 * 清空所有数据
 */
export async function clear(): Promise<void> {
  if (!preferences) return;
  try {
    await preferences.clear();
    await preferences.flush();
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to clear: %{public}s', JSON.stringify(err));
  }
}

/**
 * 检查键是否存在
 */
export async function has(key: string): Promise<boolean> {
  if (!preferences) return false;
  try {
    return await preferences.has(key);
  } catch (e) {
    return false;
  }
}

// 存储键名接口
interface StorageKeysInterface {
  API_SOURCE: string;
  SOURCE_NAME_KW: string;
  SOURCE_NAME_TX: string;
  SOURCE_NAME_MG: string;
  SOURCE_NAME_WY: string;
  PLAY_AUTO_PLAY: string;
  PLAY_VOLUME: string;
  PLAY_CONTINUE: string;
  PLAY_INDEX: string;
  PLAY_TIMER: string;
  PLAY_TIMEOUT_EXIT: string;
  PLAY_QUALITY: string;
  PLAY_HIGH_QUALITY: string;
  SEARCH_HISTORY: string;
  SEARCH_MAX_HISTORY: string;
  THEME_MODE: string;
  THEME_ID: string;
  THEME_COLOR: string;
  LIST_DEFAULT: string;
  LIST_LOVE: string;
  LIST_USER: string;
}

// 存储键名常量
export const StorageKeys: StorageKeysInterface = {
  // 通用设置
  API_SOURCE: 'setting.common.apiSource',
  SOURCE_NAME_KW: 'setting.common.sourceNames.kw',
  SOURCE_NAME_TX: 'setting.common.sourceNames.tx',
  SOURCE_NAME_MG: 'setting.common.sourceNames.mg',
  SOURCE_NAME_WY: 'setting.common.sourceNames.wy',

  // 播放设置
  PLAY_AUTO_PLAY: 'setting.play.autoPlay',
  PLAY_VOLUME: 'setting.play.volume',
  PLAY_CONTINUE: 'setting.play.continuePlay',
  PLAY_INDEX: 'setting.play.playIndex',
  PLAY_TIMER: 'setting.play.playerTimer',
  PLAY_TIMEOUT_EXIT: 'setting.play.timeoutExit',

  // 播放音质
  PLAY_QUALITY: 'setting.player.playQuality',
  PLAY_HIGH_QUALITY: 'setting.player.isPlayHighQuality',

  // 搜索设置
  SEARCH_HISTORY: 'setting.search.searchHistory',
  SEARCH_MAX_HISTORY: 'setting.search.maxSearchHistory',

  // 主题设置
  THEME_MODE: 'theme.mode',
  THEME_ID: 'theme.id',
  THEME_COLOR: 'theme.color',

  // 列表数据
  LIST_DEFAULT: 'list.default',
  LIST_LOVE: 'list.love',
  LIST_USER: 'list.user',
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
