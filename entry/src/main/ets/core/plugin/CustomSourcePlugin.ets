/**
 * 自定义源插件实现
 * 实现 Plugin 接口，通过 HTTP 模拟 lx.request API 与插件通信
 */
import { httpRequest } from '../network/http';
import hilog from '@ohos.hilog';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import type { Plugin, PluginSongInfo, PluginLyricInfo, PluginSearchResult, PluginSongListResult, PluginBoard, PluginBoardDetail, PluginHotSearch } from './PluginManager';

const TAG = 'CustomSourcePlugin';
const DOMAIN = 0x0001;

// lx API 请求配置
interface LxRequestConfig {
  method?: 'get' | 'post';
  timeout?: number;
  headers?: Record<string, string>;
  body?: string;
  form?: Record<string, string>;
  formData?: Record<string, string>;
}

// lx API 响应
interface LxResponse {
  statusCode: number;
  headers: Record<string, string>;
  body: string | object;
}

// API 模式
interface ApiPattern {
  type: string;
  urlTemplate: string;
  headers: Record<string, string>;
  responsePath: string;
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
  private apiSourceUrl: string = '';
  private scriptContent: string = '';

  constructor(id: string, name: string, description: string, version: string, author: string, homepage: string, apiSourceUrl: string, scriptContent: string) {
    this.id = id;
    this.name = name;
    this.description = description;
    this.version = version;
    this.author = author;
    this.homepage = homepage;
    this.apiSourceUrl = apiSourceUrl;
    this.scriptContent = scriptContent;
  }

  onInit(): Promise<boolean> {
    this.loaded = true;
    hilog.info(DOMAIN, TAG, 'CustomSourcePlugin initialized: %{public}s', this.name);
    return Promise.resolve(true);
  }

  onDestroy?(): void {
    this.loaded = false;
    hilog.info(DOMAIN, TAG, 'CustomSourcePlugin destroyed: %{public}s', this.name);
  }

  isLoaded(): boolean {
    return this.loaded;
  }

  getApiSourceUrl(): string {
    return this.apiSourceUrl;
  }

  getScriptContent(): string {
    return this.scriptContent;
  }

