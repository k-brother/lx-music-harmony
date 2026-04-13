// 配置常量 - 对应 src/config/constant.ts
// 应用配置常量

export const HEADER_HEIGHT = 42;
export const LIST_ITEM_HEIGHT = 54;
export const LIST_SCROLL_POSITION_KEY = '__LIST_SCROLL_POSITION_KEY__';

// 分隔符接口
interface SplitChar {
  DISLIKE_NAME: string;
  DISLIKE_NAME_ALIAS: string;
}

export const SPLIT_CHAR: SplitChar = {
  DISLIKE_NAME: '@',
  DISLIKE_NAME_ALIAS: '#',
};

// 列表ID接口
interface ListIds {
  DEFAULT: string;
  LOVE: string;
  TEMP: string;
  DOWNLOAD: string;
  PLAY_LATER: string | null;
}

export const LIST_IDS: ListIds = {
  DEFAULT: 'default',
  LOVE: 'love',
  TEMP: 'temp',
  DOWNLOAD: 'download',
  PLAY_LATER: null,
};

// 组件ID枚举
export enum COMPONENT_IDS {
  home = 'home',
  playDetail = 'playDetail',
  songlistDetail = 'songlistDetail',
  comment = 'comment',
}

// 导航剪贴板ID枚举
export enum NAV_SHEAR_NATIVE_IDS {
  playDetail_pic = 'playDetail_pic',
  playDetail_header = 'playDetail_header',
  playDetail_player = 'playDetail_player',
  songlistDetail_pic = 'songlistDetail_pic',
  songlistDetail_title = 'songlistDetail_title',
}

// 存储数据键前缀接口
interface StorageDataPrefix {
  setting: string;
  userList: string;
  viewPrevState: string;
  list: string;
  listScrollPosition: string;
  listPrevSelectId: string;
  lyric: string;
  musicUrl: string;
  musicOtherSource: string;
  playInfo: string;
  syncAuthKey: string;
  syncHost: string;
  syncHostHistory: string;
  openStoragePath: string;
  selectedManagedFolder: string;
  notificationTipEnable: string;
  ignoringBatteryOptimizationTipEnable: string;
  searchHistoryList: string;
  listUpdateInfo: string;
  ignoreVersion: string;
  ignoreVersionFailTipTimeKey: string;
  leaderboardSetting: string;
  songListSetting: string;
  searchSetting: string;
  fontSize: string;
  theme: string;
  cheatTip: string;
  remoteLyricTip: string;
  dislikeList: string;
  userApi: string;
}

// 存储数据键前缀
export const storageDataPrefix: StorageDataPrefix = {
  setting: '@setting_v1',
  userList: '@user_list',
  viewPrevState: '@view_prev_state',
  list: '@list__',
  listScrollPosition: '@list_scroll_position',
  listPrevSelectId: '@list_prev_select_id',
  lyric: '@lyric__',
  musicUrl: '@music_url__',
  musicOtherSource: '@music_other_source__',
  playInfo: '@play_info',
  syncAuthKey: '@sync_auth_key',
  syncHost: '@sync_host',
  syncHostHistory: '@sync_host_history',
  openStoragePath: '@open_storage_path',
  selectedManagedFolder: '@selected_managed_folder',
  notificationTipEnable: '@notification_tip_enable',
  ignoringBatteryOptimizationTipEnable: '@ignoring_battery_optimization_tip_enable',
  searchHistoryList: '@search_history_list',
  listUpdateInfo: '@list_update_info',
  ignoreVersion: '@ignore_version',
  ignoreVersionFailTipTimeKey: '@ignore_version_fail_tip_time',
  leaderboardSetting: '@leaderboard_setting',
  songListSetting: '@songist_setting',
  searchSetting: '@search_setting',
  fontSize: '@font_size',
  theme: '@theme',
  cheatTip: '@cheat_tip',
  remoteLyricTip: '@remote_lyric_tip',
  dislikeList: '@dislike_list',
  userApi: '@user_api__',
};

