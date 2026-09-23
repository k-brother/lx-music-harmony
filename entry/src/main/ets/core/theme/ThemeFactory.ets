/**
 * 主题工厂函数
 *
 * 从 themes.ets 抽出：ArkTS 不允许对象字面量用于接口/类实例，
 * 这几行 helper 是「用函数返回值绕过字面量类型检查」的统一出口，
 * 主题数据文件（data/LightThemes、data/DarkThemes）与自定义主题都复用它。
 */
import { ThemeItem, ThemeConfig, ThemeExtInfo } from '../../types/ThemeTypes';

// 辅助函数：创建 Map 对象
export function createThemeColors(entries: string[][]): Map<string, string> {
  const map = new Map<string, string>();
  let i: number = 0;
  while (i < entries.length) {
    const entry = entries[i];
    map.set(entry[0], entry[1]);
    i++;
  }
  return map;
}

// 辅助函数：创建 ThemeExtInfo 对象
export function createExtInfo(
  appBg: string, mainBg: string, bgImg: string,
  bgPos: string, bgSize: string,
  badge1: string, badge2: string, badge3: string
): ThemeExtInfo {
  return new ThemeExtInfo(appBg, mainBg, bgImg, bgPos, bgSize, badge1, badge2, badge3);
}

// 辅助函数：创建 ThemeConfig 对象
export function createThemeConfig(themeColorsMap: Map<string, string>, extInfo: ThemeExtInfo): ThemeConfig {
  const config: ThemeConfig = { themeColors: themeColorsMap, extInfo: extInfo };
  return config;
}

// 辅助函数：创建 ThemeItem 对象
export function createTheme(id: string, name: string, isDark: boolean, isCustom: boolean, config: ThemeConfig): ThemeItem {
  const item: ThemeItem = { id: id, name: name, isDark: isDark, isCustom: isCustom, config: config };
  return item;
}
