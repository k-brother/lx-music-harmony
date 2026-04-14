/**
 * 自定义源插件实现
 * 基于 QuickJS 原生引擎执行插件 JS 代码
 */
import hilog from '@ohos.hilog';
import { initQuickJS as initNativeQuickJS, loadPluginScript, callPluginAction, destroyQuickJS as destroyNativeQuickJS, loadPreloadScript } from '../napi/napi_quickjs';
import { httpRequest } from '../network/http';
import type { Plugin, PluginSongInfo, PluginLyricInfo, PluginSearchResult, PluginSongListResult, PluginBoard, PluginBoardDetail, PluginHotSearch } from './PluginManager';

const TAG = 'CustomSourcePlugin';
const DOMAIN = 0x0001;

// QuickJS request info
interface QuickJSRequestInfo {
  mid?: string;
  hash?: string;
  type?: string;
  musicInfo?: PluginSongInfo;
  keyword?: string;
  page?: number;
  tagId?: string;
  boardId?: string;
}

// QuickJS request result
interface QuickJSRequestResult {
  url?: string;
  pic?: string;
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

interface InitCallResult {
  error?: string;
}

interface ScriptApiResponse {
  code: number;
  url?: string;
  msg?: string;
}

const QUICKJS_SETUP_KEY = 'lxmusic_harmony_key';

// QuickJS 状态
let isQuickJSInited = false;
let currentPluginId: string = '';

function formatErrorMessage(err: Object): string {
  const e = err as Error;
  if (e && e.message && e.message.length > 0) {
    return e.message;
  }
  const text = String(err);
  if (text && text !== '[object Object]') {
    return text;
  }
  const json = JSON.stringify(err);
  if (json && json !== '{}') {
    return json;
  }
  return 'unknown error object';
}

/**
 * 加载 native QuickJS 模块
 */
function loadNativeQuickJS(): boolean {
  hilog.info(DOMAIN, TAG, 'Loading native QuickJS module');

  // 直接调用 napi_quickjs 模块初始化
  // 静态导入的 native module 会在内部处理所有加载逻辑
  const result = initNativeQuickJS();
  hilog.info(DOMAIN, TAG, 'initNativeQuickJS result: %{public}s', result.toString());
  return result;
}

/**
 * 尝试初始化 native QuickJS
 */
function tryLoadNativeQuickJS(): boolean {
  hilog.info(DOMAIN, TAG, 'tryLoadNativeQuickJS called');

  // 尝试加载 native QuickJS
  const loaded = loadNativeQuickJS();
  if (loaded) {
    hilog.info(DOMAIN, TAG, 'Native QuickJS loaded successfully');
    return true;
  }

  hilog.warn(DOMAIN, TAG, 'Failed to load native QuickJS');
  return false;
}

/**
 * 初始化 QuickJS 引擎
 */
function initQuickJS(): boolean {
  if (isQuickJSInited) {
    return true;
  }

  hilog.info(DOMAIN, TAG, 'Initializing QuickJS engine');

  // 尝试加载 native QuickJS
  const nativeLoaded = tryLoadNativeQuickJS();

  if (!nativeLoaded) {
    hilog.error(DOMAIN, TAG, 'QuickJS native module unavailable');
    isQuickJSInited = false;
    return false;
  }

  hilog.info(DOMAIN, TAG, 'QuickJS initialized successfully');
  isQuickJSInited = true;
  return true;
}

/**
 * 使用 QuickJS 执行插件请求
 */
function quickjsRequest(source: string, action: string, info: QuickJSRequestInfo): QuickJSRequestResult {
  if (!isQuickJSInited) {
    return { url: '', lyric: '', list: [], total: 0 };
  }

  const requestData = JSON.stringify({
    source: source,
    action: action,
    info: info,
  });

  const result = callPluginAction('request', requestData);
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
 * 解析插件信息
 */
function parsePluginInfo(scriptContent: string): PluginInfo | null {
  try {
    const infoMatch = scriptContent.match(/export\s+const\s+plugin\s*=\s*\{([^}]+)\}/s);
    if (!infoMatch) {
      return null;
    }

    const info: PluginInfo = {
      id: '',
      name: '',
      description: '',
      version: '',
      author: '',
      homepage: '',
    };

    const idMatch = scriptContent.match(/id:\s*['"]([^'"]+)['"]/);
    if (idMatch) {
      info.id = idMatch[1];
    }

    const nameMatch = scriptContent.match(/name:\s*['"]([^'"]+)['"]/);
    if (nameMatch) {
      info.name = nameMatch[1];
    }

    const descMatch = scriptContent.match(/description:\s*['"]([^'"]+)['"]/);
    if (descMatch) {
      info.description = descMatch[1];
    }

    const versionMatch = scriptContent.match(/version:\s*['"]([^'"]+)['"]/);
    if (versionMatch) {
      info.version = versionMatch[1];
    }

    const authorMatch = scriptContent.match(/author:\s*['"]([^'"]+)['"]/);
    if (authorMatch) {
      info.author = authorMatch[1];
    }

    const homepageMatch = scriptContent.match(/homepage:\s*['"]([^'"]+)['"]/);
    if (homepageMatch) {
      info.homepage = homepageMatch[1];
    }

    return info;
  } catch {
    return null;
  }
}

function parseSupportedActions(scriptContent: string): Set<string> {
  const actions = new Set<string>();
  const actionBlockRegex = /actions\s*:\s*\[([^\]]*)\]/g;
  let match: RegExpExecArray | null = actionBlockRegex.exec(scriptContent);
  while (match) {
    const block = match[1];
    const actionRegex = /['"]([a-zA-Z][a-zA-Z0-9]*)['"]/g;
    let actionMatch: RegExpExecArray | null = actionRegex.exec(block);
    while (actionMatch) {
      actions.add(actionMatch[1]);
      actionMatch = actionRegex.exec(block);
    }
    match = actionBlockRegex.exec(scriptContent);
  }
  if (actions.size === 0) {
    // Keep compatibility with old scripts that only expose musicUrl.
    actions.add('musicUrl');
  }
  return actions;
}

/**
 * 加载插件到 QuickJS
 */
function loadPluginToQuickJS(scriptContent: string, pluginInfo: PluginInfo, sources: SourceConfig[]): boolean {
  if (!isQuickJSInited) {
    return false;
  }

  try {
    hilog.info(DOMAIN, TAG, 'Loading plugin to QuickJS: %{public}s', pluginInfo.name);

    const entryScript = [
      'if (typeof globalThis.lx_setup === "function") {',
      `  globalThis.lx_setup(${JSON.stringify(QUICKJS_SETUP_KEY)}, ${JSON.stringify(pluginInfo.id)}, ${JSON.stringify(pluginInfo.name)}, ${JSON.stringify(pluginInfo.description)}, ${JSON.stringify(pluginInfo.version)}, ${JSON.stringify(pluginInfo.author)}, ${JSON.stringify(pluginInfo.homepage)}, ${JSON.stringify(scriptContent)});`,
      '}',
      scriptContent,
    ].join('\n');

    const loaded = loadPluginScript(entryScript);
    if (!loaded) {
      hilog.error(DOMAIN, TAG, 'Failed to load plugin script');
      return false;
    }

    const initResult = callPluginAction('init', JSON.stringify({
      id: pluginInfo.id,
      name: pluginInfo.name,
      sources: sources,
    }));
    // Current preload bridge does not implement explicit "init" action.
    // Many scripts initialize themselves via send(EVENT_NAMES.inited) at load time.
    if (initResult && initResult.length > 0 && initResult !== 'Unknown action: init') {
      hilog.info(DOMAIN, TAG, 'Plugin init result: %{public}s', initResult);
      try {
        const parsed = JSON.parse(initResult) as InitCallResult;
        if (parsed.error && parsed.error.length > 0) {
          hilog.error(DOMAIN, TAG, 'Plugin init failed: %{public}s', parsed.error);
          return false;
        }
      } catch {
        // ignore parse error, keep compatibility with non-JSON init responses
      }
    }

    currentPluginId = pluginInfo.id;
    hilog.info(DOMAIN, TAG, 'Plugin loaded to QuickJS successfully');
    return true;
  } catch (e) {
    hilog.error(DOMAIN, TAG, 'Failed to load plugin to QuickJS: %{public}s', formatErrorMessage(e as Object));
    return false;
  }
}

/**
 * 自定义源插件类
 */
export class CustomSourcePlugin implements Plugin {
  id: string;
  name: string;
  description: string;
  version: string;
  author: string;
  homepage: string;
  loaded: boolean = false;
  useQuickJS: boolean = false;
  useScriptApiFallback: boolean = false;
  fallbackApiUrl: string = '';
  fallbackApiKey: string = '';
  scriptContent: string = '';
  private supportedActions: Set<string>;

