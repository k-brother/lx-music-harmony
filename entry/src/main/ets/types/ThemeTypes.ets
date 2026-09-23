/**
 * 主题类型定义 - 基于安卓源码主题系统
 * 注意：ArkTS 不支持索引签名和未类型对象字面量，使用 Map 存储主题颜色
 */

// 扩展信息 - 使用 class 避免 indexed access 问题
export class ThemeExtInfo {
  cAppBackground: string;
  cMainBackground: string;
  bgImage: string;
  bgImagePosition: string;
  bgImageSize: string;
  cBadgePrimary: string;
  cBadgeSecondary: string;
  cBadgeTertiary: string;

  constructor(
    cAppBackground: string, cMainBackground: string, bgImage: string,
    bgImagePosition: string, bgImageSize: string,
    cBadgePrimary: string, cBadgeSecondary: string, cBadgeTertiary: string
  ) {
    this.cAppBackground = cAppBackground;
    this.cMainBackground = cMainBackground;
    this.bgImage = bgImage;
    this.bgImagePosition = bgImagePosition;
    this.bgImageSize = bgImageSize;
    this.cBadgePrimary = cBadgePrimary;
    this.cBadgeSecondary = cBadgeSecondary;
    this.cBadgeTertiary = cBadgeTertiary;
  }

}

// 主题配置 - themeColors 用 Map 存储
export interface ThemeConfig {
  themeColors: Map<string, string>;
  extInfo: ThemeExtInfo;
}

// 主题项
export interface ThemeItem {
  id: string;
  name: string;
  isDark: boolean;
  isCustom: boolean;
  config: ThemeConfig;
}

// 活跃主题 - 使用 Map 存储所有运行时颜色（含动态生成的 alpha 变体）
export class ActiveTheme {
  id: string;
  name: string;
  isDark: boolean;
  colors: Map<string, string>;

  constructor(id: string, name: string, isDark: boolean) {
    this.id = id;
    this.name = name;
    this.isDark = isDark;
    this.colors = new Map();
  }

  get(key: string): string {
    return this.colors.get(key) || '';
  }

  set(key: string, value: string): void {
    this.colors.set(key, value);
  }

  has(key: string): boolean {
    return this.colors.has(key);
  }

  getContentBackground(): string {
    return this.colors.get('c-main-background') || '#FFFFFF';
  }

  getAppBackground(): string {
    return this.colors.get('c-app-background') || '#FFFFFF';
  }

  getBgImage(): string {
    return this.colors.get('bg-image') || '';
  }
}
