// 内置源枚举、插件桥接、跨源搜索等（对外经 MusicFeatureEntry 再导出）

// 内置源：经根目录 MusicSourceFactory 统一创建
import { MusicSourceFactory } from './MusicSourceRegistry';
// 导入插件系统
import { pluginManager, PluginSongInfo as PluginSongInfoFromPlugin } from '../plugin/PluginManager';
import { getStorageService } from '../interfaces/IStorageService';

const _musicFactory = MusicSourceFactory.getInstance();
const kw = _musicFactory.getSdk('kw');
const kg = _musicFactory.getSdk('kg');
const tx = _musicFactory.getSdk('tx');
const wy = _musicFactory.getSdk('wy');
const mg = _musicFactory.getSdk('mg');

// 音乐源类型枚举
export enum MusicSource {
  KW = 'kw',
  KG = 'kg',
  TX = 'tx',
  WY = 'wy',
  MG = 'mg',
  XM = 'xm',
  CUSTOM = 'custom'  // 自定义源
}

// 音乐源信息
export interface SourceInfo {
  name: string;
  id: MusicSource;
  builtIn: boolean;  // 是否是内置源
}

// 音乐源列表
export const sources: SourceInfo[] = [
  { name: '酷我音乐', id: MusicSource.KW, builtIn: true },
  { name: '酷狗音乐', id: MusicSource.KG, builtIn: true },
  { name: 'QQ音乐', id: MusicSource.TX, builtIn: true },
  { name: '网易音乐', id: MusicSource.WY, builtIn: true },
  { name: '咪咕音乐', id: MusicSource.MG, builtIn: true },
];

// 搜索结果项
export interface SearchResultItem {
  id: string;
  name: string;
  singer: string;
  album: string;
  albumId: string | null;
  duration: number;
  interval: string | null;
  source: MusicSource;
  pic: string | null;
  lrc: string | null;
}

// 搜索结果
export interface SearchResult {
  list: SearchResultItem[];
  source: MusicSource;
}

// 歌词信息
export interface LyricResult {
  lyric: string;
  tlyric: string | null;
  lxlyric: string | null;
  rlyric: string | null;
}

// 歌曲详情
export interface SongDetail {
  name: string;
  singer: string;
  album: string;
  pic: string;
  interval: string | null;
}

// 歌单项
export interface SonglistItem {
  id: string;
  name: string;
  desc: string;
  pic: string;
  source: MusicSource;
  playCount: number;
  author: string;
}

// 歌单搜索结果
export interface SonglistResult {
  list: SonglistItem[];
  source: MusicSource;
  page: number;
  total: number;
}

// 排行榜项
export interface LeaderboardItem {
  id: string;
  name: string;
  source: MusicSource;
  description: string | null;
  pic: string | null;
  playCount: number | null;
}

// 排行榜结果
export interface LeaderboardResult {
  list: LeaderboardItem[];
  source: MusicSource;
}

// 热搜项
export interface HotSearchItem {
  index: number;
  title: string;
  source: MusicSource;
  url: string | null;
  hot: number | null;
}

// 音乐搜索接口
export interface MusicSearchInterface {
  search: (keyword: string, page: number | null, limit: number | null) => Promise<SearchResult>;
}

// 音乐URL结果接口
export interface MusicUrlResult {
  url: string;
  type: string;
}

// 获取歌曲播放链接接口
export interface GetMusicUrlInterface {
  call: (songInfo: SongInfo, quality: string) => Promise<MusicUrlResult>;
}

// 获取歌词接口
export interface GetLyricInterface {
  call: (songInfo: SongInfo) => Promise<LyricResult>;
}

// 获取封面接口
export interface GetPicInterface {
  call: (songInfo: SongInfo) => Promise<string>;
}

// 歌单接口
export interface SongListInterface {
  search: (keyword: string, page: number | null, limit: number | null) => Promise<SonglistResult>;
  getInfo: (id: string) => Promise<SonglistDetail>;
}

// 排行榜接口
export interface LeaderboardInterface {
  list: () => Promise<LeaderboardResult>;
  getInfo: (id: string) => Promise<SonglistDetail>;
}

// 热搜接口
export interface HotSearchInterface {
  list: () => Promise<HotSearchItem[]>;
}

// 音乐源SDK接口
export interface MusicSourceSDK {
  // 初始化（可选，各音乐源不一定实现）
  init?: () => Promise<void>;

  // 音乐搜索
  musicSearch: MusicSearchInterface;

  // 获取歌曲播放链接
  getMusicUrl: GetMusicUrlInterface;

  // 获取歌词
  getLyric: GetLyricInterface;