  constructor(id: string, name: string, description: string, version: string, author: string, homepage: string, scriptContent: string) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.version = version;
    this.author = author;
    this.homepage = homepage;
    this.scriptContent = scriptContent;
    this.supportedActions = parseSupportedActions(scriptContent);
  }

  async onInit(): Promise<boolean> {
    hilog.info(DOMAIN, TAG, 'CustomSourcePlugin initializing: %{public}s', this.name);

    // 初始化 QuickJS
    this.useQuickJS = initQuickJS();
    if (!this.useQuickJS) {
      hilog.warn(DOMAIN, TAG, 'QuickJS unavailable, trying script-api fallback mode');
      const fallbackReady = this.initScriptApiFallback();
      this.loaded = fallbackReady;
      this.useScriptApiFallback = fallbackReady;
      return fallbackReady;
    }

    if (this.useQuickJS) {
      const preloadLoaded = await loadPreloadScript();
      hilog.info(DOMAIN, TAG, 'Preload script load result: %{public}s', preloadLoaded.toString());
      if (!preloadLoaded) {
        hilog.warn(DOMAIN, TAG, 'Failed to load preload script, QuickJS plugin may fail');
      }
      const loaded = loadPluginToQuickJS(this.scriptContent, {
        id: this.id,
        name: this.name,
        description: this.description || '',
        version: this.version || '',
        author: this.author || '',
        homepage: '',
      }, [{
        type: 'custom',
        actions: this.getInitActions(),
        qualitys: ['128k', '320k', 'flac'],
      }]);

      if (loaded) {
        // Keep API fallback as a backup path when QuickJS request returns empty.
        const fallbackReady = this.initScriptApiFallback();
        if (fallbackReady) {
          hilog.info(DOMAIN, TAG, 'Script-api fallback is ready as backup');
        }
        hilog.info(DOMAIN, TAG, 'CustomSourcePlugin initialized with QuickJS: %{public}s', this.name);
        this.loaded = true;
        this.useScriptApiFallback = false;
        return true;
      } else {
        hilog.warn(DOMAIN, TAG, 'QuickJS script load failed, trying script-api fallback mode');
        const fallbackReady = this.initScriptApiFallback();
        this.loaded = fallbackReady;
        this.useQuickJS = false;
        this.useScriptApiFallback = fallbackReady;
        return fallbackReady;
      }
    }

    return false;
  }

