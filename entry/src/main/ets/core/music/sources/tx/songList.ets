/**
 * QQ音乐 - 歌单（对齐 src/utils/musicSdk/tx/songList.js）
 */
import type { MusicInfo, MusicQualityType, Quality, QualityDetail } from '../../../../types/MusicTypes';
import { httpRequest, parseHttpBodyJson, type HttpRequestConfig } from '../../../../core/network/http';
import { formatPlayTime, decodeName, formatPlayCount, sizeFormate } from '../../../../utils/CommonUtils';
import { formatSingerName, type SingerInfo } from './utils/crypto';
import type {
  SongListTagsResult,
  SongListResult,
  SongListInfo,
  SongListDetailResult,
  SongListDetailInfo,
  SongListTag,
  SongListSdkInterface,
} from '../MusicSdkContracts';
import hilog from '@ohos.hilog';

interface TxSongListModule extends SongListSdkInterface {
  getDetailPageUrl(listId: string): string;
}

const SUCCESS_CODE = 0;
const LIMIT_LIST = 36;

function buildTxBrowserHeaderMap(): Map<string, string> {
  const m: Map<string, string> = new Map();
  m.set('Referer', 'https://y.qq.com/');
  m.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.0.0 Safari/537.36');
  return m;
}

function buildTxDetailHeaderMap(playlistId: string): Map<string, string> {
  const m: Map<string, string> = new Map();
  m.set('Origin', 'https://y.qq.com');
  m.set('Referer', `https://y.qq.com/n/yqq/playsquare/${playlistId}.html`);
  m.set('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.0.0 Safari/537.36');
  return m;
}

const TAGS_URL =
  'https://u.y.qq.com/cgi-bin/musicu.fcg?loginUin=0&hostUin=0&format=json&inCharset=utf-8&outCharset=utf-8&notice=0&platform=wk_v15.json&needNewCode=0&data=%7B%22tags%22%3A%7B%22method%22%3A%22get_all_categories%22%2C%22param%22%3A%7B%22qq%22%3A%22%22%7D%2C%22module%22%3A%22playlist.PlaylistAllCategoriesServer%22%7D%7D';
const HOT_TAG_URL = 'https://c.y.qq.com/node/pc/wk_v15/category_playlist.html';

function getListUrl(sortId: string, tagId: string, page: number): string {
  if (tagId && tagId.length > 0) {
    const tid = parseInt(tagId, 10);
    const p = page - 1;
    const dataStr =
      '{"comm":{"cv":1602,"ct":20},"playlist":{"method":"get_category_content","param":{"titleid":' +
      String(tid) +
      ',"caller":"0","category_id":' +
      String(tid) +
      ',"size":' +
      String(LIMIT_LIST) +
      ',"page":' +
      String(p) +
      ',"use_page":1},"module":"playlist.PlayListCategoryServer"}}';
    return `https://u.y.qq.com/cgi-bin/musicu.fcg?loginUin=0&hostUin=0&format=json&inCharset=utf-8&outCharset=utf-8&notice=0&platform=wk_v15.json&needNewCode=0&data=${encodeURIComponent(dataStr)}`;
  }
  const order = !sortId || sortId === 'default' ? 'hot' : sortId;
  const sin = LIMIT_LIST * (page - 1);
  const dataStr2 =
    '{"comm":{"cv":1602,"ct":20},"playlist":{"method":"get_playlist_by_tag","param":{"id":10000000,"sin":' +
    String(sin) +
    ',"size":' +
    String(LIMIT_LIST) +
    ',"order":"' +
    order +
    '","cur_page":' +
    String(page) +
    '},"module":"playlist.PlayListPlazaServer"}}';
  return `https://u.y.qq.com/cgi-bin/musicu.fcg?loginUin=0&hostUin=0&format=json&inCharset=utf-8&outCharset=utf-8&notice=0&platform=wk_v15.json&needNewCode=0&data=${encodeURIComponent(dataStr2)}`;
}

function getListDetailUrl(id: string): string {
  return `https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg?type=1&json=1&utf8=1&onlysong=0&new_format=1&disstid=${id}&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0`;
}

interface TxTagItem {
  id?: number;
  name?: string;
}

interface TxTagGroupRaw {
  group_name?: string;
  group_id?: string;
  v_item?: TxTagItem[];
}

interface TxTagsData {
  v_group?: TxTagGroupRaw[];
}

interface TxTagsWrap {
  data?: TxTagsData;
}

