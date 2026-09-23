/**
 * 网易云音乐 - 歌单（对齐 src/utils/musicSdk/wy/songList.js）
 */
import { httpRequest, parseHttpBodyJson, httpResponseBody, type HttpRequestConfig } from '../../../../core/network/http';
import type { MusicInfo, MusicQualityType, Quality, QualityDetail } from '../../../../types/MusicTypes';
import { formatPlayTime, formatPlayCount, sizeFormate } from '../../../../utils/CommonUtils';
import type {
  SongListTagsResult,
  SongListResult,
  SongListInfo,
  SongListDetailResult,
  SongListDetailInfo,
  SongListTag,
  SongListSdkInterface,
} from '../MusicSdkContracts';
import {
  neteaseWeapi,
  neteaseLinuxapiFromJsonString,
  buildWeapiFormBody,
  buildLinuxapiFormBody,
  type WeapiJsonObject,
} from './NeteaseCrypto';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'WySongList';
const DOMAIN = 0x0001;

interface WySongListModule extends SongListSdkInterface {
  getDetailPageUrl(rawId: string): string;
}

const SUCCESS_CODE = 200;
const LIMIT_LIST = 30;
const LIMIT_SONG = 100000;
const DETAIL_PAGE_LIMIT = 1000;

const WY_HEADERS: Map<string, string> = buildWyHeaders();

function buildWyHeaders(): Map<string, string> {
  const m: Map<string, string> = new Map();
  m.set('Content-Type', 'application/x-www-form-urlencoded');
  m.set('Referer', 'https://music.163.com/');
  m.set('Origin', 'https://music.163.com');
  m.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');
  return m;
}

const LINUX_FORWARD_HEADERS: Map<string, string> = buildLinuxForwardHeaders();

