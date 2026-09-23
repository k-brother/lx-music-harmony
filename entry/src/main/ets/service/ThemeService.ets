/**
 * 主题服务 - 基于安卓源码主题系统迁移
 * 支持多主题切换、背景图、完整主题颜色（含运行时 alpha 计算）
 */
import hilog from '@ohos.hilog';
import StorageService from './StorageService';
import { getDefaultThemes, getThemeById, DEFAULT_THEME_ID } from '../core/theme/themes';
import { ActiveTheme } from '../types/ThemeTypes';
import type { ThemeItem } from '../types/ThemeTypes';
import { settingsService } from './SettingsService';

const TAG = 'ThemeService';
const DOMAIN = 0x0004;

// 主题状态
class ThemeState {
  currentThemeId: string = DEFAULT_THEME_ID;
  currentTheme: ThemeItem | undefined;
  activeTheme: ActiveTheme | undefined;
  isDark: boolean = false;
}

const themeState = new ThemeState();

// 主题监听器
type ThemeChangeListener = (theme: ActiveTheme) => void;
const listeners: ThemeChangeListener[] = [];

/**
 * 解析 rgb/rgba 颜色为 [r, g, b, a]
 */
function parseColor(color: string): number[] {
  const match = color.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/);
  if (match) {
    return [
      parseInt(match[1]),
      parseInt(match[2]),
      parseInt(match[3]),
      match[4] ? parseFloat(match[4]) : 1.0
    ];
  }
  return [0, 0, 0, 1.0];
}

/**
 * 修改透明度
 * @param p 透明度 0.0 到 1.0
 */
function alphaShade(p: number, color: string): string {
  const parsed = parseColor(color);
  return `rgba(${parsed[0]}, ${parsed[1]}, ${parsed[2]}, ${p.toFixed(2)})`;
}

/**
 * 解析 var() 引用
 */
function resolveVar(color: string, theme: ActiveTheme): string {
  if (color.startsWith('var(')) {
    const varName = color.replace(/^var\((.+)\)$/, '$1');
    return theme.get(varName) || color;
  }
  return color;
}

/**
 * 构建活跃主题（运行时颜色 + alpha 变体）
 */
function buildActiveTheme(themeItem: ThemeItem): ActiveTheme {
  const activeTheme = new ActiveTheme(
    themeItem.id,
    themeItem.name,
    themeItem.isDark
  );

  // 复制基础颜色（themeColors 是 Map）
  const themeColors = themeItem.config.themeColors;
  if (themeColors) {
    const keys = Array.from(themeColors.keys());
    let i = 0;
    while (i < keys.length) {
      const key = keys[i];
      activeTheme.set(key, themeColors.get(key) || '');
      i++;
    }
  }

  const extInfo = themeItem.config.extInfo;

  // 生成所有 alpha 变体（须在解析 extInfo 中的 var(...) 之前完成：如 var(c-primary-light-600-alpha-700)）
  const primary = activeTheme.get('c-primary');

  // primary 的 alpha 变体
  for (let j = 1; j <= 9; j++) {
    activeTheme.set(`c-primary-alpha-${j * 100}`, alphaShade(0.1 * j, primary));
  }

  // dark 变体的 alpha
  const darkKeys = ['c-primary-dark-100', 'c-primary-dark-200', 'c-primary-dark-300',
    'c-primary-dark-400', 'c-primary-dark-500', 'c-primary-dark-600',
    'c-primary-dark-700', 'c-primary-dark-800', 'c-primary-dark-900', 'c-primary-dark-1000'];
  darkKeys.forEach(darkKey => {
    if (activeTheme.has(darkKey)) {
      const color = activeTheme.get(darkKey);
      for (let j = 1; j <= 9; j++) {
        activeTheme.set(`${darkKey}-alpha-${j * 100}`, alphaShade(0.1 * j, color));
      }
    }
  });

  // light 变体的 alpha
  const lightKeys = ['c-primary-light-100', 'c-primary-light-200', 'c-primary-light-300',
    'c-primary-light-400', 'c-primary-light-500', 'c-primary-light-600',
    'c-primary-light-700', 'c-primary-light-800', 'c-primary-light-900', 'c-primary-light-1000'];
  lightKeys.forEach(lightKey => {
    if (activeTheme.has(lightKey)) {
      const color = activeTheme.get(lightKey);
      for (let j = 1; j <= 9; j++) {
        activeTheme.set(`${lightKey}-alpha-${j * 100}`, alphaShade(0.1 * j, color));
      }
    }
  });

  // 扩展信息依赖上面生成的 alpha 键等，故在此解析 var(...)
  activeTheme.set('c-app-background', resolveVar(extInfo.cAppBackground, activeTheme));
  activeTheme.set('c-main-background', resolveVar(extInfo.cMainBackground, activeTheme));
  activeTheme.set('bg-image', resolveVar(extInfo.bgImage, activeTheme));
  activeTheme.set('bg-image-position', resolveVar(extInfo.bgImagePosition, activeTheme));
  activeTheme.set('bg-image-size', resolveVar(extInfo.bgImageSize, activeTheme));
  activeTheme.set('c-badge-primary', resolveVar(extInfo.cBadgePrimary, activeTheme));
  activeTheme.set('c-badge-secondary', resolveVar(extInfo.cBadgeSecondary, activeTheme));
  activeTheme.set('c-badge-tertiary', resolveVar(extInfo.cBadgeTertiary, activeTheme));

  // 设置衍生颜色
  activeTheme.set('c-font', activeTheme.get('c-850') || 'rgb(66,66,66)');
  activeTheme.set('c-font-label', activeTheme.get('c-450') || 'rgb(155,155,155)');
  activeTheme.set('c-primary-font', primary);

  return activeTheme;
}

