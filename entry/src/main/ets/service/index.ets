/**
 * 服务模块导出
 * 统一导出所有核心服务
 */

// 仅导入 initAllServices / initImageCache 内部真正使用的成员；
// 对外导出统一由下面的 export 语句声明，避免"导入一堆再导出"的重复。
import { initStorage } from './StorageService';
import { initTheme } from './ThemeService';
import { initListService } from './ListService';
import { migrateLegacyCollections } from './UserListSyncService';
import { playerService } from './PlayerService';
import { initDownloadService } from '../core/music/MusicFeatureEntry';
import { imageCacheService } from '../utils/ImageCache';
import { initSettings } from './SettingsService';
import { sleepTimerService } from './SleepTimerService';
import type { common } from '@kit.AbilityKit';

// HTTP服务（统一从 core/network/http 导出）
export { httpRequest, httpGet, httpPost } from '../core/network/http';

// 播放器服务
export { default as PlayerService, playerService as playerServiceInstance, PlayStatus, SongInfo, MusicInfo, ProgressInfo } from './PlayerService';

// 导航服务
export { navigationService, RouteName, NavigationService } from './NavigationService';

// 存储服务
export { default as StorageService, initStorage, getString, getNumber, getBoolean, setString, setNumber, setBoolean, remove, clear, has, StorageKeys } from './StorageService';

// 设置服务（全应用唯一设置入口）
export { settingsService, initSettings } from './SettingsService';
export type {
  AppSettings,
  SettingsPatch,
  PlayMode,
  ThemeMode,
  StartupPage,
  AddMusicLocation,
  DesktopLyricPosition,
} from './SettingsService';

// 主题服务
export { default as ThemeService, initTheme, getCurrentThemeId, getActiveTheme, getAllThemes, applyThemeById, isDarkMode, getBackgroundImage, getAppBackground, getContentBackground, onThemeChange } from './ThemeService';

// 列表服务
export { default as ListService, LIST_IDS, initListService, getDefaultList, getLoveList, getUserList, getUserListMusic, addMusicToList, removeMusicFromList, createUserList, deleteUserList, setPlayList, getPlayList, setPlayIndex, getCurrentMusic, playNext, playPrev, isInLoveList, toggleLoveList, onListChange, MusicItem, ListInfo } from './ListService';

// 事件总线：只对外暴露真正在用的订阅入口与三个事件
export { EventTypes, on, emitListUpdated, emitSearchRequest, emitSettingChanged } from './EventBus';

/**
 * 初始化所有服务
 */
export async function initAllServices(): Promise<void> {
  // 初始化存储
  await initStorage();

  // 初始化设置（依赖存储，主题/播放器等都从这里读配置）
  await initSettings();

  // 初始化主题
  await initTheme();

  // 初始化列表
  await initListService();
  // 旧版本「收藏歌单」只是标记，这里一次性迁移成绑定的自建歌单（可在我的列表里同步）
  await migrateLegacyCollections();

  // 初始化下载服务（加载下载历史）
  await initDownloadService();

  // 初始化播放器
  await playerService.init();

  // 恢复定时退出（睡眠定时）
  sleepTimerService.restoreFromSettings();
}

/**
 * 初始化图片缓存服务
 */
export async function initImageCache(context: common.UIAbilityContext): Promise<void> {
  await imageCacheService.init(context);
}
