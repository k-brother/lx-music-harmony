/**
 * 咪咕音乐 - 歌单（对齐 src/utils/musicSdk/mg/songList.js）
 */
import { httpRequest, parseHttpBodyJson, type HttpRequestConfig } from '../../../../core/network/http';
import type { MusicInfo, MusicQualityType, Quality, QualityDetail } from '../../../../types/MusicTypes';
import { formatPlayCount, sizeFormate, formatPlayTime } from '../../../../utils/CommonUtils';
import type {
  SongListTagsResult,
  SongListResult,
  SongListInfo,
  SongListDetailResult,
  SongListDetailInfo,
  SongListTag,
  SongListSdkInterface,
} from '../MusicSdkContracts';

interface MgSongListModule extends SongListSdkInterface {
  getDetailPageUrl(rawId: string): string;
}

const LIMIT_LIST = 30;
const LIMIT_SONG = 10000;
const SUCCESS_CODE = '000000';
const defaultHeaders: Map<string, string> = new Map([
  ['User-Agent', 'Mozilla/5.0 (iPhone; CPU iPhone OS 13_2_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.0.3 Mobile/15E148 Safari/604.1'],
  ['Referer', 'https://m.music.migu.cn/'],
]);

function createMgHttpConfig(): HttpRequestConfig {
  return { header: defaultHeaders };
}

const TAGS_URL = 'https://app.c.nf.migu.cn/pc/v1.0/template/musiclistplaza-taglist/release';

const cachedDetailInfo: Map<string, SongListDetailInfo> = new Map();

function createEmptyDetailInfo(): SongListDetailInfo {
  return { name: '', img: '', desc: '', author: '', play_count: '' };
}

function createEmptyDetailResult(page: number): SongListDetailResult {
  return {
    list: [],
    info: createEmptyDetailInfo(),
    total: 0,
    source: 'mg',
    page,
    limit: LIMIT_SONG,
  };
}

function getSongListUrl(sortId: string, tagId: string, page: number): string {
  if (!tagId || tagId.length === 0) {
    return `https://app.c.nf.migu.cn/pc/bmw/page-data/playlist-square-recommend/v1.0?templateVersion=2&pageNo=${page}`;
  }
  return `https://app.c.nf.migu.cn/pc/v1.0/template/musiclistplaza-listbytag/release?pageNumber=${page}&templateVersion=2&tagId=${tagId}`;
}

function getSongListDetailUrl(id: string, page: number): string {
  return `https://app.c.nf.migu.cn/MIGUM3.0/resource/playlist/song/v2.0?pageNo=${page}&pageSize=${LIMIT_SONG}&playlistId=${id}`;
}

interface MgTagCell {
  texts?: string[];
}

interface MgTagHeader {
  title?: string;
}

interface MgTagSection {
  header?: MgTagHeader;
  content?: MgTagCell[];
}

interface MgTagsBody {
  code?: string;
  data?: MgTagSection[];
}

interface MgBarItem {
  title?: string;
}

interface MgLogEvent {
  contentId?: string;
}

interface MgContentItem {
  contents?: MgContentItem[];
  resType?: string | number;
  resId?: string;
  txt?: string;
  txt2?: string;
  img?: string;
  barList?: MgBarItem[];
  title?: string;
  imageUrl?: string;
  logEvent?: MgLogEvent;
}

interface MgContentItemListEntry {
  itemList?: MgContentItem[];
}

interface MgListBodyData {
  contents?: MgContentItem[];
  contentItemList?: MgContentItemListEntry[];
}

interface MgListBody {
  code?: string;
  data?: MgListBodyData;
}

interface MgAudioFmt {
  formatType?: string;
  size?: number;
  androidSize?: number;
}

interface MgSingerEntry {
  name?: string;
}

interface MgSongRow {
  songId?: string;
  songName?: string;
  singerList?: MgSingerEntry[];
  album?: string;
  albumId?: string;
  copyrightId?: string;
  duration?: number;
  img1?: string;
  img2?: string;
  img3?: string;
  audioFormats?: MgAudioFmt[];
  lrcUrl?: string;
  mrcUrl?: string;
  trcUrl?: string;
}

