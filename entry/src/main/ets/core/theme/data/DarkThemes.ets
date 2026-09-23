/**
 * 深色主题
 *
 * 深色主题（跟随系统深色模式时使用）。
 * 数据来自安卓版 `createThemes.js`（原样迁移，只做了排版归类）。
 * 新增主题：往对应数组里追加一条 `createTheme(...)`，id 不要与已有重复。
 */
import { ThemeItem } from '../../../types/ThemeTypes';
import { createTheme, createThemeConfig, createThemeColors, createExtInfo } from '../ThemeFactory';

export const DARK_THEMES: ThemeItem[] = [
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
];