function buildLinuxForwardHeaders(): Map<string, string> {
  const m: Map<string, string> = new Map();
  m.set('Content-Type', 'application/x-www-form-urlencoded');
  m.set('User-Agent', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/60.0.3112.90 Safari/537.36');
  return m;
}

interface WyTagGroup {
  name: string;
  list: SongListTag[];
}

interface WyPlaylistListResponse {
  code: number;
  playlists?: WyPlaylistItem[];
  total?: string | number;
}

interface WyUserNick {
  nickname?: string;
}

interface WyPlaylistItem {
  id?: number;
  name?: string;
  coverImgUrl?: string;
  description?: string;
  creator?: WyUserNick;
  playCount?: number;
  trackCount?: number;
  createTime?: number;
}

interface WyCatalogueResponse {
  code: number;
  sub?: WySubTag[];
  categories?: Record<string, string>;
}

// 歌单搜索（web 搜索接口 type=1000）
interface WySearchPlaylistItem {
  id: number;
  name?: string;
  coverImgUrl?: string;
  trackCount?: number;
  playCount?: number;
  description?: string;
  creator?: WyUserNick;
}

interface WySearchPlaylistResult {
  playlists?: WySearchPlaylistItem[];
  playlistCount?: number;
}

interface WyPlaylistSearchBody {
  code?: number;
  result?: WySearchPlaylistResult;
}

interface WySubTag {
  category: string;
  name: string;
}

interface WyHotTagsResponse {
  code: number;
  tags?: WyHotTagEntry[];
}

interface WyPlaylistTagName {
  name?: string;
}

interface WyHotTagEntry {
  playlistTag?: WyPlaylistTagName;
}

interface WyPlaylistDetailBody {
  code: number;
  playlist?: WyPlaylistDetail;
  privileges?: WyPrivilege[];
}

interface WyTrackIdEntry {
  id?: number;
}

interface WyPlaylistDetail {
  name?: string;
  coverImgUrl?: string;
  description?: string;
  creator?: WyUserNick;
  playCount?: number;
  trackIds?: WyTrackIdEntry[];
  tracks?: WyTrack[];
}

interface WyPcTrack {
  ar?: string;
  sn?: string;
  alb?: string;
}

interface WyArTrack {
  name?: string;
}

interface WyAlTrack {
  id?: number;
  name?: string;
  picUrl?: string;
}

interface WyBitrateFile {
  size?: number;
}

interface WyTrack {
  id?: number;
  name?: string;
  dt?: number;
  pc?: WyPcTrack;
  ar?: WyArTrack[];
  al?: WyAlTrack;
  hr?: WyBitrateFile;
  h?: WyBitrateFile;
  l?: WyBitrateFile;
}

interface WyPrivilege {
  id?: number;
  maxBrLevel?: string;
  maxbr?: number;
}

/**
 * 与安卓歌单页 sortList 对齐：网易接口 order 仅支持 hot / new。
 * Harmony 通用 getSortList 使用 id「0=推荐 1=最新 2=最热」，需映射。
 */
function normalizeOrder(sortId: string): string {
  if (sortId === 'new' || sortId === '1') {
    return 'new';
  }
  if (sortId === 'hot' || sortId === '2' || sortId === '0' || !sortId || sortId === 'default') {
    return 'hot';
  }
  return sortId;
}

function flattenTagGroups(groups: WyTagGroup[], source: string): SongListTag[] {
  const out: SongListTag[] = [];
  for (let g = 0; g < groups.length; g++) {
    const grp = groups[g];
    const list = grp.list;
    for (let i = 0; i < list.length; i++) {
      const t = list[i];
      const flat: SongListTag = {
        id: t.id,
        name: t.name,
        parent_id: t.parent_id,
        parent_name: t.parent_name ?? grp.name,
        source,
      };
      out.push(flat);
    }
  }
  return out;
}

function filterTagInfo(body: WyCatalogueResponse): WyTagGroup[] {
  const categories = body.categories;
  const sub = body.sub;
  if (!categories || !sub) {
    return [];
  }
  const subList: Record<string, SongListTag[]> = {};
  for (let i = 0; i < sub.length; i++) {
    const item = sub[i];
    const cat = item.category;
    if (!subList[cat]) {
      subList[cat] = [];
    }
    const catName = categories[cat];
    const row: SongListTag = {
      parent_id: catName,
      parent_name: catName,
      id: item.name,
      name: item.name,
      source: 'wy',
    };
    subList[cat].push(row);
  }
  const list: WyTagGroup[] = [];
  const keys = Object.keys(categories);
  for (let k = 0; k < keys.length; k++) {
    const key = keys[k];
    const name = categories[key];
    const arr = subList[key];
    if (arr) {
      const grp: WyTagGroup = { name, list: arr };
      list.push(grp);
    }
  }
  return list;
}

function filterHotTagInfo(raw: WyHotTagEntry[]): SongListTag[] {
  const out: SongListTag[] = [];
  for (let i = 0; i < raw.length; i++) {
    const n = raw[i].playlistTag?.name ?? '';
    if (n.length > 0) {
      const ht: SongListTag = { id: n, name: n, source: 'wy' };
      out.push(ht);
    }
  }
  return out;
}

function filterListPlaylists(raw: WyPlaylistItem[]): SongListInfo[] {
  const list: SongListInfo[] = [];
  for (let i = 0; i < raw.length; i++) {
    const item = raw[i];
    const row: SongListInfo = {
      play_count: item.playCount !== undefined ? formatPlayCount(item.playCount) : '0',
      id: String(item.id ?? ''),
      author: item.creator?.nickname ?? '',
      name: item.name ?? '',
      img: item.coverImgUrl ?? '',
      desc: item.description ?? '',
      total: item.trackCount ?? 0,
      source: 'wy',
    };
    list.push(row);
  }
  return list;
}

function formatWySingers(ar: WyArTrack[] | undefined): string {
  if (!ar || ar.length === 0) {
    return '';
  }
  const parts: string[] = [];
  for (let i = 0; i < ar.length; i++) {
    const n = ar[i].name;
    if (n) {
      parts.push(n);
    }
  }
  return parts.join('、');
}

/** 公开 v3/detail 常不带 privileges；无此项时 filterListDetail 会丢光曲目 */
function buildSyntheticWyPrivileges(tracks: WyTrack[]): WyPrivilege[] {
  const out: WyPrivilege[] = [];
  for (let i = 0; i < tracks.length; i++) {
    const item = tracks[i];
    const sid = item.id ?? 0;
    let maxbr = 128000;
    if (item.hr) {
      maxbr = 999000;
    } else if (item.h) {
      maxbr = 320000;
    }
    const p: WyPrivilege = {
      id: sid,
      maxbr,
      maxBrLevel: item.hr ? 'hires' : undefined,
    };
    out.push(p);
  }
  return out;
}

function filterListDetail(body: WyPlaylistDetailBody): MusicInfo[] {
  const pl = body.playlist;
  if (!pl || !pl.tracks) {
    return [];
  }
  const tracks = pl.tracks;
  let privileges = body.privileges ?? [];
  if (privileges.length === 0 && tracks.length > 0) {
    privileges = buildSyntheticWyPrivileges(tracks);
  }
  const list: MusicInfo[] = [];
  for (let index = 0; index < tracks.length; index++) {
    const item = tracks[index];
    let privilege: WyPrivilege | undefined = privileges[index];
    if (privilege && item.id !== undefined && privilege.id !== item.id) {
      for (let p = 0; p < privileges.length; p++) {
        if (privileges[p].id === item.id) {
          privilege = privileges[p];
          break;
        }
      }
    }
    if (!privilege) {
      continue;
    }
    const types: MusicQualityType[] = [];
    const _types = new Map<Quality, QualityDetail>();

    if (privilege.maxBrLevel === 'hires') {
      const size = item.hr ? sizeFormate(item.hr.size ?? 0) : null;
      const qh: MusicQualityType = { type: 'flac24bit', size };
      types.push(qh);
      const dh: QualityDetail = { size };
      _types.set('flac24bit', dh);
    }
    const maxbr = privilege.maxbr ?? 0;
    if (maxbr === 999000) {
      const qf: MusicQualityType = { type: 'flac', size: null };
      types.push(qf);
      const df: QualityDetail = { size: null };
      _types.set('flac', df);
    }
    if (maxbr === 999000 || maxbr === 320000) {
      const s320 = item.h ? sizeFormate(item.h.size ?? 0) : null;
      const q320: MusicQualityType = { type: '320k', size: s320 };
      types.push(q320);
      const d320: QualityDetail = { size: s320 };
      _types.set('320k', d320);
    }
    if (maxbr === 999000 || maxbr === 320000 || maxbr === 192000 || maxbr === 128000) {
      const s128 = item.l ? sizeFormate(item.l.size ?? 0) : null;
      const q128: MusicQualityType = { type: '128k', size: s128 };
      types.push(q128);
      const d128: QualityDetail = { size: s128 };
      _types.set('128k', d128);
    }
    for (let a = 0, b = types.length - 1; a < b; a++, b--) {
      const tmp = types[a];
      types[a] = types[b];
      types[b] = tmp;
    }

    if (item.pc) {
      const mi: MusicInfo = {
        singer: item.pc.ar ?? '',
        name: item.pc.sn ?? '',
        albumName: item.pc.alb ?? '',
        albumId: item.al?.id?.toString() ?? '',
        source: 'wy',
        interval: formatPlayTime((item.dt ?? 0) / 1000),
        songmid: String(item.id ?? ''),
        img: item.al?.picUrl ?? null,
        lrc: null,
        otherSource: null,
        types,
        _types,
        typeUrl: new Map(),
      };
      list.push(mi);
    } else {
      const mi2: MusicInfo = {
        singer: formatWySingers(item.ar),
        name: item.name ?? '',
        albumName: item.al?.name,
        albumId: item.al?.id?.toString() ?? '',
        source: 'wy',
        interval: formatPlayTime((item.dt ?? 0) / 1000),
        songmid: String(item.id ?? ''),
        img: item.al?.picUrl ?? null,
        lrc: null,
        otherSource: null,
        types,
        _types,
        typeUrl: new Map(),
      };
      list.push(mi2);
    }
  }
  return list;
}

const REG_LIST = /^.+(?:\?|&)id=(\d+)(?:&.*$|#.*$|$)/;
const REG_LIST2 = /^.+\/playlist\/(\d+)\/\d+\/.+$/;

interface WyResolvedListId {
  id: string;
  cookie?: string;
}

async function getListId(rawId: string): Promise<WyResolvedListId> {
  let id = rawId;
  let cookie: string | undefined;
  if (/###/.test(id)) {
    const parts = id.split('###');
    id = parts[0];
    cookie = `MUSIC_U=${parts[1]}`;
  }
  if (/[?&:/]/.test(id)) {
    let m = REG_LIST.exec(id);
    if (!m) {
      m = REG_LIST2.exec(id);
    }
    if (!m) {
      m = /[?&]id=(\d+)/.exec(id);
    }
    if (!m) {
      m = /\/playlist\/(\d+)/.exec(id);
    }
    if (m) {
      id = m[1];
    }
  }
  return { id, cookie };
}

class WySongListImpl implements WySongListModule {
  /** 公开 GET，预览器/无 linux 加密时可用（与 leaderboard legacy 一致） */
  private async fetchPlaylistDetailPublic(id: string, cookie: string | undefined): Promise<WyPlaylistDetailBody | null> {
    try {
      const headers: Map<string, string> = new Map();
      headers.set('Referer', 'https://music.163.com/');
      headers.set(
        'User-Agent',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36'
      );
      if (cookie) {
        headers.set('Cookie', cookie);
      }
      const url = `https://music.163.com/api/v3/playlist/detail?id=${encodeURIComponent(id)}&n=1000`;
      const res = await httpRequest(url, { method: 'GET', header: headers, responseType: 'text' }).promise;
      return parseHttpBodyJson<WyPlaylistDetailBody>(httpResponseBody(res));
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'fetchPlaylistDetailPublic failed: %{public}s', (e as Error)?.message);
      return null;
    }
  }

  private tryBuildSonglistDetailResult(body: WyPlaylistDetailBody | null, page: number): SongListDetailResult | null {
    if (body === null || body.code !== SUCCESS_CODE || !body.playlist) {
      return null;
    }
    const pl = body.playlist;
    const trackIds = pl.trackIds ?? [];
    const fullList = filterListDetail(body);
    const rangeStart = (page - 1) * DETAIL_PAGE_LIMIT;
    const slice = fullList.slice(rangeStart, rangeStart + DETAIL_PAGE_LIMIT);
    const info: SongListDetailInfo = {
      play_count: pl.playCount !== undefined ? formatPlayCount(pl.playCount) : '',
      name: pl.name ?? '',
      img: pl.coverImgUrl ?? '',
      desc: pl.description ?? '',
      author: pl.creator?.nickname ?? '',
    };
    const trackTotal =
      trackIds.length > 0 ? trackIds.length : (pl.tracks !== undefined ? pl.tracks.length : fullList.length);
    const out: SongListDetailResult = {
      list: slice,
      page,
      limit: DETAIL_PAGE_LIMIT,
      total: trackTotal,
      source: 'wy',
      info,
    };
    return out;
  }

  private async getTagsByLegacyApi(): Promise<SongListTagsResult> {
    try {
      const headers: Map<string, string> = new Map();
      headers.set('Referer', 'https://music.163.com/');
      headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');
      const resArr = await Promise.all([
        httpRequest('https://music.163.com/api/playlist/catalogue', { method: 'GET', header: headers, responseType: 'text' }).promise,
        httpRequest('https://music.163.com/api/playlist/hottags', { method: 'GET', header: headers, responseType: 'text' }).promise,
      ]);
      const body1 = parseHttpBodyJson<WyCatalogueResponse>(httpResponseBody(resArr[0]));
      const body2 = parseHttpBodyJson<WyHotTagsResponse>(httpResponseBody(resArr[1]));
      const emptyTags: SongListTagsResult = { tags: [], hotTag: [], source: 'wy' };
      if (body1 === null || body1.code !== SUCCESS_CODE) {
        return emptyTags;
      }
      const groups = filterTagInfo(body1);
      const hotTag = body2 && body2.code === SUCCESS_CODE && body2.tags ? filterHotTagInfo(body2.tags) : [];
      return {
        tags: flattenTagGroups(groups, 'wy'),
        hotTag,
        source: 'wy',
      };
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : String(e);
      hilog.warn(0x0001, 'WY_SongList', 'getTags public GET failed: %{public}s', errMsg);
      return { tags: [], hotTag: [], source: 'wy' };
    }
  }

  private async getListByLegacyApi(order: string, cat: string, page: number): Promise<SongListResult> {
    try {
      const headers: Map<string, string> = new Map();
      headers.set('Referer', 'https://music.163.com/');
      headers.set('User-Agent', 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/110.0.0.0 Safari/537.36');
      const offset = LIMIT_LIST * (page - 1);
      const url = `https://music.163.com/api/playlist/list?cat=${encodeURIComponent(cat)}&order=${encodeURIComponent(order)}&offset=${offset}&limit=${LIMIT_LIST}`;
      const res = await httpRequest(url, { method: 'GET', header: headers, responseType: 'text' }).promise;
      const body = parseHttpBodyJson<WyPlaylistListResponse>(httpResponseBody(res));
      const emptyList: SongListResult = { list: [], total: 0, page, limit: LIMIT_LIST, source: 'wy' };
      if (body === null || body.code !== SUCCESS_CODE || !body.playlists) {
        return emptyList;
      }
      return {
        list: filterListPlaylists(body.playlists),
        total: typeof body.total === 'string' ? parseInt(body.total, 10) : (body.total ?? 0),
        page,
        limit: LIMIT_LIST,
        source: 'wy',
      };
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : String(e);
      hilog.warn(0x0001, 'WY_SongList', 'getList public GET failed: %{public}s', errMsg);
      return { list: [], total: 0, page, limit: LIMIT_LIST, source: 'wy' };
    }
  }

  async getTags(): Promise<SongListTagsResult> {
    const legacy = await this.getTagsByLegacyApi();
    if (legacy.tags.length > 0 || legacy.hotTag.length > 0) {
      return legacy;
    }
    try {
      const emptyBody: WeapiJsonObject = {};
      const form1 = await neteaseWeapi(emptyBody);
      const form2 = await neteaseWeapi(emptyBody);
      const catReq: HttpRequestConfig = {
        method: 'POST',
        header: WY_HEADERS,
        extraData: buildWeapiFormBody(form1),
        responseType: 'text',
      };
      const hotReq: HttpRequestConfig = {
        method: 'POST',
        header: WY_HEADERS,
        extraData: buildWeapiFormBody(form2),
        responseType: 'text',
      };
      const resArr = await Promise.all([
        httpRequest('https://music.163.com/weapi/playlist/catalogue', catReq).promise,
        httpRequest('https://music.163.com/weapi/playlist/hottags', hotReq).promise,
      ]);
      const body1 = parseHttpBodyJson<WyCatalogueResponse>(httpResponseBody(resArr[0]));
      const body2 = parseHttpBodyJson<WyHotTagsResponse>(httpResponseBody(resArr[1]));
      if (body1 === null || body2 === null || body1.code !== SUCCESS_CODE) {
        return legacy;
      }
      const groups = filterTagInfo(body1);
      const hotTag = body2.code === SUCCESS_CODE && body2.tags ? filterHotTagInfo(body2.tags) : [];
      return {
        tags: flattenTagGroups(groups, 'wy'),
        hotTag,
        source: 'wy',
      };
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : String(e);
      hilog.error(0x0001, 'WY_SongList', 'getTags weapi %{public}s', errMsg);
      return legacy;
    }
  }

  async getList(sortId: string, tagId: string, page: number): Promise<SongListResult> {
    const order = normalizeOrder(sortId);
    const cat = tagId && tagId.length > 0 ? tagId : '全部';
    const legacy = await this.getListByLegacyApi(order, cat, page);
    if (legacy.list.length > 0 || legacy.total > 0) {
      return legacy;
    }
    try {
      const listBody: WeapiJsonObject = {};
      listBody['cat'] = cat;
      listBody['order'] = order;
      listBody['limit'] = LIMIT_LIST;
      listBody['offset'] = LIMIT_LIST * (page - 1);
      listBody['total'] = true;
      const form = await neteaseWeapi(listBody);
      const listReq: HttpRequestConfig = {
        method: 'POST',
        header: WY_HEADERS,
        extraData: buildWeapiFormBody(form),
        responseType: 'text',
      };
      const res = await httpRequest('https://music.163.com/weapi/playlist/list', listReq).promise;
      const body = parseHttpBodyJson<WyPlaylistListResponse>(httpResponseBody(res));
      if (body === null || body.code !== SUCCESS_CODE || !body.playlists) {
        return legacy;
      }
      return {
        list: filterListPlaylists(body.playlists),
        total: typeof body.total === 'string' ? parseInt(body.total, 10) : (body.total ?? 0),
        page,
        limit: LIMIT_LIST,
        source: 'wy',
      };
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : String(e);
      hilog.error(0x0001, 'WY_SongList', 'getList weapi %{public}s', errMsg);
      return legacy;
    }
  }

  async getListDetail(rawId: string, page: number): Promise<SongListDetailResult> {
    const emptyInfo: SongListDetailInfo = { name: '', img: '', desc: '', author: '', play_count: '' };
    const emptyDetail: SongListDetailResult = {
      list: [],
      info: emptyInfo,
      total: 0,
      source: 'wy',
      page,
      limit: DETAIL_PAGE_LIMIT,
    };
    try {
      const resolved = await getListId(rawId);
      const id = resolved.id;
      const cookie = resolved.cookie;

      const pubBody = await this.fetchPlaylistDetailPublic(id, cookie);
      let detail = this.tryBuildSonglistDetailResult(pubBody, page);
      if (detail !== null && (detail.list.length > 0 || detail.info.name.length > 0 || detail.total > 0)) {
        return detail;
      }

      const linuxJson =
        '{"method":"POST","url":"https://music.163.com/api/v3/playlist/detail","params":{"id":' +
        id +
        ',"n":' +
        String(LIMIT_SONG) +
        ',"s":8}}';
      const linuxForm = await neteaseLinuxapiFromJsonString(linuxJson);
      const headers: Map<string, string> = new Map(LINUX_FORWARD_HEADERS);
      if (cookie) {
        headers.set('Cookie', cookie);
      }
      const forwardReq: HttpRequestConfig = {
        method: 'POST',
        header: headers,
        extraData: buildLinuxapiFormBody(linuxForm),
        responseType: 'text',
      };
      const res = await httpRequest('https://music.163.com/api/linux/forward', forwardReq).promise;
      const body = parseHttpBodyJson<WyPlaylistDetailBody>(httpResponseBody(res));
      detail = this.tryBuildSonglistDetailResult(body, page);
      if (detail !== null) {
        return detail;
      }
      if (body === null) {
        hilog.warn(0x0001, 'WY_SongList', 'getListDetail empty or non-json response body (linux/forward)');
      }
      return emptyDetail;
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : String(e);
      hilog.error(0x0001, 'WY_SongList', 'getListDetail %{public}s', errMsg);
      return emptyDetail;
    }
  }

  getDetailPageUrl(rawId: string): string {
    return `https://music.163.com/#/playlist?id=${rawId.replace(/###.*/, '')}`;
  }

  /**
   * 歌单搜索：使用公开的 web 搜索接口（type=1000 表示歌单）。
   * 返回 null 表示该源当前不可用，由上层跳过。
   */
  async searchList(keyword: string, page: number, limit: number): Promise<SongListResult | null> {
    const kw = (keyword ?? '').trim();
    if (kw.length === 0) {
      return null;
    }
    const safeLimit = Math.min(Math.max(limit, 1), 50);
    const offset = Math.max(page - 1, 0) * safeLimit;
    const url = `https://music.163.com/api/search/get/web?s=${encodeURIComponent(kw)}&type=1000&limit=${safeLimit}&offset=${offset}`;
    try {
      const req: HttpRequestConfig = {
        method: 'GET',
        header: WY_HEADERS,
        responseType: 'text',
      };
      const res = await httpRequest(url, req).promise;
      const body = parseHttpBodyJson<WyPlaylistSearchBody>(httpResponseBody(res));
      if (!body || !body.result || !body.result.playlists) {
        hilog.warn(DOMAIN, TAG, 'searchList empty response');
        return null;
      }
      const list: SongListInfo[] = [];
      const raw = body.result.playlists;
      for (let i = 0; i < raw.length; i++) {
        const item = raw[i];
        list.push({
          id: `${item.id}`,
          name: item.name ?? '',
          author: item.creator ? (item.creator.nickname ?? '') : '',
          img: item.coverImgUrl ?? '',
          play_count: formatPlayCount(item.playCount ?? 0),
          desc: item.description ?? '',
          total: item.trackCount ?? 0,
          source: 'wy',
        });
      }
      const result: SongListResult = {
        list: list,
        total: body.result.playlistCount ?? list.length,
        page: page,
        limit: safeLimit,
        source: 'wy',
      };
      hilog.info(DOMAIN, TAG, 'searchList ok: keyword=%{public}s, count=%{public}d', kw, list.length);
      return result;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'searchList failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      return null;
    }
  }
}

export const songList: WySongListModule = new WySongListImpl();

export default songList;