interface TxTagsBody {
  code?: number;
  tags?: TxTagsWrap;
}

interface TxVItemEntry {
  basic?: TxPlaylistBasic;
}

interface TxPlaylistContentBlock {
  v_item?: TxVItemEntry[];
  total_cnt?: number;
}

interface TxPlaylistData {
  v_playlist?: TxVPlaylist[];
  total?: number;
  content?: TxPlaylistContentBlock;
}

interface TxNick {
  nick?: string;
}

interface TxVPlaylist {
  tid?: number;
  title?: string;
  access_num?: number;
  modify_time?: number;
  cover_url_medium?: string;
  song_ids?: number[];
  desc?: string;
  creator_info?: TxNick;
}

interface TxCoverDual {
  medium_url?: string;
  default_url?: string;
}

interface TxPlaylistBasic {
  tid?: number;
  title?: string;
  play_cnt?: number;
  cover?: TxCoverDual;
  desc?: string;
  creator?: TxNick;
}

interface TxPlaylistWrap {
  data?: TxPlaylistData;
}

interface TxListBody {
  code?: number;
  playlist?: TxPlaylistWrap;
}

interface TxFileBlock {
  size_128mp3?: number;
  size_320mp3?: number;
  size_flac?: number;
  size_hires?: number;
  media_mid?: string;
}

interface TxSingerMini {
  name?: string;
  mid?: string;
}

interface TxAlbumMini {
  name?: string;
  mid?: string;
}

interface TxSongRow {
  title?: string;
  mid?: string;
  id?: number;
  interval?: number;
  singer?: TxSingerMini[];
  album?: TxAlbumMini;
  file?: TxFileBlock;
}

interface TxCdInfo {
  dissname?: string;
  logo?: string;
  desc?: string;
  nickname?: string;
  visitnum?: number;
  songlist?: TxSongRow[];
}

interface TxDetailBody {
  code?: number;
  cdlist?: TxCdInfo[];
}

interface TxTagGroupOut {
  name: string;
  list: SongListTag[];
}

function filterTagInfo(rawList: TxTagGroupRaw[]): TxTagGroupOut[] {
  const out: TxTagGroupOut[] = [];
  for (let i = 0; i < rawList.length; i++) {
    const type = rawList[i];
    const vItem = type.v_item ?? [];
    const list: SongListTag[] = [];
    for (let j = 0; j < vItem.length; j++) {
      const item = vItem[j];
      const tag: SongListTag = {
        parent_id: String(type.group_id ?? ''),
        parent_name: type.group_name ?? '',
        id: String(item.id ?? ''),
        name: item.name ?? '',
        source: 'tx',
      };
      list.push(tag);
    }
    const grp: TxTagGroupOut = { name: type.group_name ?? '', list };
    out.push(grp);
  }
  return out;
}

function filterInfoHotTag(html: string): SongListTag[] {
  const hotTagHtml = html.match(/class="c_bg_link js_tag_item" data-id="\w+">.+?<\/a>/g);
  const hotTags: SongListTag[] = [];
  if (!hotTagHtml) {
    return hotTags;
  }
  const hotTagRe = /data-id="(\w+)">(.+?)<\/a>/;
  for (let i = 0; i < hotTagHtml.length; i++) {
    const tagHtml = hotTagHtml[i];
    const result = hotTagRe.exec(tagHtml);
    if (!result) {
      continue;
    }
    const ht: SongListTag = {
      id: String(parseInt(result[1], 10)),
      name: result[2],
      source: 'tx',
    };
    hotTags.push(ht);
  }
  return hotTags;
}

function flattenTxTags(groups: TxTagGroupOut[]): SongListTag[] {
  const out: SongListTag[] = [];
  for (let g = 0; g < groups.length; g++) {
    const grp = groups[g];
    for (let i = 0; i < grp.list.length; i++) {
      out.push(grp.list[i]);
    }
  }
  return out;
}

function filterList(data: TxPlaylistData, page: number): SongListResult {
  const v = data.v_playlist ?? [];
  const list: SongListInfo[] = [];
  for (let i = 0; i < v.length; i++) {
    const item = v[i];
    const row: SongListInfo = {
      play_count: formatPlayCount(item.access_num ?? 0),
      id: String(item.tid ?? ''),
      author: item.creator_info?.nick ?? '',
      name: item.title ?? '',
      img: item.cover_url_medium ?? '',
      total: item.song_ids?.length ?? 0,
      desc: decodeName(item.desc ?? '').replace(/<br>/g, '\n'),
      source: 'tx',
    };
    list.push(row);
  }
  const outList: SongListResult = {
    list,
    total: data.total ?? 0,
    page,
    limit: LIMIT_LIST,
    source: 'tx',
  };
  return outList;
}

