/**
 * 主题数据门面
 *
 * 2622 行 → 门面 + 三个文件：
 * - `ThemeFactory`  主题工厂函数（绕过 ArkTS 对象字面量限制）
 * - `data/LightThemes` / `data/DarkThemes`  明暗两套主题数据
 * 门面只保留查询 API，调用方（主题服务、设置页）import 路径不变。
 */
import type { ThemeItem } from '../../types/ThemeTypes';
import { LIGHT_THEMES } from './data/LightThemes';
import { DARK_THEMES } from './data/DarkThemes';

/** 全部内置主题（浅色在前，深色在后） */
const DEFAULT_THEMES: ThemeItem[] = LIGHT_THEMES.concat(DARK_THEMES);

// 获取所有默认主题
export function getDefaultThemes(): ThemeItem[] {
  return DEFAULT_THEMES;
}

// 根据id获取主题
export function getThemeById(id: string): ThemeItem | undefined {
  let i: number = 0;
  while (i < DEFAULT_THEMES.length) {
    const theme = DEFAULT_THEMES[i];
    if (theme.id === id) {
      return theme;
    }
    i++;
  }
  return undefined;
}

// 默认主题id
export const DEFAULT_THEME_ID = 'green';