interface MgSongListData {
  songList?: MgSongRow[];
  totalCount?: number;
}

interface MgSongListBody {
  code?: string;
  data?: MgSongListData;
}

interface MgImgItem {
  img?: string;
}

interface MgOpNumItem {
  playNum?: number;
}

interface MgPlaylistData {
  title?: string;
  imgItem?: MgImgItem;
  summary?: string;
  ownerName?: string;
  opNumItem?: MgOpNumItem;
}

interface MgPlaylistInfoBody {
  code?: string;
  data?: MgPlaylistData;
}

function formatMgSingers(singerList: MgSingerEntry[] | undefined): string {
  if (!singerList || singerList.length === 0) {
    return '';
  }
  const parts: string[] = [];
  for (let i = 0; i < singerList.length; i++) {
    const n = singerList[i].name;
    if (n) {
      parts.push(n);
    }
  }
  return parts.join('、');
}

function filterMusicInfoListV5(rawList: MgSongRow[]): MusicInfo[] {
  const ids = new Set<string>();
  const list: MusicInfo[] = [];
  for (let i = 0; i < rawList.length; i++) {
    const item = rawList[i];
    const sid = item.songId;
    if (!sid || ids.has(sid)) {
      continue;
    }
    ids.add(sid);
    const types: MusicQualityType[] = [];
    const _types = new Map<Quality, QualityDetail>();
    const fmts = item.audioFormats ?? [];
    for (let f = 0; f < fmts.length; f++) {
      const type = fmts[f];
      const ft = type.formatType;
      let size: string | null = null;
      switch (ft) {
        case 'PQ':
          size = sizeFormate(type.size ?? type.androidSize ?? 0);
          const q128: MusicQualityType = { type: '128k', size };
          types.push(q128);
          const d128: QualityDetail = { size };
          _types.set('128k', d128);
          break;
        case 'HQ':
          size = sizeFormate(type.size ?? type.androidSize ?? 0);
          const q320: MusicQualityType = { type: '320k', size };
          types.push(q320);
          const d320: QualityDetail = { size };
          _types.set('320k', d320);
          break;
        case 'SQ':
          size = sizeFormate(type.size ?? type.androidSize ?? 0);
          const qf: MusicQualityType = { type: 'flac', size };
          types.push(qf);
          const df: QualityDetail = { size };
          _types.set('flac', df);
          break;
        case 'ZQ':
          size = sizeFormate(type.size ?? type.androidSize ?? 0);
          const qh: MusicQualityType = { type: 'flac24bit', size };
          types.push(qh);
          const dh: QualityDetail = { size };
          _types.set('flac24bit', dh);
          break;
        default:
          break;
      }
    }
    const mi: MusicInfo = {
      singer: formatMgSingers(item.singerList),
      name: item.songName ?? '',
      albumName: item.album,
      // 咪咕接口的 albumId/songId 实际是数字，统一转字符串（否则播控元数据被拒收）
      albumId: String(item.albumId ?? ''),
      songmid: String(item.songId ?? ''),
      copyrightId: String(item.copyrightId ?? ''),
      source: 'mg',
      interval: formatPlayTime(item.duration ?? 0),
      img: item.img3 ?? item.img2 ?? item.img1 ?? null,
      lrc: null,
      otherSource: null,
      types,
      _types,
      typeUrl: new Map(),
    };
    list.push(mi);
  }
  return list;
}