  async onSearch(keyword: string, page: number): Promise<PluginSearchResult> {
    if (!this.isActionSupported('search')) {
      return { list: [], total: 0, page };
    }
    if (!this.loaded || !this.useQuickJS) {
      return { list: [], total: 0, page };
    }

    try {
      const result = quickjsRequest('custom', 'search', { keyword, page });
      return {
        list: (result.list || []) as PluginSongInfo[],
        total: result.total || 0,
        page,
      };
    } catch {
      return { list: [], total: 0, page };
    }
  }

  async onGetMusicUrl(songInfo: PluginSongInfo, quality: string): Promise<string> {
    if (!this.isActionSupported('musicUrl')) {
      return '';
    }
    if (!this.loaded) {
      return '';
    }

    if (!this.useQuickJS && this.useScriptApiFallback) {
      return await this.getMusicUrlByScriptApi(songInfo, quality);
    }

    if (!this.useQuickJS) {
      return '';
    }

    try {
      const result = quickjsRequest('custom', 'musicUrl', {
        mid: songInfo.songmid,
        hash: songInfo.hash,
        type: quality,
        musicInfo: songInfo,
      });
      const quickjsUrl = result.url || '';
      if (quickjsUrl.length > 0) {
        return quickjsUrl;
      }
      if (this.fallbackApiUrl.length > 0 && this.fallbackApiKey.length > 0) {
        hilog.warn(DOMAIN, TAG, 'QuickJS returned empty musicUrl, fallback to script-api');
        return await this.getMusicUrlByScriptApi(songInfo, quality);
      }
      return '';
    } catch {
      if (this.fallbackApiUrl.length > 0 && this.fallbackApiKey.length > 0) {
        hilog.warn(DOMAIN, TAG, 'QuickJS musicUrl threw error, fallback to script-api');
        return await this.getMusicUrlByScriptApi(songInfo, quality);
      }
      return '';
    }
  }

