/**
 * 自定义源插件实现
 * 基于 QuickJS 原生引擎执行插件 JS 代码
 */
import hilog from '@ohos.hilog';
import type { Plugin, PluginSongInfo, PluginLyricInfo, PluginSearchResult, PluginSongListResult, PluginBoard, PluginBoardDetail, PluginHotSearch } from './PluginManager';

const TAG = 'CustomSourcePlugin';
const DOMAIN = 0x0001;

// QuickJS native module interface - 映射到 libquickjs_napi.so
// NAPI 模块通过 import 直接导入
interface QuickJSNAPI {
  loadScript(script: string): string;
  callJS(action: string, data: string): string;
  destroy(): void;
}

// QuickJS request info
interface QuickJSRequestInfo {
  mid?: string;
  hash?: string;
  type?: string;
  keyword?: string;
  page?: number;
  tagId?: string;
  boardId?: string;
}

// QuickJS request result
interface QuickJSRequestResult {
  url?: string;
  lyric?: string;
  list?: object[];
  total?: number;
}

// Plugin info interface
interface PluginInfo {
  id: string;
  name: string;
  description: string;
  version: string;
  author: string;
  homepage: string;
}

// Source config for QuickJS init
interface SourceConfig {
  type: string;
  actions: string[];
  qualitys: string[];
}

// QuickJS 状态
let quickjsModule: QuickJSNAPI | null = null;
let isQuickJSInited = false;
let currentPluginId: string = '';

// QuickJS stub 实现类（备用）
class QuickJSStub implements QuickJSNAPI {
  loadScript(script: string): string {
    hilog.info(DOMAIN, TAG, 'QuickJS stub loadScript called, length: %{public}d', script.length);
    return '';
  }

  callJS(action: string, data: string): string {
    hilog.info(DOMAIN, TAG, 'QuickJS stub callJS called: %{public}s', action);
    return '{"error":"stub"}';
  }

  destroy(): void {
    hilog.info(DOMAIN, TAG, 'QuickJS stub destroy called');
  }
}

/**
 * 尝试加载 native QuickJS 模块
 * HarmonyOS NAPI 模块从 native/libs/{abi}/ 目录自动加载
 */
function tryLoadNativeQuickJS(): boolean {
  try {
    hilog.info(DOMAIN, TAG, 'Trying to load native QuickJS module');

    // HarmonyOS NAPI: 直接 import native 模块
    // 库文件名是 liblibquickjs_napi.so，但 import 时使用 liblibquickjs_napi
    // 注意：HarmonyOS 会自动从 native/libs/{abi}/ 目录加载模块
    try {
      // 尝试直接导入 native 模块
      // 注意：这里的导入方式可能因 HarmonyOS 版本而异
      const nativeModule = globalThis.liblibquickjs_napi as QuickJSNAPI | undefined;
      if (nativeModule && typeof nativeModule.loadScript === 'function') {
        hilog.info(DOMAIN, TAG, 'Native QuickJS module found');
        quickjsModule = nativeModule;
        return true;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'Direct import failed: %{public}s', JSON.stringify(e));
    }

    hilog.warn(DOMAIN, TAG, 'Native QuickJS module not available, using stub');
    return false;

  } catch (e) {
    hilog.error(DOMAIN, TAG, 'Error loading native QuickJS: %{public}s', JSON.stringify(e));
    return false;
  }
}

/**
 * 初始化 QuickJS 引擎
 */
function initQuickJS(): boolean {
  if (isQuickJSInited && quickjsModule) {
    return true;
  }

  try {
    hilog.info(DOMAIN, TAG, 'Initializing QuickJS engine');

    // 尝试加载 native QuickJS
    let nativeLoaded = tryLoadNativeQuickJS();

    // 如果 native 方式失败，使用 stub
    if (!nativeLoaded) {
      hilog.info(DOMAIN, TAG, 'Using QuickJS stub implementation');
      const stubModule: QuickJSNAPI = new QuickJSStub();
      quickjsModule = stubModule;
    }

    hilog.info(DOMAIN, TAG, 'QuickJS initialized successfully');
    isQuickJSInited = true;
    return true;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'Failed to initialize QuickJS: %{public}s', JSON.stringify(e));
    return false;
  }
}

/**
 * 使用 QuickJS 执行插件请求
 */
function quickjsRequest(source: string, action: string, info: QuickJSRequestInfo): QuickJSRequestResult {
  if (!quickjsModule || !isQuickJSInited) {
    return { url: '', lyric: '', list: [], total: 0 };
  }

  const requestData = JSON.stringify({
    source: source,
    action: action,
    info: info,
  });

  const result = quickjsModule.callJS('request', requestData);
  if (!result) {
    return { url: '', lyric: '', list: [], total: 0 };
  }

  try {
    return JSON.parse(result) as QuickJSRequestResult;
  } catch {
    return { url: '', lyric: '', list: [], total: 0 };
  }
}

/**
 * 加载插件脚本到 QuickJS
 */