  /**
   * 模拟 lx.request API
   */
  private async lxRequest(url: string, config: LxRequestConfig): Promise<LxResponse> {
    const method = config.method === 'post' ? 'POST' : 'GET';
    const headers = config.headers || {};

    const task = httpRequest(url, {
      method: method,
      header: headers,
      extraData: config.body || config.form,
      timeout: config.timeout || 30000,
    });

    try {
      const response = await task.promise;
      const res: LxResponse = {
        statusCode: response.status,
        headers: response.headers,
        body: response.result as string | object,
      };
      return res;
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'lx.request failed: %{public}s', err.message);
      const errRes: LxResponse = {
        statusCode: 0,
        headers: {},
        body: '',
      };
      return errRes;
    }
  }

  /**
   * 处理音乐 URL 请求
   */
  private async handleGetMusicUrl(songInfo: PluginSongInfo, quality: string): Promise<string> {
    hilog.info(DOMAIN, TAG, 'CustomSource getMusicUrl: %{public}s quality: %{public}s', songInfo.name, quality);

    if (!this.scriptContent || this.scriptContent.length === 0) {
      hilog.warn(DOMAIN, TAG, 'No plugin script, falling back to built-in source');
      return '';
    }

    try {
      const mid = songInfo.songmid || '';
      const hash = songInfo.hash || '';

      const apiPatterns = this.extractApiPatterns();

      for (let i = 0; i < apiPatterns.length; i++) {
        const pattern = apiPatterns[i];
        if (pattern.type === 'musicUrl') {
          const params: Record<string, string> = {} as Record<string, string>;
          params['mid'] = mid;
          params['hash'] = hash;
          params['quality'] = quality;
          const url = this.buildUrlFromPattern(pattern.urlTemplate, params);
          if (url && url.length > 0) {
            const response = await this.lxRequest(url, { method: 'get', headers: pattern.headers });
            const musicUrl = this.parseMusicUrlResponse(response.body, pattern.responsePath);
            if (musicUrl && musicUrl.length > 0) {
              return musicUrl;
            }
          }
        }
      }

      return '';
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'getMusicUrl error: %{public}s', (error as Error).message);
      return '';
    }
  }

  /**
   * 从脚本内容中提取 API 模式
   */
  private extractApiPatterns(): ApiPattern[] {
    const patterns: ApiPattern[] = [];
    const script = this.scriptContent;

    const urlPattern = /["'](https?:\/\/[^"']+(?:music|url|song)[^"']*)["']/gi;
    let match = urlPattern.exec(script);
    while (match !== null) {
      const url = match[1];
      if (url.startsWith('http')) {
        const pattern: ApiPattern = {
          type: 'musicUrl',
          urlTemplate: url,
          headers: { 'Referer': 'https://example.com', 'User-Agent': 'Mozilla/5.0' },
          responsePath: 'url',
        };
        patterns.push(pattern);
      }
      match = urlPattern.exec(script);
    }

    return patterns;
  }

  /**
   * 从 URL 模式构建完整 URL
   */
  private buildUrlFromPattern(template: string, params: Record<string, string>): string {
    let url = template;
    const paramKeys = Object.keys(params);
    for (let i = 0; i < paramKeys.length; i++) {
      const key = paramKeys[i];
      const value = params[key];
      const encodedValue = encodeURIComponent(value);
      url = url.replace(new RegExp('\\$\\{' + key + '\\}', 'g'), encodedValue);
      url = url.replace(new RegExp(':' + key, 'g'), encodedValue);
    }
    return url;
  }

  /**
   * 解析音乐 URL 响应
   */
  private parseMusicUrlResponse(body: string | object, responsePath: string): string {
    try {
      let data: Record<string, object> = {};
      if (typeof body === 'string') {
        data = JSON.parse(body) as Record<string, object>;
      } else {
        data = body as Record<string, object>;
      }

      const pathParts = responsePath.split('.');
      let result: object = data;
      for (let i = 0; i < pathParts.length; i++) {
        const part = pathParts[i];
        const nested = result as Record<string, object>;
        const fallback: Record<string, object> = {};
        result = nested[part] || fallback;
      }
      return String(result);
    } catch {
      return '';
    }
  }

  /**
   * 处理歌词请求
   */
  private handleGetLyricImpl(songInfo: PluginSongInfo): PluginLyricInfo {
    hilog.info(DOMAIN, TAG, 'CustomSource getLyric: %{public}s', songInfo.name);
    const result: PluginLyricInfo = { lyric: '' };
    return result;
  }

  /**
   * 处理搜索请求
   */
  private handleSearchImpl(keyword: string, page: number): PluginSearchResult {
    hilog.info(DOMAIN, TAG, 'CustomSource search: %{public}s page: %{public}d', keyword, page);
    const result: PluginSearchResult = { list: [], total: 0, page: page };
    return result;
  }

  // ==================== Plugin 接口实现 ====================

  onGetMusicUrl(songInfo: PluginSongInfo, quality: string): Promise<string> {
    return this.handleGetMusicUrl(songInfo, quality);
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
    hilog.info(DOMAIN, TAG, 'CustomSource getSongList');
    const result: PluginSongListResult = { list: [], total: 0, page: page, limit: 20 };
    return Promise.resolve(result);
  }

  onGetBoards(): Promise<PluginBoard[]> {
    hilog.info(DOMAIN, TAG, 'CustomSource getBoards');
    return Promise.resolve([]);
  }

  onGetBoardList(boardId: string, page: number): Promise<PluginBoardDetail> {
    hilog.info(DOMAIN, TAG, 'CustomSource getBoardList');
    const result: PluginBoardDetail = { name: '', list: [], total: 0, page: page };
    return Promise.resolve(result);
  }

  onGetHotSearch(): Promise<PluginHotSearch[]> {
    hilog.info(DOMAIN, TAG, 'CustomSource getHotSearch');
    return Promise.resolve([]);
  }
}
