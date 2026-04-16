/**
 * 服务模块导出
 * 统一导出所有核心服务
 */

// 导入各个服务
import { default as storageService, initStorage, StorageServiceInterface } from './StorageService';
import { default as themeService, initTheme, ThemeServiceInterface } from './ThemeService';
import { default as listService, initListService, LIST_IDS, getDefaultList, getLoveList, getUserList, getUserListMusic, addMusicToList, removeMusicFromList, createUserList, deleteUserList, setPlayList, getPlayList, setPlayIndex, getCurrentMusic, playNext, playPrev, isInLoveList, toggleLoveList, onListChange, MusicItem, ListInfo, ListServiceInterface } from './ListService';
import { default as eventBus, EventTypes, on, once, off, emit, clear, emitPlayStateChanged, emitPlayProgressChanged, emitPlayMusicChanged, emitSearchStarted, emitSearchCompleted, emitListUpdated, emitThemeChanged, emitError, emitToast, EventBusInterface } from './EventBus';
import { playerService, PlayStatus, SongInfo, MusicInfo, ProgressInfo, PlayerService } from './PlayerService';
import { navigationService, RouteName, NavigationService } from './NavigationService';
import { initDownloadService } from '../core/music/MusicFeatureEntry';

// HTTP服务（统一从 core/network/http 导出）
export { httpRequest, httpGet, httpPost } from '../core/network/http';

// 播放器服务
export { default as PlayerService, playerService as playerServiceInstance, PlayStatus, SongInfo, MusicInfo, ProgressInfo } from './PlayerService';

// 导航服务
export { navigationService, RouteName, NavigationService } from './NavigationService';

// 存储服务
export { default as StorageService, initStorage, getString, getNumber, getBoolean, setString, setNumber, setBoolean, remove, clear, has, StorageKeys } from './StorageService';

// 主题服务
export { default as ThemeService, initTheme, getCurrentThemeId, getActiveTheme, getAllThemes, applyThemeById, isDarkMode, getBackgroundImage, getAppBackground, getContentBackground, onThemeChange } from './ThemeService';

// 列表服务
export { default as ListService, LIST_IDS, initListService, getDefaultList, getLoveList, getUserList, getUserListMusic, addMusicToList, removeMusicFromList, createUserList, deleteUserList, setPlayList, getPlayList, setPlayIndex, getCurrentMusic, playNext, playPrev, isInLoveList, toggleLoveList, onListChange, MusicItem, ListInfo } from './ListService';

// 事件总线（重命名 clear 避免冲突）
export { default as EventBus, EventTypes, on, once, off, emit, clear as clearAllEvents, emitPlayStateChanged, emitPlayProgressChanged, emitPlayMusicChanged, emitSearchStarted, emitSearchCompleted, emitListUpdated, emitThemeChanged, emitError, emitToast } from './EventBus';

/**
 * 初始化所有服务
 */
export async function initAllServices(): Promise<void> {
  // 初始化存储
  await initStorage();

  // 初始化主题
  await initTheme();

  // 初始化列表
  await initListService();

  // 初始化下载服务（加载下载历史）
  await initDownloadService();

  // 初始化播放器
  await playerService.init();
}