function loadPluginToQuickJS(scriptContent: string, pluginInfo: PluginInfo): boolean {
  if (!quickjsModule || !isQuickJSInited) {
    return false;
  }

  try {
    hilog.info(DOMAIN, TAG, 'Loading plugin to QuickJS: %{public}s', pluginInfo.name);

    // 加载插件脚本
    const result = quickjsModule.loadScript(scriptContent);
    if (result && result.length > 0) {
      hilog.error(DOMAIN, TAG, 'Failed to load plugin: %{public}s', result);
      return false;
    }

    // 构建 sources 配置 - 支持所有常见 action
    const sources: Record<string, SourceConfig> = {
      'custom': {
        type: 'music',
        actions: ['musicUrl', 'lyric', 'search', 'songList', 'boards', 'boardList', 'hotSearch'],
        qualitys: ['128k', '320k', 'flac', 'flac24bit']
      }
    };

    // 初始化插件
    const initResult = quickjsModule.callJS('init', JSON.stringify({
      id: pluginInfo.id,
      name: pluginInfo.name,
      sources: sources,
    }));

    hilog.info(DOMAIN, TAG, 'Plugin init result: %{public}s', initResult);

    currentPluginId = pluginInfo.id;
    hilog.info(DOMAIN, TAG, 'Plugin loaded to QuickJS successfully');
    return true;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'Failed to load plugin to QuickJS: %{public}s', JSON.stringify(e));
    return false;
  }
}

/** 自定义源插件类 */
export class CustomSourcePlugin implements Plugin {
  id: string;
  name: string;
  description?: string;
  version?: string;
  author?: string;
  homepage?: string;
  private loaded: boolean = false;
  private scriptContent: string = '';
  private useQuickJS: boolean = false;

