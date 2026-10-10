/**
 * 设置首页的分类目录
 *
 * 为什么要有这一层：设置项一路加到十几张分组卡片平铺在同一页（播放、下载、搜索、列表、
 * 存储、备份、同步、外观、桌面歌词、实况窗、音源、自定义源、关于…），找一项要滚半晌，
 * 新加的功能也没地方「分门别类」。现在首页只放**分类入口**，每类点进一个二级页
 * （RouteName.SETTINGS_*），二级页复用原来的分组组件（BasicSection / PlaybackSection …），
 * 所以设置项本身没有搬迁成本，只是换了个挂载位置。
 *
 * 这里同时是分类的**单一出处**：首页的行、二级页的顶部栏标题都从这份目录取，
 * 避免两处各写一份文案而漂移。
 *
 * 注意：文案必须在函数里现算（t 依赖当前语言），不能在模块级求值；
 * 而且一律写成字面量 `t('key')`——动态拼键会被 scripts/check_i18n.py 判成
 * 「定义了没人用」，那也是它该有的严格程度。
 */
import { t } from '../../../service/LocalizationService';
import { RouteName } from '../../../service/NavigationService';

/** 首页一行分类入口 */
export interface SettingsCategoryRow {
  /** 二级页路由；枚举值本身即分类标识，二级页据此选择要渲染的分组 */
  route: RouteName;
  title: string;
  /** 行说明：一句话说清这一类里有什么，省得点进去找 */
  desc: string;
}

/** 首页一张卡片（可选的卡片标题 + 若干分类入口） */
export interface SettingsCategoryGroup {
  /** 卡片标题；空串 = 不显示标题（只有一个入口的卡片不再硬凑标题） */
  title: string;
  rows: SettingsCategoryRow[];
}

/** 首页分类目录（顺序即展示顺序） */
export function settingsHomeGroups(): SettingsCategoryGroup[] {
  const play: SettingsCategoryGroup = {
    title: t('settings_home_group_play'),
    rows: [
      {
        route: RouteName.SETTINGS_PLAYBACK,
        title: t('settings_playback'),
        desc: t('settings_group_playback_desc'),
      },
      {
        route: RouteName.SETTINGS_LYRIC,
        title: t('settings_group_lyric'),
        desc: t('settings_group_lyric_desc'),
      },
      {
        route: RouteName.SETTINGS_SOURCE,
        title: t('settings_source'),
        desc: t('settings_group_source_desc'),
      },
    ],
  };

  const ui: SettingsCategoryGroup = {
    title: t('settings_home_group_ui'),
    rows: [
      {
        route: RouteName.SETTINGS_APPEARANCE,
        title: t('settings_appearance'),
        desc: t('settings_group_appearance_desc'),
      },
      {
        route: RouteName.SETTINGS_SEARCH_LIST,
        title: t('settings_group_search_list'),
        desc: t('settings_group_search_list_desc'),
      },
      {
        route: RouteName.SETTINGS_BASIC,
        title: t('settings_basic'),
        desc: t('settings_group_basic_desc'),
      },
    ],
  };

  const data: SettingsCategoryGroup = {
    title: t('settings_home_group_data'),
    rows: [
      {
        route: RouteName.SETTINGS_STORAGE,
        title: t('settings_group_storage'),
        desc: t('settings_group_storage_desc'),
      },
      {
        route: RouteName.SETTINGS_BACKUP,
        title: t('settings_group_backup_sync'),
        desc: t('settings_group_backup_sync_desc'),
      },
    ],
  };

  // 不成类的放最后一张卡片：像 iOS「设置」底部的独立卡片，不再硬起一个「其他」标题
  const other: SettingsCategoryGroup = {
    title: '',
    rows: [
      {
        route: RouteName.SETTINGS_ABOUT,
        title: t('settings_about'),
        desc: t('settings_group_about_desc'),
      },
    ],
  };

  return [play, ui, data, other];
}

/** 分类标题（二级页顶部栏用）：从同一份目录里查，保证与首页行文案完全一致 */
export function settingsCategoryTitle(route: RouteName): string {
  const groups: SettingsCategoryGroup[] = settingsHomeGroups();
  for (let i = 0; i < groups.length; i++) {
    const rows: SettingsCategoryRow[] = groups[i].rows;
    for (let j = 0; j < rows.length; j++) {
      if (rows[j].route === route) {
        return rows[j].title;
      }
    }
  }
  return '';
}
