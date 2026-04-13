/**
 * 主题常量 - 统一的颜色、字体、间距等UI常量
 * 用于替换页面中的硬编码值
 */

// 主色调
export const PRIMARY_COLOR = '#E63946';
export const PRIMARY_COLOR_ALPHA_10 = 'rgba(230, 57, 70, 0.1)';

// 文字颜色
export const TEXT_PRIMARY_LIGHT = '#333333';
export const TEXT_PRIMARY_DARK = '#FFFFFF';
export const TEXT_SECONDARY = '#999999';
export const TEXT_PLACEHOLDER = '#999999';

// 背景颜色
export const BG_PRIMARY_LIGHT = '#FFFFFF';
export const BG_PRIMARY_DARK = '#1C1C1C';
export const BG_SECONDARY_LIGHT = '#F5F5F5';
export const BG_SECONDARY_DARK = '#121212';
export const BG_TERTIARY_LIGHT = '#F0F0F0';
export const BG_TERTIARY_DARK = '#2C2C2C';

// 边框颜色
export const BORDER_COLOR_LIGHT = '#E0E0E0';
export const BORDER_COLOR_DARK = '#333333';

// 热搜排名颜色
export const HOT_SEARCH_TOP_COLOR = '#E63946';
export const HOT_SEARCH_OTHER_COLOR = '#999999';

// 播放器颜色
export const PLAYER_BG_LIGHT = '#FFFFFF';
export const PLAYER_BG_DARK = '#1C1C1C';

// 进度条颜色
export const SLIDER_BLOCK_COLOR = '#E63946';
export const SLIDER_TRACK_COLOR = '#E0E0E0';
export const SLIDER_SELECTED_COLOR = '#E63946';

// Tab指示器
export const TAB_INDICATOR_ACTIVE = '#E63946';
export const TAB_INDICATOR_INACTIVE = '#E0E0E0';

// 音乐源选项卡
export const SOURCE_TAB_ACTIVE_COLOR = '#E63946';
export const SOURCE_TAB_INACTIVE_LIGHT = '#666666';
export const SOURCE_TAB_INACTIVE_DARK = '#CCCCCC';

// 底部TabBar
export const TAB_BAR_ACTIVE_COLOR = '#E63946';
export const TAB_BAR_INACTIVE_LIGHT = '#999999';
export const TAB_BAR_INACTIVE_DARK = '#AAAAAA';

// 字体大小
export const FONT_SIZE_TITLE = 20;
export const FONT_SIZE_SUBTITLE = 16;
export const FONT_SIZE_BODY = 14;
export const FONT_SIZE_CAPTION = 12;
export const FONT_SIZE_SMALL = 10;

// 间距
export const PADDING_SMALL = 8;
export const PADDING_MEDIUM = 12;
export const PADDING_LARGE = 16;
export const PADDING_XLARGE = 20;

// 圆角
export const BORDER_RADIUS_SMALL = 4;
export const BORDER_RADIUS_MEDIUM = 8;
export const BORDER_RADIUS_LARGE = 12;
export const BORDER_RADIUS_ROUND = 16;
export const BORDER_RADIUS_CIRCLE = 20;

// 图标大小
export const ICON_SIZE_SMALL = 16;
export const ICON_SIZE_MEDIUM = 20;
export const ICON_SIZE_LARGE = 24;
export const ICON_SIZE_XLARGE = 32;

// 播放器栏高度
export const PLAYER_BAR_HEIGHT = 56;
export const TAB_BAR_HEIGHT = 50;
export const TOP_BAR_HEIGHT = 48;

// 封面图片尺寸
export const ALBUM_ART_SIZE_SMALL = 46;
export const ALBUM_ART_SIZE_MEDIUM = 120;
export const ALBUM_ART_SIZE_LARGE = 200;

/**
 * 根据主题获取对应的颜色值
 */
export function getTextColor(isDark: boolean): string {
  return isDark ? TEXT_PRIMARY_DARK : TEXT_PRIMARY_LIGHT;
}

export function getSecondaryTextColor(): string {
  return TEXT_SECONDARY;
}

export function getBgColor(isDark: boolean): string {
  return isDark ? BG_SECONDARY_DARK : BG_SECONDARY_LIGHT;
}

export function getPrimaryBgColor(isDark: boolean): string {
  return isDark ? BG_PRIMARY_DARK : BG_PRIMARY_LIGHT;
}

export function getBorderColor(isDark: boolean): string {
  return isDark ? BORDER_COLOR_DARK : BORDER_COLOR_LIGHT;
}