/**
 * 初始化主题服务
 */
export async function initTheme(): Promise<void> {
  try {
    const savedThemeId = await StorageService.getString(
      StorageService.StorageKeys.THEME_ID,
      DEFAULT_THEME_ID
    );
    await applyThemeById(savedThemeId);
    hilog.info(DOMAIN, TAG, 'ThemeService initialized, theme: %{public}s', savedThemeId);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to init theme: %{public}s', JSON.stringify(err));
    await applyThemeById(DEFAULT_THEME_ID);
  }
}

/**
 * 根据 id 应用主题
 * @param persist 是否把该 id 记为「用户手动选择的主题」；自动跟随系统深浅色时传 false，
 *                避免系统切换把用户手动选的主题覆盖掉
 */
export async function applyThemeById(themeId: string, persist: boolean = true): Promise<void> {
  const theme = getThemeById(themeId);
  if (!theme) {
    hilog.warn(DOMAIN, TAG, 'Theme not found: %{public}s, using default', themeId);
    return;
  }

  themeState.currentThemeId = themeId;
  themeState.currentTheme = theme;
  themeState.isDark = theme.isDark;
  themeState.activeTheme = buildActiveTheme(theme);

  // 更新 StorageProp 的 theme 值
  AppStorage.setOrCreate('theme', theme.isDark ? 'dark' : 'light');

  // 保存设置（自动模式下不覆盖用户手动选择的主题）
  if (persist) {
    // 统一走设置服务：它同时负责落库、刷新缓存并广播 SETTING_CHANGED。
    // 早期直接写 StorageService，导致 SettingsService 缓存里的 themeId 与实际主题不同步——
    // 设置页显示的还是旧主题名，重启后才暴露真实值。
    await settingsService.update({ themeId });
  }

  // 通知所有监听器
  notifyListeners();
}

// ==================== 自动跟随系统深浅色（安卓版 common.isAutoTheme） ====================

/** 系统当前是否深色（由 EntryAbility 在启动与系统配置变化时推送） */
let systemDarkMode: boolean = false;


/**
 * 系统深浅色变化时调用（EntryAbility.onConfigurationUpdate / 启动时一次）
 * 仅在「自动跟随系统」开启时立即切换主题
 */
export function setSystemDarkMode(isDark: boolean): void {
  if (systemDarkMode === isDark) {
    return;
  }
  systemDarkMode = isDark;
  if (settingsService.get().autoTheme) {
    applyAutoTheme().catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'applyAutoTheme failed: %{public}s', err.message);
    });
  }
}

/**
 * 按系统深浅色应用对应的浅色/深色主题。
 * 设置页切换「自动跟随系统」开关后也应调用一次。
 */
export async function applyAutoTheme(): Promise<void> {
  const settings = settingsService.get();
  if (!settings.autoTheme) {
    return;
  }
  const targetId = systemDarkMode ? settings.themeDarkId : settings.themeLightId;
  if (themeState.currentThemeId === targetId) {
    return;
  }
  await applyThemeById(targetId, false);
  hilog.info(DOMAIN, TAG, 'Auto theme applied: %{public}s (systemDark=%{public}s)',
    targetId, String(systemDarkMode));
}

/**
 * 获取所有可用主题
 */
export function getAllThemes(): ThemeItem[] {
  return getDefaultThemes();
}

/**
 * 获取当前主题
 */
export function getCurrentTheme(): ThemeItem | undefined {
  return themeState.currentTheme;
}

/**
 * 获取当前活跃主题颜色
 */
export function getActiveTheme(): ActiveTheme | undefined {
  return themeState.activeTheme;
}

/**
 * 获取当前主题 id
 */
export function getCurrentThemeId(): string {
  return themeState.currentThemeId;
}

/**
 * 是否深色模式
 */
export function isDarkMode(): boolean {
  return themeState.isDark;
}

/**
 * 订阅主题变化
 */
export function onThemeChange(listener: ThemeChangeListener): () => void {
  listeners.push(listener);
  return () => {
    const index = listeners.indexOf(listener);
    if (index > -1) {
      listeners.splice(index, 1);
    }
  };
}

/**
 * 通知监听器
 */
function notifyListeners(): void {
  if (themeState.activeTheme) {
    let i: number = 0;
    while (i < listeners.length) {
      const listener: ThemeChangeListener = listeners[i];
      listener(themeState.activeTheme);
      i++;
    }
  }
}

/**
 * 获取背景图名称
 */
export function getBackgroundImage(): string {
  return themeState.activeTheme?.getBgImage() || '';
}

/**
 * 获取主背景色
 */
export function getAppBackground(): string {
  return themeState.activeTheme?.getAppBackground() || '#FFFFFF';
}

/**
 * 获取内容背景色
 */
export function getContentBackground(): string {
  return themeState.activeTheme?.getContentBackground() || '#FFFFFF';
}

// 主题服务接口
export interface ThemeServiceInterface {
  initTheme: () => Promise<void>;
  applyThemeById: (themeId: string) => Promise<void>;
  getAllThemes: () => ThemeItem[];
  getCurrentTheme: () => ThemeItem | undefined;
  getActiveTheme: () => ActiveTheme | undefined;
  getCurrentThemeId: () => string;
  isDarkMode: () => boolean;
  onThemeChange: (listener: ThemeChangeListener) => () => void;
  getBackgroundImage: () => string;
  getAppBackground: () => string;
  getContentBackground: () => string;
}

const themeService: ThemeServiceInterface = {
  initTheme,
  applyThemeById,
  getAllThemes,
  getCurrentTheme,
  getActiveTheme,
  getCurrentThemeId,
  isDarkMode,
  onThemeChange,
  getBackgroundImage,
  getAppBackground,
  getContentBackground,
};

export default themeService;