  async onGetLyric(songInfo: PluginSongInfo): Promise<PluginLyricInfo> {
    if (!this.isActionSupported('lyric')) {
      return { lyric: '' };
    }
    if (!this.loaded || !this.useQuickJS) {
      return { lyric: '' };
    }

    try {
      const result = quickjsRequest('custom', 'lyric', {
        mid: songInfo.songmid,
        hash: songInfo.hash,
        musicInfo: songInfo,
      });
      return { lyric: result.lyric || '' };
    } catch {
      return { lyric: '' };
    }
  }

  async onGetPic(songInfo: PluginSongInfo): Promise<string> {
    if (!this.isActionSupported('pic')) {
      return '';
    }
    if (!this.loaded || !this.useQuickJS) {
      return '';
    }
    try {
      const result = quickjsRequest('custom', 'pic', {
        mid: songInfo.songmid,
        hash: songInfo.hash,
        musicInfo: songInfo,
      });
      return result.url || result.pic || '';
    } catch {
      return '';
    }
  }

  async onGetSongList(songListId: string, page: number): Promise<PluginSongListResult> {
    if (!this.isActionSupported('songList')) {
      return { list: [], total: 0, page, limit: 20 };
    }
    if (!this.loaded || !this.useQuickJS) {
      return { list: [], total: 0, page, limit: 20 };
    }

    try {
      const result = quickjsRequest('custom', 'songList', { mid: songListId });
      return {
        list: (result.list || []) as PluginSongInfo[],
        total: result.total || 0,
        page,
        limit: 20,
      };
    } catch {
      return { list: [], total: 0, page, limit: 20 };
    }
  }

  async onGetHotSearch(): Promise<PluginHotSearch[]> {
    if (!this.isActionSupported('hotSearch')) {
      return [];
    }
    if (!this.loaded || !this.useQuickJS) {
      return [];
    }

    try {
      const result = quickjsRequest('custom', 'hotSearch', {});
      return (result.list || []) as PluginHotSearch[];
    } catch {
      return [];
    }
  }

  async onGetBoards(): Promise<PluginBoard[]> {
    if (!this.isActionSupported('boards')) {
      return [];
    }
    if (!this.loaded || !this.useQuickJS) {
      return [];
    }
    try {
      const result = quickjsRequest('custom', 'boards', {});
      return (result.list || []) as PluginBoard[];
    } catch {
      return [];
    }
  }