// 旧版本存储键前缀接口
interface StorageDataPrefixOld {
  setting: string;
  list: string;
  listPosition: string;
  listSort: string;
  playInfo: string;
  syncAuthKey: string;
  syncHost: string;
  syncHostHistory: string;
  notificationTipEnable: string;
}

// 旧版本存储键前缀（用于数据迁移）
export const storageDataPrefixOld: StorageDataPrefixOld = {
  setting: '@setting',
  list: '@list__',
  listPosition: '@listposition__',
  listSort: '@listsort__',
  playInfo: '@play_info',
  syncAuthKey: '@sync_auth_key',
  syncHost: '@sync_host',
  syncHostHistory: '@sync_host_history',
  notificationTipEnable: '@notification_tip_enable',
};

// 应用Provider名称
export const APP_PROVIDER_NAME = 'cn.toside.music.mobile.provider';

// 导航菜单项接口
interface NavMenuItem {
  id: string;
  icon: string;
}

// 导航菜单
export const NAV_MENUS: NavMenuItem[] = [
  { id: 'nav_search', icon: 'search-2' },
  { id: 'nav_songlist', icon: 'album' },
  { id: 'nav_top', icon: 'leaderboard' },
  { id: 'nav_love', icon: 'love' },
  { id: 'nav_setting', icon: 'setting' },
];

export type NAV_ID_Type = 'nav_search' | 'nav_songlist' | 'nav_top' | 'nav_love' | 'nav_setting';

// 文件扩展名正则
export const LXM_FILE_EXT_RXP = ['json', 'lxmc', 'bin'];
export const USER_API_SOURCE_FILE_EXT_RXP = ['js'];

// 音乐播放模式
// 音乐播放模式接口
interface MusicToggleMode {
  listLoop: string;
  random: string;
  list: string;
  singleLoop: string;
  none: string;
}

export const MUSIC_TOGGLE_MODE: MusicToggleMode = {
  listLoop: 'listLoop', // 列表循环
  random: 'random', // 列表随机
  list: 'list', // 顺序播放
  singleLoop: 'singleLoop', // 单曲循环
  none: 'none', // 禁用
};

export const MUSIC_TOGGLE_MODE_LIST = [
  MUSIC_TOGGLE_MODE.listLoop,
  MUSIC_TOGGLE_MODE.random,
  MUSIC_TOGGLE_MODE.list,
  MUSIC_TOGGLE_MODE.singleLoop,
  MUSIC_TOGGLE_MODE.none,
];

// 排行榜设置
interface LeaderboardSetting {
  source: string;
  boardId: string;
}

// 歌单设置
interface SongListSetting {
  source: string;
  sortId: string;
  tagName: string;
  tagId: string;
}

// 搜索设置
interface SearchSetting {
  temp_source: string;
  source: string;
  type: string;
}

// 视图状态
interface ViewPrevStateSetting {
  id: string;
}

// 默认设置接口
interface DefaultSetting {
  leaderboard: LeaderboardSetting;
  songList: SongListSetting;
  search: SearchSetting;
  viewPrevState: ViewPrevStateSetting;
}

// 默认设置值
const DEFAULT_LEADERBOARD_SETTING: LeaderboardSetting = {
  source: 'kw',
  boardId: 'kw__16',
};

const DEFAULT_SONGLIST_SETTING: SongListSetting = {
  source: 'kw',
  sortId: 'new',
  tagName: '',
  tagId: '',
};

const DEFAULT_SEARCH_SETTING: SearchSetting = {
  temp_source: 'kw',
  source: 'all',
  type: 'music',
};

const DEFAULT_VIEWPREVSTATE_SETTING: ViewPrevStateSetting = {
  id: 'nav_search',
};

export const DEFAULT_SETTING: DefaultSetting = {
  leaderboard: DEFAULT_LEADERBOARD_SETTING,
  songList: DEFAULT_SONGLIST_SETTING,
  search: DEFAULT_SEARCH_SETTING,
  viewPrevState: DEFAULT_VIEWPREVSTATE_SETTING,
};