function filterList2(content: TxPlaylistContentBlock, page: number): SongListResult {
  const vItem = content.v_item ?? [];
  const list: SongListInfo[] = [];
  for (let i = 0; i < vItem.length; i++) {
    const basic = vItem[i].basic;
    if (!basic) {
      continue;
    }
    const row: SongListInfo = {
      play_count: formatPlayCount(basic.play_cnt ?? 0),
      id: String(basic.tid ?? ''),
      author: basic.creator?.nick ?? '',
      name: basic.title ?? '',
      img: basic.cover?.medium_url ?? basic.cover?.default_url ?? '',
      total: 0,
      desc: decodeName(basic.desc ?? '').replace(/<br>/g, '\n'),
      source: 'tx',
    };
    list.push(row);
  }
  const outList2: SongListResult = {
    list,
    total: content.total_cnt ?? 0,
    page,
    limit: LIMIT_LIST,
    source: 'tx',
  };
  return outList2;
}

function filterListDetail(rawList: TxSongRow[]): MusicInfo[] {
  return rawList.map((item: TxSongRow): MusicInfo => {
    const types: MusicQualityType[] = [];
    const _types = new Map<Quality, QualityDetail>();
    const f = item.file;
    if (f) {
      if (f.size_128mp3 !== undefined && f.size_128mp3 !== 0) {
        const size = sizeFormate(f.size_128mp3);
        const q128: MusicQualityType = { type: '128k', size };
        types.push(q128);
        const d128: QualityDetail = { size };
        _types.set('128k', d128);
      }
      if (f.size_320mp3 !== undefined && f.size_320mp3 !== 0) {
        const size = sizeFormate(f.size_320mp3);
        const q320: MusicQualityType = { type: '320k', size };
        types.push(q320);
        const d320: QualityDetail = { size };
        _types.set('320k', d320);
      }
      if (f.size_flac !== undefined && f.size_flac !== 0) {
        const size = sizeFormate(f.size_flac);
        const qf: MusicQualityType = { type: 'flac', size };
        types.push(qf);
        const df: QualityDetail = { size };
        _types.set('flac', df);
      }
      if (f.size_hires !== undefined && f.size_hires !== 0) {
        const size = sizeFormate(f.size_hires);
        const qh: MusicQualityType = { type: 'flac24bit', size };
        types.push(qh);
        const dh: QualityDetail = { size };
        _types.set('flac24bit', dh);
      }
    }
    const album = item.album;
    const albumMid = album?.mid ?? '';
    const albumName = album?.name ?? '';
    const img =
      albumName === '' || albumName === '空'
        ? (item.singer && item.singer.length > 0
          ? `https://y.gtimg.cn/music/photo_new/T001R500x500M000${item.singer[0].mid ?? ''}.jpg`
          : '')
        : `https://y.gtimg.cn/music/photo_new/T002R500x500M000${albumMid}.jpg`;
    const singerRaw = item.singer ?? [];
    const singerArr: SingerInfo[] = [];
    for (let si = 0; si < singerRaw.length; si++) {
      const s = singerRaw[si];
      singerArr.push({ name: s.name ?? '', mid: s.mid });
    }
    const out: MusicInfo = {
      singer: formatSingerName(singerArr, 'name'),
      name: item.title ?? '',
      albumName,
      albumId: albumMid,
      source: 'tx',
      interval: formatPlayTime(item.interval ?? 0),
      songId: item.id,
      songmid: item.mid ?? '',
      strMediaMid: item.file?.media_mid ?? '',
      img,
      lrc: null,
      otherSource: null,
      types,
      _types,
      typeUrl: new Map(),
    };
    return out;
  });
}

const REG_PLAYLIST = /\/playlist\/(\d+)/;
const REG_ID = /id=(\d+)/;

async function getListId(rawId: string): Promise<string> {
  let id = rawId;
  if (/[?&:/]/.test(id)) {
    let m = REG_PLAYLIST.exec(id);
    if (!m) {
      m = REG_ID.exec(id);
    }
    if (m) {
      id = m[1];
    }
  }
  return id;
}

