// 本地化服务 - 多语言支持
// 通过 AppStorage 驱动全局语言切换

import { hilog } from '@kit.PerformanceAnalysisKit';
import { i18n } from '@kit.LocalizationKit';
import { settingsService } from './SettingsService';
import type { PlayCountUnits } from '../utils/FormatTools';

import { buildZhCN } from './localization/ZhCN';
import { buildEnUS } from './localization/EnUS';

const TAG = 'Localization';
const DOMAIN = 0x0001;

const zhCNMap: Map<string, string> = buildZhCN();
const enUSMap: Map<string, string> = buildEnUS();

// 模块级当前语言缓存（避免 AppStorage 读取延迟问题）
let currentLang: string = 'zh-CN';

// 获取当前语言
function getCurrentLang(): string {
  const stored = AppStorage.get<string>('language');
  if (stored !== undefined && stored !== null && stored.length > 0) {
    currentLang = stored;
    return stored;
  }
  return currentLang;
}

// 设置语言（更新模块变量 + AppStorage）
export function setLanguage(lang: string): void {
  currentLang = lang;
  AppStorage.setOrCreate('language', lang);
  // 通过 langVersion 强制所有 @StorageProp('langVersion') 组件重渲染
  AppStorage.setOrCreate('langVersion', Date.now());
  applyAppPreferredLanguage(lang);
  hilog.info(DOMAIN, TAG, 'Language set to: %{public}s, version=%{public}d', lang, Date.now());
}

/**
 * 把应用内语言同步给系统资源框架。
 *
 * 应用内的文案走自己的词条表，但「应用名、权限申请理由、系统弹窗」这些由系统渲染的
 * 字符串走资源限定词目录（resources/en_US/...）。不同步的话，用户在应用里切成英文，
 * 系统弹窗仍然是中文。该设置按官方说明在应用冷启动后生效，所以启动时也要调一次。
 */
function applyAppPreferredLanguage(lang: string): void {
  try {
    i18n.System.setAppPreferredLanguage(lang);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'setAppPreferredLanguage failed: %{public}s',
      (err as Error)?.message ?? '');
  }
}

// 获取翻译文本
export function t(key: string): string {
  // 优先从 AppStorage 读，fallback 到模块变量
  const stored = AppStorage.get<string>('language');
  const lang = (stored !== undefined && stored !== null && stored.length > 0) ? stored : currentLang;
  let map: Map<string, string>;
  if (lang === 'en-US') {
    map = enUSMap;
  } else {
    map = zhCNMap;
  }
  const val = map.get(key);
  if (val !== undefined) {
    return val;
  }
  const fallback = zhCNMap.get(key);
  if (fallback !== undefined) {
    return fallback;
  }
  return key;
}


/**
 * 带占位符的翻译：文案里用 {0} {1} 表示参数。
 * 例：tf('toast_added_to_list', [name]) 对应文案 '已添加到「{0}」'
 */
export function tf(key: string, args: string[]): string {
  let text: string = t(key);
  for (let i = 0; i < args.length; i++) {
    const placeholder: string = `{${i}}`;
    // 用 split/join 代替 replaceAll，兼容 ArkTS 的字符串实现
    text = text.split(placeholder).join(args[i]);
  }
  return text;
}

/**
 * 音乐源展示名（各源文案在 i18n 中，这里做显式映射，便于静态检查与复用）
 */
/**
 * 播放量单位：中文用万/亿，其它语言用 K/M（量级一起换，不能只换文案）。
 * 放在本地化服务里是因为「用哪个量级」本身就是语言相关的规则。
 */
export function playCountUnits(): PlayCountUnits {
  const lang = AppStorage.get<string>('language') ?? 'zh-CN';
  if (lang.startsWith('zh')) {
    return {
      smallBase: 10000,
      smallLabel: t('ten_thousand_unit'),
      largeBase: 100000000,
      largeLabel: t('billion_unit'),
    };
  }
  return {
    smallBase: 1000,
    smallLabel: t('ten_thousand_unit'),
    largeBase: 1000000,
    largeLabel: t('billion_unit'),
  };
}

export function sourceLabel(source: string): string {
  switch (source) {
    case 'kw':
      return sourceName('kw');
    case 'kg':
      return sourceName('kg');
    case 'tx':
      return sourceName('tx');
    case 'wy':
      return sourceName('wy');
    case 'mg':
      return sourceName('mg');
    case 'all':
      return sourceName('all');
    case 'local':
      return t('local_music');
    default:
      return source;
  }
}

/**
 * 音源名称：按「设置 → 源名显示」返回别名或原名
 * （别名与安卓版一致：小蜗音乐 / 小枸音乐 / 小蜜音乐 / 小秋音乐 / 小芸音乐）
 */
export function sourceName(source: string): string {
  const type = getSourceNameType();
  const prefix = type === 'real' ? 'source_real_' : 'source_alias_';
  const key = `${prefix}${source}`;
  const label = t(key);
  // 未登记的键 t() 会原样返回 key，此时回退到原名
  if (label === key) {
    return sourceRealName(source);
  }
  return label;
}

function sourceRealName(source: string): string {
  switch (source) {
    case 'kw':
      return t('source_kw');
    case 'kg':
      return t('source_kg');
    case 'tx':
      return t('source_tx');
    case 'wy':
      return t('source_wy');
    case 'mg':
      return t('source_mg');
    default:
      return source;
  }
}

/** 读取源名显示设置（设置未就绪时按别名，与默认值一致） */
function getSourceNameType(): string {
  try {
    return AppStorage.get<string>('sourceNameType') ?? 'alias';
  } catch (err) {
    return 'alias';
  }
}

/**
 * 初始化语言设置（读取已经加载好的设置快照，不再自行访问 Preferences）
 */
export function initLocalization(): void {
  const saved = settingsService.get().language;
  const lang = (saved === 'en-US' || saved === 'zh-CN') ? saved : 'zh-CN';
  currentLang = lang;
  AppStorage.setOrCreate('language', lang);
  AppStorage.setOrCreate('langVersion', Date.now());
  applyAppPreferredLanguage(lang);
  hilog.info(DOMAIN, TAG, 'initLocalization: applied %{public}s', lang);
}