function filterTagInfo(rawList: MgTagSection[]): SongListTagsResult {
  if (!rawList || rawList.length === 0) {
    const emptyTags: SongListTagsResult = { tags: [], hotTag: [], source: 'mg' };
    return emptyTags;
  }
  const first = rawList[0];
  const hotCells = first.content ?? [];
  const hotTag: SongListTag[] = [];
  for (let i = 0; i < hotCells.length; i++) {
    const texts = hotCells[i].texts;
    if (texts && texts.length >= 2) {
      const name = texts[0];
      const id = texts[1];
      const ht: SongListTag = { id, name, source: 'mg' };
      hotTag.push(ht);
    }
  }
  const tagsFlat: SongListTag[] = [];
  for (let s = 1; s < rawList.length; s++) {
    const sec = rawList[s];
    const headerTitle = sec.header?.title ?? '';
    const content = sec.content ?? [];
    for (let c = 0; c < content.length; c++) {
      const texts = content[c].texts;
      if (texts && texts.length >= 2) {
        const tg: SongListTag = {
          id: texts[1],
          name: texts[0],
          parent_name: headerTitle,
          source: 'mg',
        };
        tagsFlat.push(tg);
      }
    }
  }
  const tagResult: SongListTagsResult = { tags: tagsFlat, hotTag, source: 'mg' };
  return tagResult;
}

function filterList2(listData: MgContentItem[], list: SongListInfo[] = [], ids: Set<string> = new Set()): SongListInfo[] {
  for (let i = 0; i < listData.length; i++) {
    const item = listData[i];
    if (item.contents) {
      filterList2(item.contents, list, ids);
    } else if (String(item.resType) === '2021' && item.resId && !ids.has(item.resId)) {
      ids.add(item.resId);
      const row: SongListInfo = {
        id: String(item.resId),
        author: '',
        name: item.txt ?? '',
        img: item.img ?? '',
        play_count: '0',
        desc: item.txt2 ?? '',
        total: 0,
        source: 'mg',
      };
      list.push(row);
    }
  }
  return list;
}

function filterList(rawData: MgContentItem[]): SongListInfo[] {
  const list: SongListInfo[] = [];
  for (let i = 0; i < rawData.length; i++) {
    const item = rawData[i];
    const cid = item.logEvent?.contentId;
    if (!cid) {
      continue;
    }
    const row: SongListInfo = {
      play_count: item.barList && item.barList.length > 0 ? (item.barList[0].title ?? '') : '0',
      id: String(cid),
      author: '',
      name: item.title ?? '',
      img: item.imageUrl ?? '',
      desc: '',
      total: 0,
      source: 'mg',
    };
    list.push(row);
  }
  return list;
}

