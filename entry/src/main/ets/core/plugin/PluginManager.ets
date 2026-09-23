/**
 * 插件系统核心
 * 支持加载用户提供的在线JS源文件作为自定义音乐源
 */
import { httpRequest } from '../network/http';
import hilog from '@ohos.hilog';
import { getStorageService } from '../interfaces/IStorageService';
import { CustomSourcePlugin } from './CustomSourcePlugin';
import fs from '@ohos.file.fs';
import { utf8Decode } from '../../utils/TextCodec';
import { t } from '../../service/LocalizationService';
import {
  loadStoredSources,
  upsertStoredSource,
  removeStoredSource,
  setEnabledSource,
  findEnabledSource,
  type StoredCustomSource
} from './PluginStore';

export type { StoredCustomSource };

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

  /** 设置激活插件 */
  setActivePlugin(pluginId: string): boolean {
    if (this.plugins.has(pluginId)) {
      this.activePluginId = pluginId;
      hilog.info(DOMAIN, TAG, 'Active plugin set: %{public}s', pluginId);
      return true;
    }
    return false;
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
      hilog.warn(DOMAIN, TAG, 'Plugin is already loading, waiting for current load to finish');
      return await this.waitForCurrentLoading();
    }

    hilog.info(DOMAIN, TAG, 'Loading custom source from: %{public}s', url);
    this.pluginLoading = true;
    this.pluginError = null;
    this.apiSourceUrl = url;
    const previousActivePluginId = this.activePluginId;
    let createdPluginId: string | null = null;

    try {
      // 加载JS脚本（支持在线链接与本地文件URI）
      const scriptContent: string = await this.loadCustomSourceScript(url);

      if (!scriptContent || scriptContent.length === 0) {
        throw new Error('Empty script content');
      }

      hilog.info(DOMAIN, TAG, 'Script downloaded, length: %{public}d', scriptContent.length);

      // 解析插件信息
      this.pluginMeta = this.parsePluginMeta(scriptContent);

      // 创建自定义源插件
      const pluginId = 'custom_' + Date.now();
      createdPluginId = pluginId;
      const customPlugin: Plugin = new CustomSourcePlugin(
        pluginId,
        this.pluginMeta.name,
        this.pluginMeta.description,
        this.pluginMeta.version,
        this.pluginMeta.author,
        this.pluginMeta.homepage,
        scriptContent
      );

      // 初始化
      const inited = await customPlugin.onInit();
      if (!inited) {
        throw new Error('Custom source init failed');
      }

      // 注册并激活
      this.register(customPlugin);
      this.setActivePlugin(pluginId);

      // 保存URL
      await this.saveCustomSourceUrl(url);
      // 记入自定义源列表（可多源管理：启用/停用/更新/删除）
      await this.persistLoadedSource(pluginId, url, scriptContent, this.pluginMeta);

      hilog.info(DOMAIN, TAG, 'Custom source loaded: %{public}s', this.pluginMeta.name);
      this.pluginLoading = false;
    this.pluginLoaded = true;
      return true;

    } catch (error) {
      const errMsg = (error as Error).message;
      hilog.error(DOMAIN, TAG, 'Failed to load custom source: %{public}s', errMsg);
      // 仅清理本次新建但失败的插件，避免误删之前可用插件
      if (createdPluginId && this.plugins.has(createdPluginId)) {
        this.unregister(createdPluginId);
      }
      if (previousActivePluginId && this.plugins.has(previousActivePluginId)) {
        this.activePluginId = previousActivePluginId;
      } else if (this.activePluginId === createdPluginId) {
        this.activePluginId = null;
      }
      this.pluginError = errMsg;
      this.pluginLoading = false;
      this.pluginLoaded = false;
      return false;
    }
  }

  private async loadCustomSourceScript(source: string): Promise<string> {
    const trimmed = source.trim();
    if (/^https?:\/\//i.test(trimmed)) {
      const task = httpRequest(trimmed, { method: 'GET' });
      const response = await task.promise;
      return response.result as string;
    }
    return await this.readScriptFromLocalUri(trimmed);
  }

  private async readScriptFromLocalUri(uriOrPath: string): Promise<string> {
    const candidates: string[] = [];
    candidates.push(uriOrPath);
    if (uriOrPath.startsWith('file://')) {
      candidates.push(uriOrPath.substring(7));
    }
    try {
      candidates.push(decodeURIComponent(uriOrPath));
    } catch (_e) {
      // ignore decode failure
    }

    let lastError: Error | null = null;
    for (let i = 0; i < candidates.length; i++) {
      const candidate = candidates[i];
      try {
        const file = await fs.open(candidate, fs.OpenMode.READ_ONLY);
        try {
          const stat = await fs.stat(file.fd);
          const buffer = new ArrayBuffer(stat.size);
          await fs.read(file.fd, buffer);
          const text = utf8Decode(new Uint8Array(buffer));
          if (text && text.length > 0) {
            return text;
          }
        } finally {
          await fs.close(file.fd);
        }
      } catch (err) {
        const msg = err instanceof Error ? err.message : JSON.stringify(err);
        lastError = new Error(msg);
      }
    }
    throw new Error(lastError ? lastError.message : '无法读取本地插件文件');
  }

  /** 等待当前加载中的插件流程结束，避免并发调用导致首播失败 */
  private async waitForCurrentLoading(timeoutMs: number = 12000): Promise<boolean> {
    const start = Date.now();
    while (this.pluginLoading) {
      if (Date.now() - start > timeoutMs) {
        hilog.warn(DOMAIN, TAG, 'Wait plugin loading timeout: %{public}dms', timeoutMs);
        break;
      }
      await new Promise<void>((resolve) => setTimeout(resolve, 120));
    }
    const active = this.getActivePlugin();
    return !!(this.pluginLoaded && active);
  }

  /** 解析插件元信息。兼容注释标注、明文对象、以及混淆代码 */
  private parsePluginMeta(script: string): PluginMeta {
    const meta: PluginMeta = {
      id: 'custom_' + Date.now(),
      name: t('custom_source_title'),
      description: t('custom_source_desc'),
      version: '1.0.0',
      author: t('unknown'),
      homepage: '',
    };

    // Strategy 1: Comment annotations (normal scripts)
    // e.g., // @name MyPlugin
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

    // Strategy 2: Object literal patterns (minified but not fully obfuscated)
    // e.g., {name:"MyPlugin",version:"2.0.0"}
    // Match quoted values in object-like context
    if (meta.name === '自定义源') {
      // Try name key-value patterns: name:"xxx", name:'xxx', n:"xxx"
      const nameKv = script.match(/(?:name|pluginName|plugin_name)\s*:\s*['"]([^'"]+)['"]/i);
      if (nameKv) meta.name = nameKv[1].trim();
    }
    if (meta.version === '1.0.0') {
      const verKv = script.match(/(?:version|ver|v)\s*:\s*['"]([^'"]+)['"]/i);
      if (verKv) meta.version = verKv[1].trim();
    }
    if (meta.author === '未知') {
      const authorKv = script.match(/(?:author|authorName|author_name)\s*:\s*['"]([^'"]+)['"]/i);
      if (authorKv) meta.author = authorKv[1].trim();
    }
    if (meta.description === '用户自定义音乐源') {
      const descKv = script.match(/(?:description|desc|info)\s*:\s*['"]([^'"]+)['"]/i);
      if (descKv) meta.description = descKv[1].trim();
    }
    if (meta.homepage === '') {
      const hpKv = script.match(/(?:homepage|url|site)\s*:\s*['"](https?:\/\/[^'"]+)['"]/i);
      if (hpKv) meta.homepage = hpKv[1].trim();
    }

    // Strategy 3: For fully obfuscated code, try to extract any useful identifier
    // from common patterns like source name at the top of the script
    if (meta.name === '自定义源') {
      // Look for any source-like name in the first 500 chars
      const head = script.substring(0, 500);
      const srcName = head.match(/(?:source|site|platform)\s*:\s*['"]([^'"]+)['"]/i);
      if (srcName) {
        meta.name = srcName[1].trim() + '源';
      }
    }

    return meta;
  }

  /** 保存自定义源URL */
  private async saveCustomSourceUrl(url: string): Promise<void> {
    await getStorageService().setString('plugin.customSourceUrl', url);
    await getStorageService().setString('plugin.currentSource', 'custom');
  }

  /** 把刚加载成功的自定义源写入持久化列表，并把它设为唯一启用项 */
  private async persistLoadedSource(
    pluginId: string,
    url: string,
    script: string,
    meta: PluginMeta | null
  ): Promise<void> {
    try {
      await setEnabledSource(null);
      const record: StoredCustomSource = {
        id: pluginId,
        url,
        name: meta?.name ?? url,
        version: meta?.version ?? '',
        author: meta?.author ?? '',
        description: meta?.description ?? '',
        homepage: meta?.homepage ?? '',
        script,
        enabled: true,
        addedAt: Date.now(),
        updatedAt: Date.now(),
      };
      await upsertStoredSource(record);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'persistLoadedSource failed: %{public}s', JSON.stringify(err));
    }
  }

  // ==================== 自定义源列表（多源管理） ====================

  /** 读取全部已保存的自定义源 */
  async getStoredSources(): Promise<StoredCustomSource[]> {
    return await loadStoredSources();
  }

  /**
   * 启用/停用某个自定义源
   * - 启用：用保存的脚本重新实例化并激活（脚本缺失时按 url 重新下载）
   * - 停用：若它是当前激活源则卸载
   */
  async setSourceEnabled(id: string, enabled: boolean): Promise<boolean> {
    const list = await loadStoredSources();
    const target = list.find((item: StoredCustomSource) => item.id === id);
    if (!target) {
      return false;
    }
    if (!enabled) {
      await setEnabledSource(null);
      if (this.activePluginId === id) {
        this.unloadPlugin();
      }
      await getStorageService().setString('plugin.currentSource', 'kw');
      return true;
    }

    let script = target.script;
    if (script.length === 0) {
      script = await this.loadCustomSourceScript(target.url);
    }
    if (script.length === 0) {
      return false;
    }
    const ok = await this.activateFromScript(id, script);
    if (!ok) {
      return false;
    }
    // 只保留一个启用项
    await setEnabledSource(null);
    target.script = script;
    target.enabled = true;
    target.updatedAt = Date.now();
    await upsertStoredSource(target);
    await this.saveCustomSourceUrl(target.url);
    return true;
  }

  /** 重新下载脚本并刷新元信息（「更新」按钮） */
  async updateSource(id: string): Promise<boolean> {
    const list = await loadStoredSources();
    const target = list.find((item: StoredCustomSource) => item.id === id);
    if (!target) {
      return false;
    }
    const script = await this.loadCustomSourceScript(target.url);
    if (script.length === 0) {
      return false;
    }
    const meta = this.parsePluginMeta(script);
    target.script = script;
    target.name = meta.name;
    target.version = meta.version;
    target.author = meta.author;
    target.description = meta.description;
    target.homepage = meta.homepage;
    target.updatedAt = Date.now();
    await upsertStoredSource(target);
    // 若是当前启用的源，需要重新实例化才能生效
    if (target.enabled) {
      return await this.activateFromScript(target.id, script);
    }
    return true;
  }

  /** 删除某个自定义源 */
  async removeSource(id: string): Promise<void> {
    const wasActive = this.activePluginId === id;
    if (wasActive) {
      this.unloadPlugin();
      await getStorageService().setString('plugin.currentSource', 'kw');
    }
    await removeStoredSource(id);
  }

  /** 用脚本正文实例化并激活插件（供启用/更新/启动恢复复用） */
  private async activateFromScript(pluginId: string, script: string): Promise<boolean> {
    try {
      const meta = this.parsePluginMeta(script);
      const plugin: Plugin = new CustomSourcePlugin(
        pluginId,
        meta.name,
        meta.description,
        meta.version,
        meta.author,
        meta.homepage,
        script
      );
      const inited = await plugin.onInit();
      if (!inited) {
        return false;
      }
      if (this.plugins.has(pluginId)) {
        this.unregister(pluginId);
      }
      const previousActive = this.activePluginId;
      if (previousActive && previousActive !== pluginId && this.plugins.has(previousActive)) {
        this.unregister(previousActive);
      }
      this.register(plugin);
      this.setActivePlugin(pluginId);
      this.pluginMeta = meta;
      this.apiSourceUrl = meta.homepage;
      this.pluginLoaded = true;
      this.pluginError = null;
      return true;
    } catch (err) {
      const msg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'activateFromScript failed: %{public}s', msg);
      this.pluginError = msg;
      return false;
    }
  }

  /**
   * 启动时恢复上次启用的自定义源（由 AppBootstrap 延迟调用）
   * 脚本缺失时回落到按 url 下载，保证老数据也能恢复
   */
  async restoreEnabledSource(): Promise<boolean> {
    const list = await loadStoredSources();
    const enabledSource = findEnabledSource(list);
    if (!enabledSource) {
      return false;
    }
    if (enabledSource.script.length > 0) {
      const ok = await this.activateFromScript(enabledSource.id, enabledSource.script);
      if (ok) {
        await getStorageService().setString('plugin.currentSource', 'custom');
      }
      return ok;
    }
    return await this.loadCustomSource(enabledSource.url);
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

}

// 单例
export const pluginManager = new PluginManagerImpl();
export default pluginManager;
