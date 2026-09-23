/**
 * 酷狗音乐 - 歌单
 */
import { httpRequest, type HttpRequestConfig } from '../../../../core/network/http';
import { formatPlayCount, formatPlayTime, sizeFormate } from '../../../../utils/CommonUtils';
import { signatureParams } from './util';
import type { MusicInfo, MusicQualityTypeKg, Quality, QualityDetail } from '../../../../types/MusicTypes';
import { parseKgHttpJson } from './kgHttpJson';
// 歌单标签/信息/结果形状各音源一致，统一在 MusicSdkContracts 声明
import type {
  SongListTag,
  SongListTagsResult,
  SongListInfo,
  SongListResult,
  SongListDetailInfo,
  SongListDetailResult,
} from '../MusicSdkContracts';


// 排序项
interface SortItem {
  name: string;
  tid: string;
  id: string;
}

// 排序类型
const sortList: SortItem[] = [
  { name: '推荐', tid: 'recommend', id: '5' },
  { name: '最热', tid: 'hot', id: '6' },
  { name: '最新', tid: 'new', id: '7' },
  { name: '热藏', tid: 'hot_collect', id: '3' },
  { name: '飙升', tid: 'rise', id: '8' },
];

// 与安卓 songList.js getInfoUrl 一致
function getInfoUrl(tagId: string): string {
  return tagId && tagId.length > 0
    ? `http://www2.kugou.kugou.com/yueku/v9/special/getSpecial?is_smarty=1&cdn=cdn&t=5&c=${tagId}`
    : 'http://www2.kugou.kugou.com/yueku/v9/special/getSpecial?is_smarty=1&cdn=cdn&';
}

function formatKgPublishDate(ts: number): string {
  if (!ts || ts <= 0) {
    return '';
  }
  const sec = ts > 1e12 ? Math.floor(ts / 1000) : ts;
  const d = new Date(sec * 1000);
  const y = d.getFullYear();
  const m = d.getMonth() + 1;
  const day = d.getDate();
  const ms = m < 10 ? `0${m}` : `${m}`;
  const ds = day < 10 ? `0${day}` : `${day}`;
  return `${y}-${ms}-${ds}`;
}

interface KgListInfoMeta {
  limit: number;
  page: number;
  total: number;
  source: string;
}

let kgCachedListInfoTagId: string = '';
let kgCachedListInfo: KgListInfoMeta | null = null;

// 获取歌单列表URL
function getSongListUrl(sortId: string, tagId: string, page: number): string {
  const c = tagId ?? '';
  return `http://www2.kugou.kugou.com/yueku/v9/special/getSpecial?is_ajax=1&cdn=cdn&t=${sortId}&c=${c}&p=${page}`;
}

// 歌单详情URL
function getSongListDetailUrl(id: string): string {
  return `http://www2.kugou.kugou.com/yueku/v9/special/single/${id}-5-9999.html`;
}

const KG_REGEXP_LIST_DATA: RegExp = /global\.data\s*=\s*(\[[\s\S]+\]);/;
const KG_REGEXP_LIST_INFO: RegExp = /global\s*=\s*\{[\s\S]+?name:\s*"(.+?)"[\s\S]+?pic:\s*"(.+?)"[\s\S]+?\};/;
const KG_DESC_PREFIX = '<div class="pc_specail_text pc_singer_tab_content" id="specailIntroduceWrap">';

function toResponseText(raw: string | Object): string {
  if (typeof raw === 'string') {
    return raw;
  }
  try {
    return JSON.stringify(raw);
  } catch (_e) {
    return '';
  }
}

function parseHtmlDesc(html: string): string {
  const idx = html.indexOf(KG_DESC_PREFIX);
  if (idx < 0) {
    return '';
  }
  const after = html.substring(idx + KG_DESC_PREFIX.length);
  const end = after.indexOf('</div>');
  if (end < 0) {
    return '';
  }
  return decodeName(after.substring(0, end));
}

function isPureHttpUrl(text: string): boolean {
  const t = text.trim();
  if (!/^https?:\/\//.test(t)) {
    return false;
  }
  return t.indexOf('\n') < 0 && t.indexOf('<') < 0 && t.indexOf('{') < 0;
}

