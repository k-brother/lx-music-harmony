// Theme Store - 对应 src/store/theme/state.ts
// 主题状态管理

// 主题类型
export type ThemeType = 'light' | 'dark' | 'system';

// 配色方案
export interface ThemeColors {
  primary: string;
  background: string;
  backgroundSecondary: string;
  text: string;
  textSecondary: string;
  border: string;
  accent: string;
}

// 主题配置
export interface ThemeConfig {
  light: ThemeColors;
  dark: ThemeColors;
}

// 主题状态
export class ThemeState {
  activeTheme: ThemeType = 'system';
  
  // 浅色主题配色
  lightColors: ThemeColors = {
    primary: '#E63946',
    background: '#FFFFFF',
    backgroundSecondary: '#F5F5F5',
    text: '#333333',
    textSecondary: '#666666',
    border: '#E0E0E0',
    accent: '#E63946',
  };

  // 深色主题配色
  darkColors: ThemeColors = {
    primary: '#E63946',
    background: '#121212',
    backgroundSecondary: '#1C1C1C',
    text: '#FFFFFF',
    textSecondary: '#999999',
    border: '#2C2C2C',
    accent: '#E63946',
  };

  // 当前使用的配色
  getColors(isDark: boolean): ThemeColors {
    return isDark ? this.darkColors : this.lightColors;
  }

  // 背景图片
  bgPic: string | null = null;
}

// 导出单例
export const themeState = new ThemeState();