  // 获取封面
  getPic: GetPicInterface;

  // 歌单搜索
  songList: SongListInterface | null;

  // 排行榜
  leaderboard: LeaderboardInterface | null;

  // 热搜
  hotSearch: HotSearchInterface | null;
}

// 跨源搜索使用的最小接口（不包含init等可选属性）
interface CrossSourceSDK {
  musicSearch: MusicSearchInterface;
}

// 各源 SDK 结构满足 CrossSourceSDK，此处做显式断言以满足 ArkTS 名义类型检查
function toCrossSource(sdk: object): CrossSourceSDK {
  return sdk as CrossSourceSDK;
}

// 歌曲信息（用于API调用）
export interface SongInfo {
  songmid: string;
  name: string;
  singer: string;
  albumName: string | null;
  interval: string | null;
}

// 歌单详情
export interface SonglistDetail {
  id: string;
  name: string;
  desc: string;
  pic: string;
  author: string;
  playCount: number;
  total: number;
  list: SearchResultItem[];
}

// 全局音乐SDK对象
export interface MusicSDK {
  sources: SourceInfo[];
  kw: MusicSourceSDK;
  kg: MusicSourceSDK;
  tx: MusicSourceSDK;
  wy: MusicSourceSDK;
  mg: MusicSourceSDK;
  xm: MusicSourceSDK;
  supportQuality: string[];
}

// 导出支持的品质
export const supportQuality = ['flac24bit', 'flac', '320k', '192k', '128k', '96k', '64k', '32k'];

// 初始化SDK
export async function initMusicSDK(): Promise<void> {
  // 对应安卓源码: src/utils/musicSdk/index.js -> init()
  // 各音乐源SDK在导入时已就绪，无需额外初始化
}

// 搜索参数接口
interface SearchMusicParams {
  name: string;
  singer: string | null;
  source: MusicSource | null;
  limit: number | null;
}

// 搜索音乐（跨源）
// 对应安卓源码: src/utils/musicSdk/index.js -> searchMusic
export async function searchMusic(params: SearchMusicParams): Promise<SearchResult[]> {
  const name = params.name;
  const singer = params.singer;
  const source = params.source;
  const limit = params.limit ?? 25;
  const trimStr = (str: string | null): string => str ? str.trim() : '';
  const musicName = trimStr(name);
  const searchKeyword = `${musicName} ${trimStr(singer)}`.trim();

  const excludeSource: MusicSource[] = [MusicSource.XM];
  const tasks: Promise<SearchResult | null>[] = [];

  // 逐个处理每个源，使用最小接口避免类型推断问题
  const checkAndSearch = async (id: MusicSource, srcSdk: CrossSourceSDK): Promise<SearchResult | null> => {
    if (id === source || excludeSource.indexOf(id) !== -1) return null;
    if (!srcSdk.musicSearch) return null;
    const searchResult: SearchResultItem[] = await srcSdk.musicSearch.search(searchKeyword, 1, limit).then(res => res.list).catch(() => []);
    if (searchResult.length === 0) return null;
    const mergedResult: SearchResult = {
      list: searchResult,
      source: id,
    };
    return mergedResult;
  };

  tasks.push(checkAndSearch(MusicSource.KW, toCrossSource(kw)));
  tasks.push(checkAndSearch(MusicSource.KG, toCrossSource(kg)));
  tasks.push(checkAndSearch(MusicSource.TX, toCrossSource(tx)));
  tasks.push(checkAndSearch(MusicSource.WY, toCrossSource(wy)));
  tasks.push(checkAndSearch(MusicSource.MG, toCrossSource(mg)));

  const results: (SearchResult | null)[] = await Promise.all(tasks);
  const filtered: SearchResult[] = [];
  for (let i = 0; i < results.length; i++) {
    if (results[i] !== null) {
      filtered.push(results[i]!);
    }
  }
  return filtered;
}

// 查找音乐参数接口
interface FindMusicParams {
  name: string;
  singer: string;
  albumName: string | null;
  interval: string | null;
  source: MusicSource | null;
}

