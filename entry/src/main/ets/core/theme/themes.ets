/**
 * 主题数据 - 从安卓源码迁移
 * 基于 src/theme/themes/themes.ts
 * 全部使用 helper 函数创建对象，绕过 ArkTS 对象字面量类型检查
 */

import { ThemeItem, ThemeConfig, ThemeExtInfo } from '../../types/ThemeTypes';

// 辅助函数：创建 Map 对象
function createThemeColors(entries: string[][]): Map<string, string> {
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
function createExtInfo(
  appBg: string, mainBg: string, bgImg: string,
  bgPos: string, bgSize: string,
  badge1: string, badge2: string, badge3: string
): ThemeExtInfo {
  return new ThemeExtInfo(appBg, mainBg, bgImg, bgPos, bgSize, badge1, badge2, badge3);
}

// 辅助函数：创建 ThemeConfig 对象
function createThemeConfig(themeColorsMap: Map<string, string>, extInfo: ThemeExtInfo): ThemeConfig {
  const config: ThemeConfig = { themeColors: themeColorsMap, extInfo: extInfo };
  return config;
}

// 辅助函数：创建 ThemeItem 对象
function createTheme(id: string, name: string, isDark: boolean, isCustom: boolean, config: ThemeConfig): ThemeItem {
  const item: ThemeItem = { id: id, name: name, isDark: isDark, isCustom: isCustom, config: config };
  return item;
}

// 预生成的主题配置（从安卓源码的 createThemes.js 生成）
const DEFAULT_THEMES: ThemeItem[] = [
  // === green: 绿意盎然 ===
  createTheme('green', '绿意盎然', false, false, createThemeConfig(
    createThemeColors([
      ['c-primary', 'rgb(77, 175, 124)'],
      ['c-primary-dark-100', 'rgb(69,158,112)'],
      ['c-primary-dark-200', 'rgb(62,142,101)'],
      ['c-primary-dark-300', 'rgb(56,128,91)'],
      ['c-primary-dark-400', 'rgb(50,115,82)'],
      ['c-primary-dark-500', 'rgb(45,104,74)'],
      ['c-primary-dark-600', 'rgb(41,94,67)'],
      ['c-primary-dark-700', 'rgb(37,85,60)'],
      ['c-primary-dark-800', 'rgb(33,77,54)'],
      ['c-primary-dark-900', 'rgb(30,69,49)'],
      ['c-primary-dark-1000', 'rgb(27,62,44)'],
      ['c-primary-light-100', 'rgb(109,190,149)'],
      ['c-primary-light-200', 'rgb(134,202,169)'],
      ['c-primary-light-300', 'rgb(155,211,185)'],
      ['c-primary-light-400', 'rgb(173,219,198)'],
      ['c-primary-light-500', 'rgb(188,225,209)'],
      ['c-primary-light-600', 'rgb(202,230,219)'],
      ['c-primary-light-700', 'rgb(214,235,227)'],
      ['c-primary-light-800', 'rgb(224,239,234)'],
      ['c-primary-light-900', 'rgb(233,243,240)'],
      ['c-primary-light-1000', 'rgb(255,255,255)'],
      ['c-theme', 'rgb(77, 175, 124)'],
      ['c-1000', 'rgb(33, 33, 33)'],
      ['c-950', 'rgb(44,44,44)'],
      ['c-900', 'rgb(55,55,55)'],
      ['c-850', 'rgb(66,66,66)'],
      ['c-800', 'rgb(77,77,77)'],
      ['c-750', 'rgb(89,89,89)'],
      ['c-700', 'rgb(100,100,100)'],
      ['c-650', 'rgb(111,111,111)'],
      ['c-600', 'rgb(122,122,122)'],
      ['c-550', 'rgb(133,133,133)'],
      ['c-500', 'rgb(144,144,144)'],
      ['c-450', 'rgb(155,155,155)'],
      ['c-400', 'rgb(166,166,166)'],
      ['c-350', 'rgb(177,177,177)'],
      ['c-300', 'rgb(188,188,188)'],
      ['c-250', 'rgb(200,200,200)'],
      ['c-200', 'rgb(211,211,211)'],
      ['c-150', 'rgb(222,222,222)'],
      ['c-100', 'rgb(233,233,233)'],
      ['c-050', 'rgb(244,244,244)'],
      ['c-000', 'rgb(255,255,255)'],
    ]),
    createExtInfo(
      'var(c-primary-light-600-alpha-700)', 'rgba(255, 255, 255, 1)', '',
      'center', 'cover',
      'var(c-primary)', '#4baed5', '#e7aa36'
    )
  )),
  // === black: 黑灯瞎火 ===
  createTheme('black', '黑灯瞎火', true, false, createThemeConfig(
    createThemeColors([
      ['c-primary', 'rgb(190, 190, 190)'],
      ['c-primary-dark-100', 'rgb(171,171,171)'],
      ['c-primary-dark-200', 'rgb(154,154,154)'],
      ['c-primary-dark-300', 'rgb(139,139,139)'],
      ['c-primary-dark-400', 'rgb(125,125,125)'],
      ['c-primary-dark-500', 'rgb(113,113,113)'],
      ['c-primary-dark-600', 'rgb(102,102,102)'],
      ['c-primary-dark-700', 'rgb(92,92,92)'],
      ['c-primary-dark-800', 'rgb(83,83,83)'],
      ['c-primary-dark-900', 'rgb(75,75,75)'],
      ['c-primary-dark-1000', 'rgb(68,68,68)'],
      ['c-primary-light-100', 'rgb(195,195,195)'],
      ['c-primary-light-200', 'rgb(199,199,199)'],
      ['c-primary-light-300', 'rgb(203,203,203)'],
      ['c-primary-light-400', 'rgb(207,207,207)'],
      ['c-primary-light-500', 'rgb(210,210,210)'],
      ['c-primary-light-600', 'rgb(213,213,213)'],
      ['c-primary-light-700', 'rgb(216,216,216)'],
      ['c-primary-light-800', 'rgb(218,218,218)'],
      ['c-primary-light-900', 'rgb(220,220,220)'],
      ['c-primary-light-1000', 'rgb(255,255,255)'],
      ['c-theme', 'rgb(190, 190, 190)'],
      ['c-1000', 'rgb(229, 229, 229)'],
      ['c-950', 'rgb(218,218,218)'],
      ['c-900', 'rgb(207,207,207)'],
      ['c-850', 'rgb(196,196,196)'],
      ['c-800', 'rgb(185,185,185)'],
      ['c-750', 'rgb(174,174,174)'],
      ['c-700', 'rgb(163,163,163)'],
      ['c-650', 'rgb(152,152,152)'],
      ['c-600', 'rgb(141,141,141)'],
      ['c-550', 'rgb(130,130,130)'],
      ['c-500', 'rgb(119,119,119)'],
      ['c-450', 'rgb(108,108,108)'],
      ['c-400', 'rgb(97,97,97)'],
      ['c-350', 'rgb(86,86,86)'],
      ['c-300', 'rgb(75,75,75)'],
      ['c-250', 'rgb(64,64,64)'],
      ['c-200', 'rgb(53,53,53)'],
      ['c-150', 'rgb(42,42,42)'],
      ['c-100', 'rgb(31,31,31)'],
      ['c-050', 'rgb(20,20,20)'],
      ['c-000', 'rgb(0,0,0)'],
    ]),
    createExtInfo(
      'rgba(0, 0, 0, 0)', 'rgba(19, 19, 19, 0.95)', 'landingMoon2.png',
      'center', 'cover',
      'var(c-primary-dark-200)', 'var(c-primary)', 'var(c-primary-dark-300)'
    )
  )),
  // === blue: 蓝田生玉 ===
  createTheme('blue', '蓝田生玉', false, false, createThemeConfig(
    createThemeColors([
      ['c-primary', 'rgb(52, 152, 219)'],
      ['c-primary-dark-100', 'rgb(47,137,197)'],
      ['c-primary-dark-200', 'rgb(42,123,177)'],
      ['c-primary-dark-300', 'rgb(38,111,159)'],
      ['c-primary-dark-400', 'rgb(34,100,143)'],
      ['c-primary-dark-500', 'rgb(31,90,129)'],
      ['c-primary-dark-600', 'rgb(28,81,116)'],
      ['c-primary-dark-700', 'rgb(25,73,104)'],
      ['c-primary-dark-800', 'rgb(23,66,94)'],
      ['c-primary-dark-900', 'rgb(21,59,85)'],
      ['c-primary-dark-1000', 'rgb(19,53,77)'],
      ['c-primary-light-100', 'rgb(83,167,224)'],
      ['c-primary-light-200', 'rgb(108,179,228)'],
      ['c-primary-light-300', 'rgb(129,189,232)'],
      ['c-primary-light-400', 'rgb(148,197,235)'],
      ['c-primary-light-500', 'rgb(164,204,238)'],
      ['c-primary-light-600', 'rgb(178,210,240)'],
      ['c-primary-light-700', 'rgb(191,216,242)'],
      ['c-primary-light-800', 'rgb(202,221,244)'],
      ['c-primary-light-900', 'rgb(212,226,246)'],
      ['c-primary-light-1000', 'rgb(255,255,255)'],
      ['c-theme', 'rgb(52, 152, 219)'],
      ['c-1000', 'rgb(33, 33, 33)'],
      ['c-950', 'rgb(44,44,44)'],
      ['c-900', 'rgb(55,55,55)'],
      ['c-850', 'rgb(66,66,66)'],
      ['c-800', 'rgb(77,77,77)'],
      ['c-750', 'rgb(89,89,89)'],
      ['c-700', 'rgb(100,100,100)'],
      ['c-650', 'rgb(111,111,111)'],
      ['c-600', 'rgb(122,122,122)'],
      ['c-550', 'rgb(133,133,133)'],
      ['c-500', 'rgb(144,144,144)'],
      ['c-450', 'rgb(155,155,155)'],
      ['c-400', 'rgb(166,166,166)'],
      ['c-350', 'rgb(177,177,177)'],
      ['c-300', 'rgb(188,188,188)'],
      ['c-250', 'rgb(200,200,200)'],
      ['c-200', 'rgb(211,211,211)'],
      ['c-150', 'rgb(222,222,222)'],
      ['c-100', 'rgb(233,233,233)'],
      ['c-050', 'rgb(244,244,244)'],
      ['c-000', 'rgb(255,255,255)'],
    ]),
    createExtInfo(
      'var(c-primary-light-600-alpha-700)', 'rgba(255, 255, 255, 1)', '',
      'center', 'cover',
      'var(c-primary)', '#5cbf9b', '#5cbf9b'
    )
  )),
  // === china_ink: 近墨者黑 ===
  createTheme('china_ink', '近墨者黑', false, false, createThemeConfig(
    createThemeColors([
      ['c-primary', 'rgba(47, 47, 47, 1)'],
      ['c-primary-dark-100', 'rgba(42,42,42,1)'],
      ['c-primary-dark-200', 'rgba(38,38,38,1)'],
      ['c-primary-dark-300', 'rgba(34,34,34,1)'],
      ['c-primary-dark-400', 'rgba(31,31,31,1)'],
      ['c-primary-dark-500', 'rgba(28,28,28,1)'],
      ['c-primary-dark-600', 'rgba(25,25,25,1)'],
      ['c-primary-dark-700', 'rgba(23,23,23,1)'],
      ['c-primary-dark-800', 'rgba(21,21,21,1)'],
      ['c-primary-dark-900', 'rgba(19,19,19,1)'],
      ['c-primary-dark-1000', 'rgba(17,17,17,1)'],
      ['c-primary-light-100', 'rgba(93,93,93,1)'],
      ['c-primary-light-200', 'rgba(129,129,129,1)'],
      ['c-primary-light-300', 'rgba(158,158,158,1)'],
      ['c-primary-light-400', 'rgba(181,181,181,1)'],
      ['c-primary-light-500', 'rgba(199,199,199,1)'],
      ['c-primary-light-600', 'rgba(213,213,213,1)'],
      ['c-primary-light-700', 'rgba(224,224,224,1)'],
      ['c-primary-light-800', 'rgba(233,233,233,1)'],
      ['c-primary-light-900', 'rgba(239,239,239,1)'],
      ['c-primary-light-1000', 'rgb(255,255,255)'],
      ['c-theme', 'rgba(47, 47, 47, 1)'],
      ['c-1000', 'rgb(33, 33, 33)'],
      ['c-950', 'rgb(44,44,44)'],
      ['c-900', 'rgb(55,55,55)'],
      ['c-850', 'rgb(66,66,66)'],
      ['c-800', 'rgb(77,77,77)'],
      ['c-750', 'rgb(89,89,89)'],
      ['c-700', 'rgb(100,100,100)'],
      ['c-650', 'rgb(111,111,111)'],
      ['c-600', 'rgb(122,122,122)'],
      ['c-550', 'rgb(133,133,133)'],
      ['c-500', 'rgb(144,144,144)'],
      ['c-450', 'rgb(155,155,155)'],
      ['c-400', 'rgb(166,166,166)'],
      ['c-350', 'rgb(177,177,177)'],
      ['c-300', 'rgb(188,188,188)'],
      ['c-250', 'rgb(200,200,200)'],
      ['c-200', 'rgb(211,211,211)'],
      ['c-150', 'rgb(222,222,222)'],
      ['c-100', 'rgb(233,233,233)'],
      ['c-050', 'rgb(244,244,244)'],
      ['c-000', 'rgb(255,255,255)'],
    ]),
    createExtInfo(
      'rgba(255, 255, 255, 0)', 'rgba(255, 255, 255, 0.8)', 'china_ink.jpg',
      'center', 'cover',
      'rgba(137, 70, 70, 1)', 'rgba(67, 139, 65, 1)', 'rgba(132, 135, 65, 1)'
    )
  )),
  // === mid_autumn: 月里嫦娥 ===
  createTheme('mid_autumn', '月里嫦娥', false, false, createThemeConfig(
    createThemeColors([
      ['c-primary', 'rgb(74, 55, 82)'],
      ['c-primary-dark-100', 'rgb(67,50,74)'],
      ['c-primary-dark-200', 'rgb(60,45,67)'],
      ['c-primary-dark-300', 'rgb(54,41,60)'],
      ['c-primary-dark-400', 'rgb(49,37,54)'],
      ['c-primary-dark-500', 'rgb(44,33,49)'],
      ['c-primary-dark-600', 'rgb(40,30,44)'],
      ['c-primary-dark-700', 'rgb(36,27,40)'],
      ['c-primary-dark-800', 'rgb(32,24,36)'],
      ['c-primary-dark-900', 'rgb(29,22,32)'],
      ['c-primary-dark-1000', 'rgb(26,20,29)'],
      ['c-primary-light-100', 'rgb(108,88,113)'],
      ['c-primary-light-200', 'rgb(136,115,139)'],
      ['c-primary-light-300', 'rgb(159,137,159)'],
      ['c-primary-light-400', 'rgb(178,156,175)'],
      ['c-primary-light-500', 'rgb(193,171,188)'],
      ['c-primary-light-600', 'rgb(206,184,199)'],
      ['c-primary-light-700', 'rgb(216,195,208)'],
      ['c-primary-light-800', 'rgb(224,204,215)'],
      ['c-primary-light-900', 'rgb(231,212,221)'],
      ['c-primary-light-1000', 'rgb(255,255,255)'],
      ['c-theme', 'rgb(74, 55, 82)'],
      ['c-1000', 'rgb(33, 33, 33)'],
      ['c-950', 'rgb(44,44,44)'],
      ['c-900', 'rgb(55,55,55)'],
      ['c-850', 'rgb(66,66,66)'],
      ['c-800', 'rgb(77,77,77)'],
      ['c-750', 'rgb(89,89,89)'],
      ['c-700', 'rgb(100,100,100)'],
      ['c-650', 'rgb(111,111,111)'],
      ['c-600', 'rgb(122,122,122)'],
      ['c-550', 'rgb(133,133,133)'],
      ['c-500', 'rgb(144,144,144)'],
      ['c-450', 'rgb(155,155,155)'],
      ['c-400', 'rgb(166,166,166)'],
      ['c-350', 'rgb(177,177,177)'],
      ['c-300', 'rgb(188,188,188)'],
      ['c-250', 'rgb(200,200,200)'],
      ['c-200', 'rgb(211,211,211)'],
      ['c-150', 'rgb(222,222,222)'],
      ['c-100', 'rgb(233,233,233)'],
      ['c-050', 'rgb(244,244,244)'],
      ['c-000', 'rgb(255,255,255)'],
    ]),
    createExtInfo(
      'var(c-primary-light-600-alpha-700)', 'rgba(255, 255, 255, 1)', '',
      'center', 'cover',
      'var(c-primary)', '#d4a373', '#d4a373'
    )
  )),
  // === naruto: 火影忍者 ===
  createTheme('naruto', '火影忍者', false, false, createThemeConfig(
    createThemeColors([
      ['c-primary', 'rgb(226, 57, 70)'],
      ['c-primary-dark-100', 'rgb(203,51,63)'],
      ['c-primary-dark-200', 'rgb(183,46,57)'],
      ['c-primary-dark-300', 'rgb(165,41,51)'],
      ['c-primary-dark-400', 'rgb(149,37,46)'],
      ['c-primary-dark-500', 'rgb(134,33,41)'],
      ['c-primary-dark-600', 'rgb(121,30,37)'],
      ['c-primary-dark-700', 'rgb(109,27,33)'],
      ['c-primary-dark-800', 'rgb(98,24,30)'],
      ['c-primary-dark-900', 'rgb(88,22,27)'],
      ['c-primary-dark-1000', 'rgb(79,20,24)'],
      ['c-primary-light-100', 'rgb(231,91,102)'],
      ['c-primary-light-200', 'rgb(235,118,127)'],
      ['c-primary-light-300', 'rgb(238,140,148)'],
      ['c-primary-light-400', 'rgb(241,158,164)'],
      ['c-primary-light-500', 'rgb(243,173,178)'],
      ['c-primary-light-600', 'rgb(244,186,190)'],
      ['c-primary-light-700', 'rgb(245,197,200)'],
      ['c-primary-light-800', 'rgb(247,207,209)'],
      ['c-primary-light-900', 'rgb(248,215,217)'],
      ['c-primary-light-1000', 'rgb(255,255,255)'],
      ['c-theme', 'rgb(226, 57, 70)'],
      ['c-1000', 'rgb(33, 33, 33)'],
      ['c-950', 'rgb(44,44,44)'],
      ['c-900', 'rgb(55,55,55)'],
      ['c-850', 'rgb(66,66,66)'],
      ['c-800', 'rgb(77,77,77)'],
      ['c-750', 'rgb(89,89,89)'],
      ['c-700', 'rgb(100,100,100)'],
      ['c-650', 'rgb(111,111,111)'],
      ['c-600', 'rgb(122,122,122)'],
      ['c-550', 'rgb(133,133,133)'],
      ['c-500', 'rgb(144,144,144)'],
      ['c-450', 'rgb(155,155,155)'],
      ['c-400', 'rgb(166,166,166)'],
      ['c-350', 'rgb(177,177,177)'],
      ['c-300', 'rgb(188,188,188)'],
      ['c-250', 'rgb(200,200,200)'],
      ['c-200', 'rgb(211,211,211)'],
      ['c-150', 'rgb(222,222,222)'],
      ['c-100', 'rgb(233,233,233)'],
      ['c-050', 'rgb(244,244,244)'],
      ['c-000', 'rgb(255,255,255)'],
    ]),
    createExtInfo(
      'var(c-primary-light-600-alpha-700)', 'rgba(255, 255, 255, 1)', 'jqbg.jpg',
      'center', 'cover',
      'var(c-primary)', '#f4a261', '#f4a261'
    )
  )),
  // === happy_new_year: 新年快乐 ===
  createTheme('happy_new_year', '新年快乐', false, false, createThemeConfig(
    createThemeColors([
      ['c-primary', 'rgb(200, 76, 62)'],
      ['c-primary-dark-100', 'rgb(180,68,56)'],
      ['c-primary-dark-200', 'rgb(162,61,50)'],
      ['c-primary-dark-300', 'rgb(146,55,45)'],
      ['c-primary-dark-400', 'rgb(131,50,41)'],
      ['c-primary-dark-500', 'rgb(118,45,37)'],
      ['c-primary-dark-600', 'rgb(106,41,33)'],
      ['c-primary-dark-700', 'rgb(95,37,30)'],
      ['c-primary-dark-800', 'rgb(86,33,27)'],
      ['c-primary-dark-900', 'rgb(77,30,24)'],
      ['c-primary-dark-1000', 'rgb(69,27,22)'],
      ['c-primary-light-100', 'rgb(211,106,94)'],
      ['c-primary-light-200', 'rgb(220,129,119)'],
      ['c-primary-light-300', 'rgb(227,148,140)'],
      ['c-primary-light-400', 'rgb(232,163,156)'],
      ['c-primary-light-500', 'rgb(236,176,169)'],
      ['c-primary-light-600', 'rgb(240,187,180)'],
      ['c-primary-light-700', 'rgb(243,197,190)'],
      ['c-primary-light-800', 'rgb(245,205,199)'],
      ['c-primary-light-900', 'rgb(247,212,207)'],
      ['c-primary-light-1000', 'rgb(255,255,255)'],
      ['c-theme', 'rgb(200, 76, 62)'],
      ['c-1000', 'rgb(33, 33, 33)'],
      ['c-950', 'rgb(44,44,44)'],
      ['c-900', 'rgb(55,55,55)'],
      ['c-850', 'rgb(66,66,66)'],
      ['c-800', 'rgb(77,77,77)'],
      ['c-750', 'rgb(89,89,89)'],
      ['c-700', 'rgb(100,100,100)'],
      ['c-650', 'rgb(111,111,111)'],
      ['c-600', 'rgb(122,122,122)'],
      ['c-550', 'rgb(133,133,133)'],
      ['c-500', 'rgb(144,144,144)'],
      ['c-450', 'rgb(155,155,155)'],
      ['c-400', 'rgb(166,166,166)'],
      ['c-350', 'rgb(177,177,177)'],
      ['c-300', 'rgb(188,188,188)'],
      ['c-250', 'rgb(200,200,200)'],
      ['c-200', 'rgb(211,211,211)'],
      ['c-150', 'rgb(222,222,222)'],
      ['c-100', 'rgb(233,233,233)'],
      ['c-050', 'rgb(244,244,244)'],
      ['c-000', 'rgb(255,255,255)'],
    ]),
    createExtInfo(
      'rgba(255, 255, 255, 0.15)', 'rgba(255, 255, 255, 0.8)', 'xnkl.png',
      'center', 'cover',
      '#7fb575', '#dfbb6b', 'var(c-primary-light-100)'
    )
  )),
];

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