function extractRedirectUrlFromHtml(html: string): string {
  const patterns: RegExp[] = [
    /location\.href\s*=\s*['"]([^'"]+)['"]/i,
    /window\.location\s*=\s*['"]([^'"]+)['"]/i,
    /window\.open\(\s*['"]([^'"]+)['"]/i,
    /url=([^"'\s>]+)/i,
  ];
  for (let i = 0; i < patterns.length; i++) {
    const m = html.match(patterns[i]);
    if (m && m[1]) {
      return decodeURIComponent(m[1].trim());
    }
  }
  return '';
}

async function fetchKgSongListDetailHtml(url: string): Promise<string> {
  const req: HttpRequestConfig = {
    header: songListHeaders,
    responseType: 'text',
  };
  const response = await httpRequest(url, req).promise;
  let body = toResponseText(response.result as string | Object);
  const trimmed = body.trim();
  if (isPureHttpUrl(trimmed)) {
    const next = await httpRequest(trimmed, req).promise;
    body = toResponseText(next.result as string | Object);
    return body;
  }
  const redirectUrl = extractRedirectUrlFromHtml(body);
  if (redirectUrl.length > 0 && redirectUrl !== url) {
    const next = await httpRequest(redirectUrl, req).promise;
    body = toResponseText(next.result as string | Object);
  }
  return body;
}

// 热门标签项
interface HotTagItem {
  special_id: string;
  special_name: string;
}

// 分类标签项
interface TagCategoryItem {
  parent_id: number;
  pname: string;
  id: string;
  name: string;
}

interface KgHotTagWrapper {
  status: number;
  data: Record<string, HotTagItem>;
}

interface KgTagidsGroup {
  data: TagCategoryItem[];
}

interface KgTagsDataBody {
  hotTag: KgHotTagWrapper;
  tagids: Record<string, KgTagidsGroup>;
}

interface KgTagsRoot {
  status: number;
  data: KgTagsDataBody;
}

interface KgListParamsBlock {
  pagesize?: number;
  p?: number;
  total?: number;
}

interface KgListParamsData {
  params?: KgListParamsBlock;
}

interface KgListParamsBody {
  status: number;
  data?: KgListParamsData;
}

// 标签列表项
interface TagListItem {
  parent_id: number;
  parent_name: string;
  id: string;
  name: string;
  source: string;
}

function buildKgSongListHeaderMap(): Map<string, string> {
  const m: Map<string, string> = new Map();
  m.set('Referer', 'https://m3ws.kugou.com/share/index.php');
  m.set(
    'User-Agent',
    'Mozilla/5.0 (iPhone; CPU iPhone OS 11_0 like Mac OS X) AppleWebKit/604.1.38 (KHTML, like Gecko) Version/11.0 Mobile/15A372 Safari/604.1'
  );
  return m;
}

const songListHeaders: Map<string, string> = buildKgSongListHeaderMap();

// 原始歌单列表项
interface RawSongListItem {
  specialid: string;
  nickname: string;
  specialname: string;
  publish_time: number;
  publishtime?: number;
  img: string;
  imgurl: string;
  songcount: number;
  grade: number;
  intro: string;
  play_count: number;
  total_play_count?: number;
}

interface KgRecommendData {
  special_list?: RawSongListItem[];
}

interface KgRecommendBody {
  status: number;
  data?: KgRecommendData;
}

interface KgRecommendPostBody {
  appid: number;
  clienttime: number;
  clientver: number;
  key: string;
  mid: string;
  platform: string;
  userid: string;
  return_min: number;
  return_max: number;
}

// 歌单列表响应
interface KGSongListResponse {
  status: number;
  special_db: RawSongListItem[];
}

// 歌单信息响应
interface KGListInfoResponse {
  specialname: string;
  imgurl: string;
  intro: string;
  songcount: number;
}

// 酷狗歌曲原始数据（歌单详情页 - HTML提取的简化数据）
interface KGSongRawItem {
  hash?: string;
  songname?: string;
  singername?: string;
  album_name?: string;
  album_id?: string;
  duration?: number;
  img?: string;
  lyrics?: string;
}

// 批量获取歌曲信息的请求体
interface KGMusicBatchRequest {
  area_code: string;
  show_privilege: number;
  show_album_info: string;
  is_publish: string;
  appid: number;
  clientver: number;
  mid: string;
  dfid: string;
  clienttime: number;
  key: string;
  fields: string;
  data: string[];
}

// 批量获取歌曲信息的响应
interface KGMusicBatchResponse {
  data: KGMusicBatchItem[];
}

// 专辑信息
interface KGAlbumInfo {
  album_name: string;
  album_id: string;
}

// 音频信息
interface KGAudioInfo {
  audio_id: string;
  hash: string;
  filesize: string;
  filesize_320: string;
  filesize_flac: string;
  filesize_high: string;
  hash_320: string;
  hash_flac: string;
  hash_high: string;
  timelength: string;
}

interface KGMusicBatchItem {
  author_name: string;
  songname: string;
  album_info: KGAlbumInfo;
  audio_info: KGAudioInfo;
}

// 创建批量获取任务
function createBatchTasks(hashes: string[]): KGMusicBatchRequest[] {
  const data: KGMusicBatchRequest = {
    area_code: '1',
    show_privilege: 1,
    show_album_info: '1',
    is_publish: '',
    appid: 1005,
    clientver: 11451,
    mid: '1',
    dfid: '-',
    clienttime: Date.now(),
    key: 'OIlwieks28dk2k092lksi2UIkp',
    fields: 'album_info,author_name,audio_info,ori_audio_name,base,songname',
    data: hashes,
  };
  return [data];
}

// 批量获取歌曲详细信息
async function getMusicInfosFromAPI(hashes: string[]): Promise<KGMusicBatchItem[]> {
  if (hashes.length === 0) return [];

  const tasks = createBatchTasks(hashes);
  const results: KGMusicBatchItem[] = [];

  for (const task of tasks) {
    try {
      const url = 'http://gateway.kugou.com/v2/album_audio/audio';
      const postHeader: Map<string, string> = new Map();
      postHeader.set('KG-THash', '13a3164');
      postHeader.set('KG-RC', '1');
      postHeader.set('KG-Fake', '0');
      postHeader.set('KG-RF', '00869891');
      postHeader.set('User-Agent', 'Android712-AndroidPhone-11451-376-0-FeeCacheUpdate-wifi');
      postHeader.set('x-router', 'kmr.service.kugou.com');
      const batchReq: HttpRequestConfig = {
        method: 'POST',
        header: postHeader,
        extraData: task,
      };
      const response = await httpRequest(url, batchReq).promise;

      const body = parseKgHttpJson<KGMusicBatchResponse>(response.result as string | Object);
      if (body && body.data) {
        results.push(...body.data);
      }
    } catch (e) {
      // 忽略错误
    }
  }

  return results;
}

// 去重
function deDuplication(items: KGSongRawItem[]): KGSongRawItem[] {
  const ids = new Set<string>();
  return items.filter(item => {
    if (!item.hash) return false;
    if (ids.has(item.hash)) return false;
    ids.add(item.hash);
    return true;
  });
}

// 解析批量获取的歌曲数据
function filterBatchMusicData(rawList: KGMusicBatchItem[]): MusicInfo[] {
  const result: MusicInfo[] = [];
  const ids = new Set<string>();

  for (let i = 0; i < rawList.length; i++) {
    const item = rawList[i];
    if (!item || !item.audio_info) continue;

    const audioId = item.audio_info.audio_id;
    if (ids.has(audioId)) continue;
    ids.add(audioId);

    const types: MusicQualityTypeKg[] = [];
    const _types = new Map<Quality, QualityDetail>();

    // 128k
    if (item.audio_info.filesize && item.audio_info.filesize !== '0') {
      const size = sizeFormate(parseInt(item.audio_info.filesize));
      types.push({ type: '128k', size, hash: item.audio_info.hash });
      _types.set('128k', { size });
    }
    // 320k
    if (item.audio_info.filesize_320 && item.audio_info.filesize_320 !== '0') {
      const size = sizeFormate(parseInt(item.audio_info.filesize_320));
      types.push({ type: '320k', size, hash: item.audio_info.hash_320 });
      _types.set('320k', { size });
    }
    // flac
    if (item.audio_info.filesize_flac && item.audio_info.filesize_flac !== '0') {
      const size = sizeFormate(parseInt(item.audio_info.filesize_flac));
      types.push({ type: 'flac', size, hash: item.audio_info.hash_flac });
      _types.set('flac', { size });
    }
    // flac24bit
    if (item.audio_info.filesize_high && item.audio_info.filesize_high !== '0') {
      const size = sizeFormate(parseInt(item.audio_info.filesize_high));
      types.push({ type: 'flac24bit', size, hash: item.audio_info.hash_high });
      _types.set('flac24bit', { size });
    }

    const musicInfo: MusicInfo = {
      name: decodeName(item.songname),
      singer: decodeName(item.author_name),
      source: 'kg',
      songmid: audioId,
      albumId: item.album_info.album_id,
      interval: formatPlayTime(parseInt(item.audio_info.timelength) / 1000),
      albumName: decodeName(item.album_info.album_name),
      img: null,
      lrc: null,
      hash: item.audio_info.hash,
      types,
      _types,
      typeUrl: new Map(),
      otherSource: null,
    };
    result.push(musicInfo);
  }
  return result;
}

// 解码歌名/歌手名（简单的HTML实体解码）
function decodeName(name: string | undefined): string {
  if (!name) return '';
  return name
    .replace(/&#(\d+);/g, (_match: string, dec: string) => String.fromCharCode(parseInt(dec)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_match: string, hex: string) => String.fromCharCode(parseInt(hex, 16)))
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'");
}

// 解析HTML中的歌曲数据（简化版本）
function parseHtmlSongList(body: string): KGSongRawItem[] {
  const result: KGSongRawItem[] = [];

  try {
    // 方法1: global.data = [...]
    const match1 = body.match(KG_REGEXP_LIST_DATA);
    if (match1 && match1[1]) {
      const data: KGSongRawItem[] = JSON.parse(match1[1]);
      if (Array.isArray(data) && data.length > 0) {
        return data;
      }
    }

    // 方法2: data = [...]
    const match2 = body.match(/data\s*=\s*(\[[\s\S]+\]);/);
    if (match2 && match2[1]) {
      const data: KGSongRawItem[] = JSON.parse(match2[1]);
      if (Array.isArray(data) && data.length > 0) {
        return data;
      }
    }

    // 方法3: 尝试从window.__INITIAL_DATA__中解析
    const match3 = body.match(/window\.__INITIAL_DATA__\s*=\s*({.*?});/s);
    if (match3 && match3[1]) {
      try {
        interface InitialData {
          songList?: KGSongRawItem[];
        }
        const parsedData: InitialData = JSON.parse(match3[1]) as InitialData;
        if (parsedData && parsedData.songList && Array.isArray(parsedData.songList)) {
          return parsedData.songList;
        }
      } catch (e) {
        // 解析失败，忽略
      }
    }
  } catch (e) {
    // 解析失败，返回空数组
  }

  return result;
}

function filterKgHotTagRows(rawData: KgHotTagWrapper): SongListTag[] {
  const result: SongListTag[] = [];
  if (rawData.status !== 1) {
    return result;
  }
  const keys = Object.keys(rawData.data);
  for (let i = 0; i < keys.length; i++) {
    const tag = rawData.data[keys[i]];
    const row: SongListTag = {
      id: String(tag.special_id),
      name: tag.special_name,
      source: 'kg',
    };
    result.push(row);
  }
  return result;
}

function flattenKgTagids(tagids: Record<string, KgTagidsGroup>): SongListTag[] {
  const out: SongListTag[] = [];
  const cats = Object.keys(tagids);
  for (let i = 0; i < cats.length; i++) {
    const group = tagids[cats[i]];
    const arr = group.data;
    for (let j = 0; j < arr.length; j++) {
      const tag = arr[j];
      const row: SongListTag = {
        parent_id: String(tag.parent_id),
        parent_name: tag.pname,
        id: String(tag.id),
        name: tag.name,
        source: 'kg',
      };
      out.push(row);
    }
  }
  return out;
}

function fetchKgSongListPage(sortId: string, tagId: string, page: number, tryNum: number = 0): Promise<RawSongListItem[]> {
  if (tryNum > 2) {
    return Promise.reject(new Error('try max num'));
  }
  const url = getSongListUrl(sortId, tagId, page);
  const listReq: HttpRequestConfig = { header: songListHeaders };
  return httpRequest(url, listReq).promise.then((response) => {
    const body = parseKgHttpJson<KGSongListResponse>(response.result as string | Object);
    if (!body || body.status !== 1) {
      return fetchKgSongListPage(sortId, tagId, page, tryNum + 1);
    }
    return body.special_db ?? [];
  });
}

function fetchKgListInfoMeta(tagId: string, tryNum: number = 0): Promise<KgListInfoMeta> {
  if (tryNum > 2) {
    const emptyMeta: KgListInfoMeta = { limit: 20, page: 1, total: 0, source: 'kg' };
    return Promise.resolve(emptyMeta);
  }
  if (kgCachedListInfoTagId === tagId && kgCachedListInfo !== null) {
    return Promise.resolve(kgCachedListInfo);
  }
  const url = getInfoUrl(tagId);
  const infoReq: HttpRequestConfig = { header: songListHeaders };
  return httpRequest(url, infoReq).promise.then((response) => {
    const body = parseKgHttpJson<KgListParamsBody>(response.result as string | Object);
    if (body.status !== 1) {
      return fetchKgListInfoMeta(tagId, tryNum + 1);
    }
    const p = body.data?.params;
    const meta: KgListInfoMeta = {
      limit: p?.pagesize ?? 20,
      page: p?.p ?? 1,
      total: p?.total ?? 0,
      source: 'kg',
    };
    kgCachedListInfoTagId = tagId;
    kgCachedListInfo = meta;
    return meta;
  });
}

function fetchKgSongListRecommend(tryNum: number = 0): Promise<RawSongListItem[]> {
  if (tryNum > 2) {
    return Promise.resolve([]);
  }
  const bodyObj: KgRecommendPostBody = {
    appid: 1001,
    clienttime: 1566798337219,
    clientver: 8275,
    key: 'f1f93580115bb106680d2375f8032d96',
    mid: '21511157a05844bd085308bc76ef3343',
    platform: 'pc',
    userid: '262643156',
    return_min: 6,
    return_max: 15,
  };
  const recHeader: Map<string, string> = new Map();
  recHeader.set('User-Agent', 'KuGou2012-8275-web_browser_event_handler');
  const recReq: HttpRequestConfig = {
    method: 'POST',
    header: recHeader,
    extraData: bodyObj,
  };
  return httpRequest('http://everydayrec.service.kugou.com/guess_special_recommend', recReq).promise.then((response) => {
    const body = parseKgHttpJson<KgRecommendBody>(response.result as string | Object);
    if (body.status !== 1) {
      return fetchKgSongListRecommend(tryNum + 1);
    }
    return body.data?.special_list ?? [];
  });
}

// 歌单接口
interface SongListInterface {
  sortList: SortItem[];
  listDetailLimit: number;
  getTags: () => Promise<SongListTagsResult>;
  getList: (sortId: string, tagId: string, page: number) => Promise<SongListResult>;
  filterList: (rawData: RawSongListItem[]) => SongListInfo[];
  getListDetail: (id: string, page: number) => Promise<SongListDetailResult>;
  getListDetailBySpecialId: (id: string, page: number, tryNum?: number) => Promise<SongListDetailResult>;
  getListDetailByLink: (link: string) => Promise<SongListDetailResult>;
  getListDetailByGlobalId: (globalId: string, page: number) => Promise<SongListDetailResult>;
  getDetailPageUrl: (id: string) => string;
}

/** 歌单详情抓不到（重试上限用尽）时的空结果 */
function buildEmptyDetailResult(): SongListDetailResult {
  const info: SongListDetailInfo = {
    name: '',
    img: '',
    desc: '',
    author: '',
    play_count: '',
  };
  return {
    list: [],
    total: 0,
    source: 'kg',
    info,
  };
}

/** 从详情页 HTML 里的 global 配置取歌单名/封面/简介 */
function buildDetailInfo(listInfo: RegExpMatchArray | null, body: string): SongListDetailInfo {
  const info: SongListDetailInfo = {
    name: listInfo && listInfo[1] ? decodeName(listInfo[1].trim()) : '',
    img: listInfo && listInfo[2] ? listInfo[2] : '',
    desc: parseHtmlDesc(body),
    author: '',
    play_count: '',
  };
  return info;
}

/** HTML 里只有歌名/歌手/hash 的简化数据（批量接口拿不到时的兜底，至少能播能看） */
function toSimpleMusicInfo(item: KGSongRawItem): MusicInfo {
  return {
    name: decodeName(item.songname) || '',
    singer: decodeName(item.singername) || '',
    source: 'kg',
    songmid: item.hash || '',
    albumId: item.album_id || '',
    interval: item.duration ? formatPlayTime(item.duration) : '00:00',
    albumName: decodeName(item.album_name) || '',
    img: item.img || null,
    lrc: null,
    types: [],
    _types: new Map<Quality, QualityDetail>(),
    typeUrl: new Map<string, string>(),
    otherSource: null,
    hash: item.hash,
  };
}

/**
 * 歌单详情的歌曲列表：优先按 hash 批量补全完整信息，批量失败就退回 HTML 简化数据。
 * 两条路都拿不到就是空列表（上层按空歌单展示）。
 */
async function buildDetailMusicList(uniqueList: KGSongRawItem[]): Promise<MusicInfo[]> {
  const hashes: string[] = [];
  for (const item of uniqueList) {
    if (item.hash) {
      hashes.push(item.hash);
    }
  }
  if (hashes.length > 0) {
    const batchData = await getMusicInfosFromAPI(hashes);
    if (batchData.length > 0) {
      const fullList: MusicInfo[] = filterBatchMusicData(batchData);
      if (fullList.length > 0) {
        return fullList;
      }
    }
  }
  const fallbackList: MusicInfo[] = [];
  for (const item of uniqueList) {
    fallbackList.push(toSimpleMusicInfo(item));
  }
  return fallbackList;
}

export const songList: SongListInterface = {
  sortList: sortList,
  listDetailLimit: 10000,

  /**
   * 获取歌单分类标签
   */
  getTags(): Promise<SongListTagsResult> {
    const url = getInfoUrl('');
    const tagReq: HttpRequestConfig = { header: songListHeaders };
    return httpRequest(url, tagReq).promise.then((response) => {
      const root = parseKgHttpJson<KgTagsRoot>(response.result as string | Object);
      if (root.status !== 1) {
        const error: Promise<SongListTagsResult> = Promise.reject(new Error('获取标签失败'));
        return error;
      }
      const hotTag: SongListTag[] = filterKgHotTagRows(root.data.hotTag);
      const tags: SongListTag[] = flattenKgTagids(root.data.tagids);
      const finalResult: SongListTagsResult = {
        hotTag,
        tags,
        source: 'kg',
      };
      return finalResult;
    });
  },

  /**
   * 获取歌单列表（与安卓：列表 + getListInfo 分页信息 + 首页推荐穿插）
   */
  getList(sortId: string, tagId: string, page: number): Promise<SongListResult> {
    const needRecommend = (!tagId || tagId.length === 0) && page === 1 && sortId === sortList[0].id;
    return fetchKgSongListPage(sortId, tagId, page).then((rawItems: RawSongListItem[]) => {
      return fetchKgListInfoMeta(tagId).then((meta: KgListInfoMeta) => {
        const assemble = (rec: RawSongListItem[]): SongListResult => {
          let rows = songList.filterList(rawItems);
          if (rec.length > 0) {
            const recRows = songList.filterList(rec);
            const merged: SongListInfo[] = [];
            for (let i = 0; i < recRows.length; i++) {
              merged.push(recRows[i]);
            }
            for (let j = 0; j < rows.length; j++) {
              merged.push(rows[j]);
            }
            rows = merged;
          }
          const totalVal = meta.total > 0 ? meta.total : rows.length;
          const finalResult: SongListResult = {
            list: rows,
            limit: meta.limit,
            total: totalVal,
            page,
            source: 'kg',
          };
          return finalResult;
        };
        if (needRecommend) {
          return fetchKgSongListRecommend().then((rec: RawSongListItem[]) => assemble(rec));
        }
        return assemble([]);
      });
    });
  },

  /**
   * 过滤歌单列表
   */
  filterList(rawData: RawSongListItem[]): SongListInfo[] {
    return rawData.map(item => {
      const rawCount = item.total_play_count !== undefined ? item.total_play_count : item.play_count;
      const publishTime: number = item.publish_time || item.publishtime || 0;
      const img: string = item.img || item.imgurl;

      const songItem: SongListInfo = {
        play_count: formatPlayCount(rawCount ?? 0),
        id: 'id_' + item.specialid,
        author: item.nickname,
        name: item.specialname,
        time: formatKgPublishDate(publishTime),
        img: img,
        total: item.songcount,
        grade: item.grade,
        desc: item.intro,
        source: 'kg',
      };
      return songItem;
    });
  },

  /**
   * 获取歌单详情
   */
  getListDetail(id: string, page: number = 1): Promise<SongListDetailResult> {
    let finalId = id.toString();

    // 处理ID格式
    if (finalId.includes('special/single/')) {
      finalId = finalId.replace(/\/(\d+)-5-9999\.html$/, '$1');
    } else if (/^https?:/.test(finalId)) {
      // URL格式，需要解析
      return songList.getListDetailByLink(finalId);
    } else if (/^\d+$/.test(finalId)) {
      // 纯数字ID
    } else if (finalId.startsWith('id_')) {
      finalId = finalId.replace('id_', '');
    }

    return songList.getListDetailBySpecialId(finalId, page);
  },

  /**
   * 通过专题ID获取歌单详情
   */
  async getListDetailBySpecialId(id: string, page: number, tryNum: number = 0): Promise<SongListDetailResult> {
    if (tryNum > 2) {
      return buildEmptyDetailResult();
    }
    // 酷狗歌单详情 URL - HTML页面
    const url = getSongListDetailUrl(id);

    try {
      const body = await fetchKgSongListDetailHtml(url);
      const listInfo = body.match(KG_REGEXP_LIST_INFO);

      // 从 HTML 中提取歌曲列表
      const rawList = parseHtmlSongList(body);
      if (rawList.length === 0) {
        return songList.getListDetailBySpecialId(id, page, tryNum + 1);
      }

      const musicList = await buildDetailMusicList(deDuplication(rawList));
      const result: SongListDetailResult = {
        list: musicList,
        page: 1,
        limit: songList.listDetailLimit,
        total: musicList.length,
        source: 'kg',
        info: buildDetailInfo(listInfo, body),
      };
      return result;
    } catch (e) {
      return songList.getListDetailBySpecialId(id, page, tryNum + 1);
    }
  },

  /**
   * 通过链接获取歌单详情
   */
  async getListDetailByLink(link: string): Promise<SongListDetailResult> {
    // URL解析逻辑
    if (link.includes('global_collection_id=')) {
      const match = link.match(/global_collection_id=(\w+)/);
      if (match) {
        return songList.getListDetailByGlobalId(match[1], 1);
      }
    }

    const result: SongListDetailResult = {
      list: [],
      total: 0,
      source: 'kg',
      info: {
        name: '',
        img: '',
        desc: '',
        author: '',
        play_count: '',
      },
    };
    return result;
  },

  /**
   * 通过global_collection_id获取歌单详情
   */
  async getListDetailByGlobalId(globalId: string, _page: number): Promise<SongListDetailResult> {
    const params = `appid=1058&specialid=0&global_specialid=${globalId}&format=jsonp&srcappid=2919&clientver=20000&clienttime=1586163242519&mid=1586163242519&uuid=1586163242519&dfid=-`;
    const signature = signatureParams(params, 'web');

    const url = `https://mobiles.kugou.com/api/v5/special/info_v2?${params}&signature=${signature}`;

    const reqOpts: HttpRequestConfig = {
      header: songListHeaders,
    };
    return httpRequest(url, reqOpts).promise.then((response) => {
      const info = parseKgHttpJson<KGListInfoResponse>(response.result as string | Object);

      const result: SongListDetailResult = {
        list: [],
        total: info.songcount || 0,
        source: 'kg',
        info: {
          name: info.specialname || '',
          img: info.imgurl ? info.imgurl.replace('{size}', '240') : '',
          desc: info.intro || '',
          author: '',
          play_count: '',
        },
      };
      return result;
    });
  },

  /**
   * 获取详情页URL
   */
  getDetailPageUrl(id: string): string {
    if (typeof id === 'string') {
      if (/^https?:\/\//.test(id)) return id;
      const newId = id.replace('id_', '');
      return `https://www.kugou.com/yy/special/single/${newId}.html`;
    }
    return `https://www.kugou.com/yy/special/single/${id}.html`;
  },
};