// 查找音乐（跨源）
// 对应安卓源码: src/utils/musicSdk/index.js -> findMusic
export async function findMusic(params: FindMusicParams): Promise<SearchResultItem[]> {
  const name: string = params.name;
  const singer: string = params.singer;
  const albumName: string | null = params.albumName;
  const interval: string | null = params.interval;
  const s: MusicSource | null = params.source;
  const lists: SearchResult[] = await searchMusic({ name, singer, source: s, limit: 25 });

  const singersRxp = /、|&|;|；|\/|,|，|\|/;
  const sortSingle = (singer: string): string =>
    singersRxp.test(singer)
      ? singer.split(singersRxp).sort((a, b) => a.localeCompare(b)).join('、')
      : (singer || '');

  const filterStr = (str: string | null): string =>
    typeof str === 'string' ? str.replace(/\s|'|\.|,|，|&|"|、|\(|\)|（|）|`|~|-|<|>|\||\/|\]|\[|!|！/g, '') : String(str || '');

  const getIntv = (interval: string | null): number => {
    if (!interval) return 0;
    const intvArr = interval.split(':');
    let intv = 0;
    let unit = 1;
    while (intvArr.length > 0) {
      intv += parseInt(intvArr.pop() || '0') * unit;
      unit *= 60;
    }
    return intv;
  };

  const trimStr = (str: string | null): string => typeof str === 'string' ? str.trim() : (str || '');
  const fMusicName = filterStr(name).toLowerCase();
  const fSinger = filterStr(sortSingle(singer)).toLowerCase();
  const fAlbumName = filterStr(albumName).toLowerCase();
  const fInterval = getIntv(interval);
  const isEqualsInterval = (intv: number): boolean => Math.abs((fInterval || intv) - (intv || fInterval)) < 5;
  const isIncludesName = (name: string): boolean => (fMusicName.includes(name) || name.includes(fMusicName));
  const isIncludesSinger = (singer: string): boolean => fSinger ? (fSinger.includes(singer) || singer.includes(fSinger)) : true;
  const isEqualsAlbum = (album: string): boolean => fAlbumName ? fAlbumName === album : true;

  const sortMusic = (arr: SearchResultItem[], callback: (item: SearchResultItem) => boolean): SearchResultItem[] => {
    const tempResult: SearchResultItem[] = [];
    for (let i = arr.length - 1; i > -1; i--) {
      const item = arr[i];
      if (callback(item)) {
        tempResult.push(item);
        arr.splice(i, 1);
      }
    }
    tempResult.reverse();
    return tempResult;
  };

  // 收集各源匹配结果
  const result: SearchResultItem[] = [];
  for (const srcResult of lists) {
    let matched: SearchResultItem | null = null;
    for (const item of srcResult.list) {
      const itemMusicName = filterStr(trimStr(item.name)).toLowerCase();
      const itemSinger = filterStr(sortSingle(trimStr(item.singer))).toLowerCase();
      const itemAlbum = filterStr(trimStr(item.album)).toLowerCase();
      const itemInterval = getIntv(item.interval);

      if (!isEqualsInterval(itemInterval)) continue;
      if (itemMusicName === fMusicName && isIncludesSinger(itemSinger)) {
        matched = item;
        break;
      }
    }
    if (!matched) {
      for (const item of srcResult.list) {
        const itemMusicName = filterStr(trimStr(item.name)).toLowerCase();
        const itemSinger = filterStr(sortSingle(trimStr(item.singer))).toLowerCase();
        if (itemSinger === fSinger && isIncludesName(itemMusicName)) {
          matched = item;
          break;
        }
      }
    }
    if (!matched) {
      for (const item of srcResult.list) {
        const itemMusicName = filterStr(trimStr(item.name)).toLowerCase();
        const itemSinger = filterStr(sortSingle(trimStr(item.singer))).toLowerCase();
        const itemAlbum = filterStr(trimStr(item.album)).toLowerCase();
        const itemInterval = getIntv(item.interval);
        if (isEqualsAlbum(itemAlbum) && isIncludesSinger(itemSinger) && isIncludesName(itemMusicName)) {
          matched = item;
          break;
        }
      }
    }
    if (matched) result.push(matched);
  }

  const newResult: SearchResultItem[] = [];
  if (result.length > 0) {
    const sort1: SearchResultItem[] = sortMusic(result, item => {
      const itemSinger = filterStr(sortSingle(trimStr(item.singer))).toLowerCase();
      const itemMusicName = filterStr(trimStr(item.name)).toLowerCase();
      return itemSinger === fSinger && itemMusicName === fMusicName && item.interval === interval;
    });
    for (let i = 0; i < sort1.length; i++) { newResult.push(sort1[i]); }
    const sort2: SearchResultItem[] = sortMusic(result, item => {
      const itemSinger = filterStr(sortSingle(trimStr(item.singer))).toLowerCase();
      const itemMusicName = filterStr(trimStr(item.name)).toLowerCase();
      const itemAlbum = filterStr(trimStr(item.album)).toLowerCase();
      return itemMusicName === fMusicName && itemSinger === fSinger && itemAlbum === fAlbumName;
    });
    for (let i = 0; i < sort2.length; i++) { newResult.push(sort2[i]); }
    const sort3: SearchResultItem[] = sortMusic(result, item => {
      const itemSinger = filterStr(sortSingle(trimStr(item.singer))).toLowerCase();
      const itemMusicName = filterStr(trimStr(item.name)).toLowerCase();
      return itemSinger === fSinger && itemMusicName === fMusicName;
    });
    for (let i = 0; i < sort3.length; i++) { newResult.push(sort3[i]); }
    const sort4: SearchResultItem[] = sortMusic(result, item => {
      const itemMusicName = filterStr(trimStr(item.name)).toLowerCase();
      return itemMusicName === fMusicName && item.interval === interval;
    });
    for (let i = 0; i < sort4.length; i++) { newResult.push(sort4[i]); }
    const sort5: SearchResultItem[] = sortMusic(result, item => {
      const itemSinger = filterStr(sortSingle(trimStr(item.singer))).toLowerCase();
      return itemSinger === fSinger && item.interval === interval;
    });
    for (let i = 0; i < sort5.length; i++) { newResult.push(sort5[i]); }
    const sort6: SearchResultItem[] = sortMusic(result, item => item.interval === interval);
    for (let i = 0; i < sort6.length; i++) { newResult.push(sort6[i]); }
    const sort7: SearchResultItem[] = sortMusic(result, item => {
      const itemMusicName = filterStr(trimStr(item.name)).toLowerCase();
      return itemMusicName === fMusicName;
    });
    for (let i = 0; i < sort7.length; i++) { newResult.push(sort7[i]); }
    const sort8: SearchResultItem[] = sortMusic(result, item => {
      const itemSinger = filterStr(sortSingle(trimStr(item.singer))).toLowerCase();
      return itemSinger === fSinger;
    });
    for (let i = 0; i < sort8.length; i++) { newResult.push(sort8[i]); }
    const sort9: SearchResultItem[] = sortMusic(result, item => {
      const itemAlbum = filterStr(trimStr(item.album)).toLowerCase();
      return itemAlbum === fAlbumName;
    });
    for (let i = 0; i < sort9.length; i++) { newResult.push(sort9[i]); }
    for (let i = 0; i < result.length; i++) { newResult.push(result[i]); }
  }
  return newResult;
}

// ============================================
// 插件系统相关接口
// ============================================

// 插件API源信息
export interface PluginApiSourceInfo {
  source: MusicSource;
  actions: string[];
  qualitys: string[];
}

// 插件初始化信息
export interface PluginInitInfo {
  sources: Record<string, PluginApiSourceInfo>;
}

/**
 * 获取插件系统实例
 */
export function getPluginSystem() {
  return pluginManager;
}

/**
 * 检查是否使用自定义源
 */
export function isUsingCustomSource(): boolean {
  return pluginManager.isLoaded();
}

/**
 * 获取当前使用的音乐源
 */
export async function getCurrentSource(): Promise<MusicSource> {
  const source = await getStorageService().getString('plugin.currentSource', 'kw');
  return source as MusicSource;
}

/**
 * 加载自定义源插件
 * @param url JS源文件URL
 */
export async function loadCustomSource(url: string): Promise<boolean> {
  return await pluginManager.loadCustomSource(url);
}

/** 启动时恢复「上次启用的自定义源」（含多源列表） */
export async function restoreEnabledCustomSource(): Promise<boolean> {
  return await pluginManager.restoreEnabledSource();
}

/**
 * 卸载自定义源插件
 */
export function unloadCustomSource(): void {
  pluginManager.unloadPlugin();
}

// 插件信息返回类型
export interface PluginInfoResult {
  id: string;
  name: string;
  version: string;
  author: string;
}

/**
 * 获取插件信息
 */
export function getPluginInfo(): PluginInfoResult | null {
  const info = pluginManager.getPluginInfo();
  if (!info) return null;
  const result: PluginInfoResult = {
    id: info.id,
    name: info.name,
    version: info.version,
    author: info.author,
  };
  return result;
}

/**
 * 通过插件获取音乐URL
 * @param songInfo 歌曲信息
 * @param quality 音质
 */
export async function getMusicUrlByPlugin(songInfo: SongInfo, quality: string): Promise<string> {
  const pluginSongInfo: PluginSongInfoFromPlugin = {
    songmid: songInfo.songmid,
    name: songInfo.name,
    singer: songInfo.singer,
    source: 'kw',
    albumName: '',
    albumId: '',
    duration: '',
    hash: '',
  };
  const plugin = pluginManager.getActivePlugin();
  if (plugin && plugin.onGetMusicUrl) {
    return await plugin.onGetMusicUrl(pluginSongInfo, quality);
  }
  return '';
}
