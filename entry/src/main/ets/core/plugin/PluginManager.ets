/**
 * 插件系统核心
 * 支持加载用户提供的在线JS源文件作为自定义音乐源
 */
import { httpRequest } from '../network/http';
import hilog from '@ohos.hilog';
import { getStorageService } from '../interfaces/IStorageService';
import { CustomSourcePlugin } from './CustomSourcePlugin';

const TAG = 'PluginManager';
const DOMAIN = 0x0001;

// ============ 类型定义 ============

/** 歌曲信息 */
export interface PluginSongInfo {
  songmid: string;
  name: string;
  singer: string;
  albumName?: string;
  albumId?: string;
  duration?: string;
  source: string;
  hash?: string;
}

/** 歌词信息 */
export interface PluginLyricInfo {
  lyric: string;
  tlyric?: string;
  lxlyric?: string;
  rlyric?: string;
}

/** 插件元信息 */
export interface PluginMeta {
  id: string;
  name: string;
  description: string;
  version: string;
  author: string;
  homepage: string;
}

/** 搜索结果 */
export interface PluginSearchResult {
  list: PluginSongInfo[];
  total: number;
  page: number;
}

/** 歌单结果 */
export interface PluginSongListResult {
  list: PluginSongInfo[];
  total: number;
  page: number;
  limit: number;
}

/** 榜单信息 */
export interface PluginBoard {
  id: string;
  name: string;
  pic: string;
  playCount?: number;
}

/** 榜单详情 */
export interface PluginBoardDetail {
  name: string;
  list: PluginSongInfo[];
  total: number;
  page: number;
}

/** 热搜项 */
export interface PluginHotSearch {
  index: number;
  title: string;
  url: string;
}

/** 插件接口 */
export interface Plugin {
  id: string;
  name: string;
  description?: string;
  version?: string;
  author?: string;
  homepage?: string;
  onInit(): Promise<boolean>;
  onDestroy?(): void;
  onGetMusicUrl?(songInfo: PluginSongInfo, quality: string): Promise<string>;
  onGetLyric?(songInfo: PluginSongInfo): Promise<PluginLyricInfo>;
  onGetPic?(songInfo: PluginSongInfo): Promise<string>;
  onSearch?(keyword: string, page: number): Promise<PluginSearchResult>;
  onGetSongList?(tagId: string, page: number): Promise<PluginSongListResult>;
  onGetBoards?(): Promise<PluginBoard[]>;
  onGetBoardList?(boardId: string, page: number): Promise<PluginBoardDetail>;
  onGetHotSearch?(): Promise<PluginHotSearch[]>;
}

export type MusicSource = string;
export const SUPPORTED_SOURCES: string[] = ['kw', 'kg', 'tx', 'wy', 'mg'];

// ============ 插件管理器 ============

class PluginManagerImpl {
  private plugins: Map<string, Plugin> = new Map();
  private activePluginId: string | null = null;
  private apiSourceUrl: string = '';
  private pluginLoaded: boolean = false;
  private pluginLoading: boolean = false;
  private pluginError: string | null = null;
  private pluginMeta: PluginMeta | null = null;

  /** 注册插件 */
  register(plugin: Plugin): void {
    this.plugins.set(plugin.id, plugin);
    hilog.info(DOMAIN, TAG, 'Plugin registered: %{public}s', plugin.id);
  }

  /** 注销插件 */
  unregister(pluginId: string): void {
    const plugin = this.plugins.get(pluginId);
    if (plugin?.onDestroy) {
      plugin.onDestroy();
    }
    this.plugins.delete(pluginId);
    hilog.info(DOMAIN, TAG, 'Plugin unregistered: %{public}s', pluginId);
  }

  /** 获取插件 */
  getPlugin(pluginId: string): Plugin | undefined {
    return this.plugins.get(pluginId);
  }

  /** 获取所有插件 */
  getPlugins(): Plugin[] {
    return Array.from(this.plugins.values());
  }

  /** 设置激活插件 */
  setActivePlugin(pluginId: string): boolean {
    if (this.plugins.has(pluginId)) {
      this.activePluginId = pluginId;
      hilog.info(DOMAIN, TAG, 'Active plugin set: %{public}s', pluginId);
      return true;
    }
    return false;
  }

  /** 获取激活插件ID */
  getActivePluginId(): string | null {
    return this.activePluginId;
  }