class TxSongListImpl implements TxSongListModule {
  getTags(): Promise<SongListTagsResult> {
    const hJson: Map<string, string> = buildTxBrowserHeaderMap();
    const tagReq: HttpRequestConfig = { header: hJson };
    const p1 = httpRequest(TAGS_URL, tagReq).promise;
    const p2 = httpRequest(HOT_TAG_URL, tagReq).promise;
    return Promise.all([p1, p2]).then((responses) => {
      const emptyTags: SongListTagsResult = { tags: [], hotTag: [], source: 'tx' };
      const tagsBody = parseHttpBodyJson<TxTagsBody>(responses[0].result as string | Object);
      const hotHtml = responses[1].result as string;
      if (!tagsBody || tagsBody.code !== SUCCESS_CODE || !tagsBody.tags?.data?.v_group) {
        return emptyTags;
      }
      const groups = filterTagInfo(tagsBody.tags.data.v_group);
      const hotTag = filterInfoHotTag(hotHtml);
      const ok: SongListTagsResult = {
        tags: flattenTxTags(groups),
        hotTag,
        source: 'tx',
      };
      return ok;
    }).catch((e: Error) => {
      hilog.error(0x0001, 'TXSongList', 'getTags %{public}s', JSON.stringify(e));
      const emptyTags: SongListTagsResult = { tags: [], hotTag: [], source: 'tx' };
      return emptyTags;
    });
  }

  getList(sortId: string, tagId: string, page: number): Promise<SongListResult> {
    const url = getListUrl(sortId, tagId, page);
    const headers: Map<string, string> = buildTxBrowserHeaderMap();
    const listReq: HttpRequestConfig = { header: headers };
    return httpRequest(url, listReq).promise.then((response) => {
      const emptyList: SongListResult = { list: [], total: 0, page, limit: LIMIT_LIST, source: 'tx' };
      const body = parseHttpBodyJson<TxListBody>(response.result as string | Object);
      if (!body || body.code !== SUCCESS_CODE || !body.playlist?.data) {
        return emptyList;
      }
      const data = body.playlist.data;
      const emptyContent: TxPlaylistContentBlock = { v_item: [], total_cnt: 0 };
      return tagId && tagId.length > 0 ? filterList2(data.content ?? emptyContent, page) : filterList(data, page);
    }).catch((e: Error) => {
      hilog.error(0x0001, 'TXSongList', 'getList %{public}s', JSON.stringify(e));
      const emptyList: SongListResult = { list: [], total: 0, page, limit: LIMIT_LIST, source: 'tx' };
      return emptyList;
    });
  }

  getListDetail(listId: string, page: number): Promise<SongListDetailResult> {
    const emptyInfo: SongListDetailInfo = { name: '', img: '', desc: '', author: '', play_count: '' };
    return getListId(listId).then((id) => {
      const url = getListDetailUrl(id);
      const headers: Map<string, string> = buildTxDetailHeaderMap(id);
      const detailReq: HttpRequestConfig = { header: headers };
      return httpRequest(url, detailReq).promise.then((response) => {
        const emptyDetail: SongListDetailResult = {
          list: [],
          info: emptyInfo,
          total: 0,
          source: 'tx',
          page: 1,
          limit: 0,
        };
        const body = parseHttpBodyJson<TxDetailBody>(response.result as string | Object);
        if (!body || body.code !== SUCCESS_CODE || !body.cdlist || body.cdlist.length === 0) {
          return emptyDetail;
        }
        const cd = body.cdlist[0];
        const songs = cd.songlist ?? [];
        const list = filterListDetail(songs);
        const info: SongListDetailInfo = {
          name: cd.dissname ?? '',
          img: cd.logo ?? '',
          desc: decodeName(cd.desc ?? '').replace(/<br>/g, '\n'),
          author: cd.nickname ?? '',
          play_count: formatPlayCount(cd.visitnum ?? 0),
        };
        const okDetail: SongListDetailResult = {
          list,
          info,
          total: songs.length,
          source: 'tx',
          page: 1,
          limit: songs.length + 1,
        };
        return okDetail;
      });
    }).catch(() => {
      const fail: SongListDetailResult = {
        list: [],
        info: emptyInfo,
        total: 0,
        source: 'tx',
        page: 1,
        limit: 0,
      };
      return fail;
    });
  }

  getDetailPageUrl(listId: string): string {
    return `https://y.qq.com/n/ryqq/playlist/${listId}`;
  }
}

export const songList: TxSongListModule = new TxSongListImpl();

export default songList;