  async onGetBoardList(boardId: string, page: number): Promise<PluginBoardDetail> {
    if (!this.isActionSupported('boardList')) {
      return { name: '', list: [], total: 0, page };
    }
    if (!this.loaded || !this.useQuickJS) {
      return { name: '', list: [], total: 0, page };
    }

    try {
      const result = quickjsRequest('custom', 'boardList', { boardId, page });
      return {
        name: boardId,
        list: (result.list || []) as PluginSongInfo[],
        total: result.total || 0,
        page,
      };
    } catch {
      return { name: '', list: [], total: 0, page };
    }
  }

  setScriptContent(scriptContent: string): void {
    this.scriptContent = scriptContent;
    this.supportedActions = parseSupportedActions(scriptContent);
  }

  async destroy(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'CustomSourcePlugin destroying');

    if (this.useQuickJS) {
      destroyNativeQuickJS();
    }

    this.loaded = false;
    this.useQuickJS = false;
    this.useScriptApiFallback = false;
  }

  private initScriptApiFallback(): boolean {
    try {
      const apiUrlMatch = this.scriptContent.match(/API_URL\s*=\s*['"]([^'"]+)['"]/);
      const apiKeyMatch = this.scriptContent.match(/API_KEY\s*=\s*['"]([^'"]+)['"]/);
      const apiUrl = apiUrlMatch ? apiUrlMatch[1] : '';
      const apiKey = apiKeyMatch ? apiKeyMatch[1] : '';
      if (apiUrl.length === 0 || apiKey.length === 0) {
        hilog.error(DOMAIN, TAG, 'Script-api fallback init failed: missing API_URL/API_KEY');
        return false;
      }
      this.fallbackApiUrl = apiUrl;
      this.fallbackApiKey = apiKey;
      hilog.info(DOMAIN, TAG, 'Script-api fallback enabled: %{public}s', this.fallbackApiUrl);
      return true;
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Script-api fallback init failed: %{public}s', formatErrorMessage(e as Object));
      return false;
    }
  }

  private async getMusicUrlByScriptApi(songInfo: PluginSongInfo, quality: string): Promise<string> {
    try {
      const source = songInfo.source || 'kw';
      const songId = songInfo.hash || songInfo.songmid || '';
      if (songId.length === 0) {
        return '';
      }
      const requestUrl = `${this.fallbackApiUrl}/url/${source}/${songId}/${quality}`;
      const response = await httpRequest(requestUrl, {
        method: 'GET',
        header: {
          'Content-Type': 'application/json',
          'User-Agent': 'lx-music-harmony/1.0.0',
          'X-Request-Key': this.fallbackApiKey,
        },
        responseType: 'text',
      }).promise;

      const raw = response.result;
      const bodyText = typeof raw === 'string' ? raw : JSON.stringify(raw);
      const body = JSON.parse(bodyText) as ScriptApiResponse;
      if (body.code === 0 && body.url && body.url.length > 0) {
        return body.url;
      }
      hilog.error(DOMAIN, TAG, 'Script-api request failed: code=%{public}d, msg=%{public}s', body.code, body.msg || '');
      return '';
    } catch (e) {
      hilog.error(DOMAIN, TAG, 'Script-api request error: %{public}s', formatErrorMessage(e as Object));
      return '';
    }
  }

  private isActionSupported(action: string): boolean {
    return this.supportedActions.has(action);
  }

  private getInitActions(): string[] {
    const orderedActions = ['search', 'musicUrl', 'lyric', 'pic', 'songList', 'hotSearch', 'boards', 'boardList'];
    const actions: string[] = [];
    for (const action of orderedActions) {
      if (this.supportedActions.has(action)) {
        actions.push(action);
      }
    }
    if (actions.length === 0) {
      actions.push('musicUrl');
    }
    return actions;
  }
}