  /** 获取激活插件 */
  getActivePlugin(): Plugin | undefined {
    if (this.activePluginId) {
      return this.plugins.get(this.activePluginId);
    }
    return undefined;
  }

  /** 加载自定义源插件 */
  async loadCustomSource(url: string): Promise<boolean> {
    if (this.pluginLoading) {
      hilog.warn(DOMAIN, TAG, 'Plugin is already loading');
      return false;
    }

    hilog.info(DOMAIN, TAG, 'Loading custom source from: %{public}s', url);
    this.pluginLoading = true;
    this.pluginError = null;
    this.apiSourceUrl = url;

    try {
      // 下载JS脚本
      const task = httpRequest(url, { method: 'GET' });
      const response = await task.promise;
      const scriptContent: string = response.result as string;

      if (!scriptContent || scriptContent.length === 0) {
        throw new Error('Empty script content');
      }

      hilog.info(DOMAIN, TAG, 'Script downloaded, length: %{public}d', scriptContent.length);

      // 解析插件信息
      this.pluginMeta = this.parsePluginMeta(scriptContent);

      // 创建自定义源插件
      const pluginId = 'custom_' + Date.now();
      const customPlugin: Plugin = new CustomSourcePlugin(
        pluginId,
        this.pluginMeta.name,
        this.pluginMeta.description,
        this.pluginMeta.version,
        this.pluginMeta.author,
        this.pluginMeta.homepage,
        scriptContent
      );

      // 注册并激活
      this.register(customPlugin);
      this.setActivePlugin(pluginId);

      // 初始化
      await customPlugin.onInit();

      // 保存URL
      await this.saveCustomSourceUrl(url);

      hilog.info(DOMAIN, TAG, 'Custom source loaded: %{public}s', this.pluginMeta.name);
      this.pluginLoading = false;
      this.pluginLoaded = true;
      return true;

    } catch (error) {
      const errMsg = (error as Error).message;
      hilog.error(DOMAIN, TAG, 'Failed to load custom source: %{public}s', errMsg);
      this.pluginError = errMsg;
      this.pluginLoading = false;
      return false;
    }
  }

  /** 解析插件元信息 */
  private parsePluginMeta(script: string): PluginMeta {
    const meta: PluginMeta = {
      id: 'custom_' + Date.now(),
      name: '自定义源',
      description: '用户自定义音乐源',
      version: '1.0.0',
      author: '未知',
      homepage: '',
    };

    const nameMatch = script.match(/\/\/\s*@name\s+(.+)/);
    const descMatch = script.match(/\/\/\s*@description\s+(.+)/);
    const versionMatch = script.match(/\/\/\s*@version\s+(.+)/);
    const authorMatch = script.match(/\/\/\s*@author\s+(.+)/);
    const homepageMatch = script.match(/\/\/\s*@homepage\s+(.+)/);

    if (nameMatch) meta.name = nameMatch[1].trim();
    if (descMatch) meta.description = descMatch[1].trim();
    if (versionMatch) meta.version = versionMatch[1].trim();
    if (authorMatch) meta.author = authorMatch[1].trim();
    if (homepageMatch) meta.homepage = homepageMatch[1].trim();

    return meta;
  }

  /** 保存自定义源URL */
  private async saveCustomSourceUrl(url: string): Promise<void> {
    await getStorageService().setString('plugin.customSourceUrl', url);
    await getStorageService().setString('plugin.currentSource', 'custom');
  }

  /** 卸载插件 */
  unloadPlugin(): void {
    if (this.activePluginId && this.activePluginId.startsWith('custom_')) {
      this.unregister(this.activePluginId);
      this.activePluginId = null;
    }
    this.pluginLoaded = false;
    this.pluginError = null;
    this.pluginMeta = null;
    hilog.info(DOMAIN, TAG, 'Custom plugin unloaded');
  }

  /** 是否已加载 */
  isLoaded(): boolean {
    return this.pluginLoaded;
  }

  /** 是否加载中 */
  isLoading(): boolean {
    return this.pluginLoading;
  }

  /** 获取错误信息 */
  getError(): string | null {
    return this.pluginError;
  }

  /** 获取插件元信息 */
  getPluginInfo(): PluginMeta | null {
    return this.pluginMeta;
  }

  /** 获取当前源URL */
  getApiSourceUrl(): string {
    return this.apiSourceUrl;
  }
}

// 单例
export const pluginManager = new PluginManagerImpl();
export default pluginManager;