const REG_LIST_DETAIL = /^.+\/playlist\/(\d+)(?:\?.*|&.*$|#.*$|$)/;

interface MgListDetailSongsResult {
  list: MusicInfo[];
  page: number;
  limit: number;
  total: number;
  source: string;
}

function fetchMgListDetailSongs(id: string, page: number): Promise<MgListDetailSongsResult> {
  return httpRequest(getSongListDetailUrl(id, page), createMgHttpConfig()).promise.then((response) => {
    const body = parseHttpBodyJson<MgSongListBody>(response.result as string | Object);
    const emptySongs: MgListDetailSongsResult = { list: [], page, limit: LIMIT_SONG, total: 0, source: 'mg' };
    if (!body || body.code !== SUCCESS_CODE || !body.data) {
      return emptySongs;
    }
    const okSongs: MgListDetailSongsResult = {
      list: filterMusicInfoListV5(body.data.songList ?? []),
      page,
      limit: LIMIT_SONG,
      total: body.data.totalCount ?? 0,
      source: 'mg',
    };
    return okSongs;
  });
}

function fetchMgListDetailMeta(id: string): Promise<SongListDetailInfo> {
  const cached = cachedDetailInfo.get(id);
  if (cached) {
    return Promise.resolve(cached);
  }
  return httpRequest(`https://c.musicapp.migu.cn/MIGUM3.0/resource/playlist/v2.0?playlistId=${id}`, createMgHttpConfig()).promise.then((response) => {
    const body = parseHttpBodyJson<MgPlaylistInfoBody>(response.result as string | Object);
    if (!body || body.code !== SUCCESS_CODE || !body.data) {
      return createEmptyDetailInfo();
    }
    const d = body.data;
    const info: SongListDetailInfo = {
      name: d.title ?? '',
      img: d.imgItem?.img ?? '',
      desc: d.summary ?? '',
      author: d.ownerName ?? '',
      play_count: d.opNumItem?.playNum !== undefined ? formatPlayCount(d.opNumItem.playNum) : '',
    };
    cachedDetailInfo.set(id, info);
    return info;
  });
}

class MgSongListImpl implements MgSongListModule {
  getTags(): Promise<SongListTagsResult> {
    return httpRequest(TAGS_URL, createMgHttpConfig()).promise.then((response) => {
      const body = parseHttpBodyJson<MgTagsBody>(response.result as string | Object);
      const emptyTags: SongListTagsResult = { tags: [], hotTag: [], source: 'mg' };
      if (!body || body.code !== SUCCESS_CODE || !body.data) {
        return emptyTags;
      }
      return filterTagInfo(body.data);
    }).catch(() => {
      const emptyTags: SongListTagsResult = { tags: [], hotTag: [], source: 'mg' };
      return emptyTags;
    });
  }

  getList(sortId: string, tagId: string, page: number): Promise<SongListResult> {
    const url = getSongListUrl(sortId, tagId, page);
    return httpRequest(url, createMgHttpConfig()).promise.then((response) => {
      const body = parseHttpBodyJson<MgListBody>(response.result as string | Object);
      const emptyList: SongListResult = { list: [], total: 0, page, limit: LIMIT_LIST, source: 'mg' };
      if (!body || body.code !== SUCCESS_CODE || !body.data) {
        return emptyList;
      }
      const d = body.data;
      let list: SongListInfo[] = [];
      if (d.contents) {
        list = filterList2(d.contents);
      } else if (d.contentItemList && d.contentItemList.length > 1 && d.contentItemList[1].itemList) {
        list = filterList(d.contentItemList[1].itemList!);
      }
      if (list.length === 0) {
        return emptyList;
      }
      const okList: SongListResult = {
        list,
        total: list.length,
        page,
        limit: LIMIT_LIST,
        source: 'mg',
      };
      return okList;
    }).catch(() => {
      const emptyList: SongListResult = { list: [], total: 0, page, limit: LIMIT_LIST, source: 'mg' };
      return emptyList;
    });
  }

  getListDetail(rawId: string, page: number): Promise<SongListDetailResult> {
    let id = rawId;
    if (/\/playlist[/?]/.test(id)) {
      const parsed = /(?:playlistId|id)=(\d+)/.exec(id);
      id = parsed ? parsed[1] : id;
    } else if (REG_LIST_DETAIL.test(id)) {
      const m = REG_LIST_DETAIL.exec(id);
      id = m ? m[1] : id;
    } else if (/[?&:/]/.test(id)) {
      return Promise.resolve(createEmptyDetailResult(page));
    }

    return Promise.all([
      fetchMgListDetailSongs(id, page),
      fetchMgListDetailMeta(id),
    ]).then((results) => {
      const listData = results[0];
      const info = results[1];
      const okDetail: SongListDetailResult = {
        list: listData.list,
        info,
        total: listData.total,
        source: 'mg',
        page: listData.page,
        limit: listData.limit,
      };
      return okDetail;
    }).catch(() => {
      return createEmptyDetailResult(page);
    });
  }

  getDetailPageUrl(rawId: string): string {
    let id = rawId;
    if (/playlist\/index\.html\?/.test(id)) {
      const m = /.*(?:\?|&)id=(\d+)(?:&.*|$)/.exec(id);
      id = m ? m[1] : id;
    } else if (REG_LIST_DETAIL.test(id)) {
      const m = REG_LIST_DETAIL.exec(id);
      id = m ? m[1] : id;
    }
    return `https://music.migu.cn/v3/music/playlist/${id}`;
  }
}

export const songList: MgSongListModule = new MgSongListImpl();

export default songList;