  constructor(id: string, name: string, description: string, version: string, author: string, homepage: string, scriptContent: string) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.version = version;
    this.author = author;
    this.homepage = homepage;
    this.scriptContent = scriptContent;
  }

  async onInit(): Promise<boolean> {
    hilog.info(DOMAIN, TAG, 'CustomSourcePlugin initializing: %{public}s', this.name);

    // 初始化 QuickJS
    this.useQuickJS = initQuickJS();

    if (this.useQuickJS) {
      const loaded = loadPluginToQuickJS(this.scriptContent, {
        id: this.id,
        name: this.name,
        description: this.description || '',
        version: this.version || '',
        author: this.author || '',
        homepage: this.homepage || '',
      });

      if (loaded) {
        hilog.info(DOMAIN, TAG, 'CustomSourcePlugin initialized with QuickJS: %{public}s', this.name);
        this.loaded = true;
        return true;
      } else {
        hilog.warn(DOMAIN, TAG, 'QuickJS load failed');
        this.useQuickJS = false;
      }
    }

    hilog.info(DOMAIN, TAG, 'CustomSourcePlugin initialized: %{public}s', this.name);
    this.loaded = true;
    return true;
  }

  onDestroy?(): void {
    this.loaded = false;
    if (quickjsModule && isQuickJSInited) {
      try {
        quickjsModule.destroy();
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'Error destroying QuickJS: %{public}s', JSON.stringify(e));
      }
      isQuickJSInited = false;
    }
    hilog.info(DOMAIN, TAG, 'CustomSourcePlugin destroyed: %{public}s', this.name);
  }

  isLoaded(): boolean {
    return this.loaded;
  }

  getScriptContent(): string {
    return this.scriptContent;
  }

  /**
   * 处理音乐 URL 请求
   */
  private handleGetMusicUrl(songInfo: PluginSongInfo, quality: string): string {
    hilog.info(DOMAIN, TAG, 'CustomSource getMusicUrl: %{public}s quality: %{public}s', songInfo.name, quality);

    if (!this.scriptContent || this.scriptContent.length === 0) {
      hilog.warn(DOMAIN, TAG, 'No plugin script');
      return '';
    }

    // QuickJS 模式
    if (this.useQuickJS && quickjsModule && isQuickJSInited) {
      try {
        const result = quickjsRequest('custom', 'musicUrl', {
          mid: songInfo.songmid || '',
          hash: songInfo.hash || '',
          type: quality,
        });

        if (result.url && typeof result.url === 'string') {
          return result.url;
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'QuickJS musicUrl error: %{public}s', JSON.stringify(e));
      }
    }

    return '';
  }

  /**
   * 处理歌词请求
   */
  private handleGetLyricImpl(songInfo: PluginSongInfo): PluginLyricInfo {
    hilog.info(DOMAIN, TAG, 'CustomSource getLyric: %{public}s', songInfo.name);

    if (this.useQuickJS && quickjsModule && isQuickJSInited) {
      try {
        const result = quickjsRequest('custom', 'lyric', {
          mid: songInfo.songmid || '',
          hash: songInfo.hash || '',
        });

        if (result.lyric) {
          return { lyric: result.lyric };
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'QuickJS lyric error: %{public}s', JSON.stringify(e));
      }
    }

    return { lyric: '' };
  }

  /**
   * 处理搜索请求
   */
  private handleSearchImpl(keyword: string, page: number): PluginSearchResult {
    hilog.info(DOMAIN, TAG, 'CustomSource search: %{public}s page: %{public}d', keyword, page);

    if (this.useQuickJS && quickjsModule && isQuickJSInited) {
      try {
        const result = quickjsRequest('custom', 'search', {
          keyword: keyword,
          page: page,
        });

        if (result.list && Array.isArray(result.list)) {
          const list: PluginSongInfo[] = result.list as PluginSongInfo[];
          return {
            list: list,
            total: result.total || 0,
            page: page
          };
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'QuickJS search error: %{public}s', JSON.stringify(e));
      }
    }

    return { list: [], total: 0, page: page };
  }

  /**
   * 处理歌单列表请求
   */
  private handleGetSongListImpl(tagId: string, page: number): PluginSongListResult {
    hilog.info(DOMAIN, TAG, 'CustomSource getSongList tagId: %{public}s page: %{public}d', tagId, page);

    if (this.useQuickJS && quickjsModule && isQuickJSInited) {
      try {
        const result = quickjsRequest('custom', 'songList', {
          tagId: tagId,
          page: page,
        });

        if (result.list && Array.isArray(result.list)) {
          const list: PluginSongInfo[] = result.list as PluginSongInfo[];
          return {
            list: list,
            total: result.total || 0,
            page: page,
            limit: 20
          };
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'QuickJS songList error: %{public}s', JSON.stringify(e));
      }
    }

    return { list: [], total: 0, page: page, limit: 20 };
  }

  /**
   * 处理板块列表请求
   */
  private handleGetBoardsImpl(): PluginBoard[] {
    hilog.info(DOMAIN, TAG, 'CustomSource getBoards');

    if (this.useQuickJS && quickjsModule && isQuickJSInited) {
      try {
        const result = quickjsRequest('custom', 'boards', {});

        if (result.list && Array.isArray(result.list)) {
          const boards: PluginBoard[] = result.list as PluginBoard[];
          return boards;
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'QuickJS boards error: %{public}s', JSON.stringify(e));
      }
    }

    return [];
  }

  /**
   * 处理板块详情请求
   */
  private handleGetBoardListImpl(boardId: string, page: number): PluginBoardDetail {
    hilog.info(DOMAIN, TAG, 'CustomSource getBoardList boardId: %{public}s page: %{public}d', boardId, page);

    if (this.useQuickJS && quickjsModule && isQuickJSInited) {
      try {
        const result = quickjsRequest('custom', 'boardList', {
          boardId: boardId,
          page: page,
        });

        if (result.list && Array.isArray(result.list)) {
          const list: PluginSongInfo[] = result.list as PluginSongInfo[];
          return {
            name: boardId,
            list: list,
            total: result.total || 0,
            page: page
          };
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'QuickJS boardList error: %{public}s', JSON.stringify(e));
      }
    }

    return { name: '', list: [], total: 0, page: page };
  }

  /**
   * 处理热门搜索请求
   */
  private handleGetHotSearchImpl(): PluginHotSearch[] {
    hilog.info(DOMAIN, TAG, 'CustomSource getHotSearch');

    if (this.useQuickJS && quickjsModule && isQuickJSInited) {
      try {
        const result = quickjsRequest('custom', 'hotSearch', {});

        if (result.list && Array.isArray(result.list)) {
          return result.list as PluginHotSearch[];
        }
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'QuickJS hotSearch error: %{public}s', JSON.stringify(e));
      }
    }

    return [];
  }

  // ==================== Plugin 接口实现 ====================

  onGetMusicUrl(songInfo: PluginSongInfo, quality: string): Promise<string> {
    const result = this.handleGetMusicUrl(songInfo, quality);
    return Promise.resolve(result);
  }

  onGetLyric(songInfo: PluginSongInfo): Promise<PluginLyricInfo> {
    const result = this.handleGetLyricImpl(songInfo);
    return Promise.resolve(result);
  }

  onSearch(keyword: string, page: number): Promise<PluginSearchResult> {
    const result = this.handleSearchImpl(keyword, page);
    return Promise.resolve(result);
  }

  onGetSongList(tagId: string, page: number): Promise<PluginSongListResult> {
    const result = this.handleGetSongListImpl(tagId, page);
    return Promise.resolve(result);
  }

  onGetBoards(): Promise<PluginBoard[]> {
    const result = this.handleGetBoardsImpl();
    return Promise.resolve(result);
  }

  onGetBoardList(boardId: string, page: number): Promise<PluginBoardDetail> {
    const result = this.handleGetBoardListImpl(boardId, page);
    return Promise.resolve(result);
  }

  onGetHotSearch(): Promise<PluginHotSearch[]> {
    const result = this.handleGetHotSearchImpl();
    return Promise.resolve(result);
  }
}
