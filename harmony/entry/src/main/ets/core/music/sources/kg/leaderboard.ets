/**
 * 酷狗音乐 - 排行榜（对齐 src/utils/musicSdk/kg/leaderboard.js）
 */
import { httpRequest, type HttpRequestConfig } from '../../../../core/network/http';
import { decodeName, formatPlayTime, sizeFormate } from '../../../../utils/CommonUtils';
import { formatSingerName } from './util';
import type { MusicInfo, MusicQualityType, MusicQualityTypeKg, Quality, QualityDetail } from '../../../../types/MusicTypes';

interface LeaderboardItem {
  id: string;
  name: string;
  bangid: string;
}

/** 与安卓 boardList 一致（安卓 getBoards 当前仍走静态表） */
const KG_STATIC_BOARDS: LeaderboardItem[] = [
  { id: 'kg__8888', name: 'TOP500', bangid: '8888' },
  { id: 'kg__6666', name: '飙升榜', bangid: '6666' },
  { id: 'kg__59703', name: '蜂鸟流行音乐榜', bangid: '59703' },
  { id: 'kg__52144', name: '抖音热歌榜', bangid: '52144' },
  { id: 'kg__52767', name: '快手热歌榜', bangid: '52767' },
  { id: 'kg__24971', name: 'DJ热歌榜', bangid: '24971' },
  { id: 'kg__23784', name: '网络红歌榜', bangid: '23784' },
  { id: 'kg__44412', name: '说唱先锋榜', bangid: '44412' },
  { id: 'kg__31308', name: '内地榜', bangid: '31308' },
  { id: 'kg__33160', name: '电音榜', bangid: '33160' },
  { id: 'kg__31313', name: '香港地区榜', bangid: '31313' },
  { id: 'kg__51341', name: '民谣榜', bangid: '51341' },
  { id: 'kg__54848', name: '台湾地区榜', bangid: '54848' },
  { id: 'kg__31310', name: '欧美榜', bangid: '31310' },
  { id: 'kg__33162', name: 'ACG新歌榜', bangid: '33162' },
  { id: 'kg__31311', name: '韩国榜', bangid: '31311' },
  { id: 'kg__31312', name: '日本榜', bangid: '31312' },
  { id: 'kg__49225', name: '80后热歌榜', bangid: '49225' },
  { id: 'kg__49223', name: '90后热歌榜', bangid: '49223' },
  { id: 'kg__49224', name: '00后热歌榜', bangid: '49224' },
  { id: 'kg__33165', name: '粤语金曲榜', bangid: '33165' },
  { id: 'kg__33166', name: '欧美金曲榜', bangid: '33166' },
  { id: 'kg__33163', name: '影视金曲榜', bangid: '33163' },
  { id: 'kg__51340', name: '伤感榜', bangid: '51340' },
  { id: 'kg__35811', name: '会员专享榜', bangid: '35811' },
  { id: 'kg__37361', name: '雷达榜', bangid: '37361' },
  { id: 'kg__21101', name: '分享榜', bangid: '21101' },
  { id: 'kg__46910', name: '综艺新歌榜', bangid: '46910' },
  { id: 'kg__30972', name: '酷狗音乐人原创榜', bangid: '30972' },
  { id: 'kg__60170', name: '闽南语榜', bangid: '60170' },
  { id: 'kg__65234', name: '儿歌榜', bangid: '65234' },
  { id: 'kg__4681', name: '美国BillBoard榜', bangid: '4681' },
  { id: 'kg__25028', name: 'Beatport电子舞曲榜', bangid: '25028' },
  { id: 'kg__4680', name: '英国单曲榜', bangid: '4680' },
  { id: 'kg__38623', name: '韩国Melon音乐榜', bangid: '38623' },
  { id: 'kg__42807', name: 'joox本地热歌榜', bangid: '42807' },
  { id: 'kg__36107', name: '小语种热歌榜', bangid: '36107' },
  { id: 'kg__4673', name: '日本公信榜', bangid: '4673' },
  { id: 'kg__46868', name: '日本SPACE SHOWER榜', bangid: '46868' },
  { id: 'kg__42808', name: 'KKBOX风云榜', bangid: '42808' },
  { id: 'kg__60171', name: '越南语榜', bangid: '60171' },
  { id: 'kg__60172', name: '泰语榜', bangid: '60172' },
  { id: 'kg__59895', name: 'R&B榜', bangid: '59895' },
  { id: 'kg__59896', name: '摇滚榜', bangid: '59896' },
  { id: 'kg__59897', name: '爵士榜', bangid: '59897' },
  { id: 'kg__59898', name: '乡村音乐榜', bangid: '59898' },
  { id: 'kg__59900', name: '纯音乐榜', bangid: '59900' },
  { id: 'kg__59899', name: '古典榜', bangid: '59899' },
  { id: 'kg__22603', name: '5sing音乐榜', bangid: '22603' },
  { id: 'kg__21335', name: '繁星音乐榜', bangid: '21335' },
  { id: 'kg__33161', name: '古风新歌榜', bangid: '33161' },
];

const defaultBoards: LeaderboardItem[] = [
  { id: 'kgtop500', name: 'TOP500', bangid: '8888' },
  { id: 'kgwlhgb', name: '网络榜', bangid: '23784' },
  { id: 'kgbsb', name: '飙升榜', bangid: '6666' },
  { id: 'kgfxb', name: '分享榜', bangid: '21101' },
  { id: 'kgcyyb', name: '纯音乐榜', bangid: '33164' },
  { id: 'kggfjqb', name: '古风榜', bangid: '33161' },
  { id: 'kgyyjqb', name: '粤语榜', bangid: '33165' },
  { id: 'kgomjqb', name: '欧美榜', bangid: '33166' },
  { id: 'kgdyrgb', name: '电音榜', bangid: '33160' },
  { id: 'kgjdrgb', name: 'DJ热歌榜', bangid: '24971' },
  { id: 'kghyxgb', name: '华语新歌榜', bangid: '31308' },
];

interface LeaderboardResult {
  list: LeaderboardItem[];
  source: string;
}

interface LeaderboardListResult {
  total: number;
  list: MusicInfo[];
  limit: number;
  page: number;
  source: string;
}

interface LeaderboardInterface {
  list: LeaderboardItem[];
  listDetailLimit: number;
  getBoards: () => Promise<LeaderboardResult>;
  getList: (bangid: string, page: number) => Promise<LeaderboardListResult>;
  getDetailPageUrl: (id: string) => string;
  filterData: (rawList: KGMusicItem[]) => MusicInfo[];
}

interface KGRankSongData {
  total: number;
  info: KGMusicItem[];
}

interface KGRankSongResponse {
  errcode: number;
  data: KGRankSongData;
}

interface KMAuthor {
  author_name: string;
}

/** 接口字段含 320filesize / 320hash（与安卓 filterData 一致） */
interface KGMusicItem {
  hash: string;
  audio_id: string;
  songname: string;
  authors: KMAuthor[];
  remark: string;
  album_id: string;
  duration: number;
  filesize: number;
  sqfilesize: number;
  sqhash: string;
  filesize_high: number;
  hash_high: string;
  hash_320?: string;
  filesize_320?: number;
}

interface KGRankListApiRow {
  rankid: number | string;
  rankname: string;
  isvol?: number;
}

interface KGRankListPayload {
  info?: KGRankListApiRow[];
}

interface KGRankListResponse {
  errcode: number;
  data?: KGRankListPayload;
}

interface KgRank320Extract {
  n: number;
  h: string;
}

function kgRankExtract320FromJson(json: string): KgRank320Extract {
  let n = 0;
  let h = '';
  const m1 = /"320filesize"\s*:\s*(\d+)/.exec(json);
  if (m1) {
    n = parseInt(m1[1], 10);
  }
  const m2 = /"320hash"\s*:\s*"([^"]*)"/.exec(json);
  if (m2) {
    h = m2[1];
  }
  const out: KgRank320Extract = { n, h };
  return out;
}

function parseKgHttpJson<T>(raw: string | Object): T {
  if (typeof raw === 'string') {
    return JSON.parse(raw) as T;
  }
  return raw as T;
}

function kgRankListHeaders(): HttpRequestConfig {
  const h: Map<string, string> = new Map();
  h.set('User-Agent', 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 Chrome/119.0.0.0 Mobile Safari/537.36');
  h.set('Referer', 'https://www.kugou.com/');
  const opts: HttpRequestConfig = { header: h };
  return opts;
}

function filterBoardsData(rawList: KGRankListApiRow[]): LeaderboardItem[] {
  const list: LeaderboardItem[] = [];
  for (let i = 0; i < rawList.length; i++) {
    const board = rawList[i];
    if (board.isvol !== 1) {
      continue;
    }
    const bid = String(board.rankid);
    const item: LeaderboardItem = {
      id: 'kg__' + bid,
      name: board.rankname,
      bangid: bid,
    };
    list.push(item);
  }
  return list;
}

class KgLeaderboardImpl implements LeaderboardInterface {
  list: LeaderboardItem[] = defaultBoards;
  listDetailLimit: number = 100;

  async getBoards(): Promise<LeaderboardResult> {
    const url =
      'http://mobilecdnbj.kugou.com/api/v5/rank/list?version=9108&plat=0&showtype=2&parentid=0&apiver=6&area_code=1&withsong=1';
    try {
      const response = await httpRequest(url, kgRankListHeaders()).promise;
      const raw = response.result as string | Object;
      const body = parseKgHttpJson<KGRankListResponse>(raw);
      if (body.errcode === 0 && body.data?.info && body.data.info.length > 0) {
        const list = filterBoardsData(body.data.info);
        if (list.length > 0) {
          this.list = list;
          const ok: LeaderboardResult = { list, source: 'kg' };
          return ok;
        }
      }
    } catch {
      // 回落静态表
    }
    const fallback: LeaderboardResult = { list: KG_STATIC_BOARDS, source: 'kg' };
    this.list = KG_STATIC_BOARDS;
    return fallback;
  }

  async getList(bangid: string, page: number = 1, tryNum: number = 0): Promise<LeaderboardListResult> {
    if (tryNum > 3) {
      const empty: LeaderboardListResult = {
        total: 0,
        list: [],
        limit: this.listDetailLimit,
        page,
        source: 'kg',
      };
      return empty;
    }
    const limit = this.listDetailLimit;
    const url =
      `http://mobilecdnbj.kugou.com/api/v3/rank/song?version=9108&ranktype=1&plat=0&pagesize=${limit}` +
      `&area_code=1&page=${page}&rankid=${bangid}&with_res_tag=0&show_portrait_mv=1`;
    const response = await httpRequest(url, kgRankListHeaders()).promise;
    const body = parseKgHttpJson<KGRankSongResponse>(response.result as string | Object);
    if (body.errcode !== 0) {
      return this.getList(bangid, page, tryNum + 1);
    }
    const list = this.filterData(body.data.info);
    const result: LeaderboardListResult = {
      total: body.data.total,
      list,
      limit,
      page,
      source: 'kg',
    };
    return result;
  }

  getDetailPageUrl(id: string): string {
    let sid = id;
    if (typeof sid === 'string') {
      sid = sid.replace('kg__', '');
    }
    return `https://www.kugou.com/yy/rank/home/1-${sid}.html`;
  }

  filterData(rawList: KGMusicItem[]): MusicInfo[] {
    return rawList.map((item): MusicInfo => {
      const line = JSON.stringify(item);
      const ex320 = kgRankExtract320FromJson(line);
      let n320 = ex320.n;
      let h320 = ex320.h;
      if (n320 === 0 && item.filesize_320 !== undefined && item.filesize_320 !== 0) {
        n320 = item.filesize_320;
      }
      if (h320.length === 0 && item.hash_320 !== undefined && item.hash_320.length > 0) {
        h320 = item.hash_320;
      }

      const types: MusicQualityType[] = [];
      const _types: Map<Quality, QualityDetail> = new Map();

      if (item.filesize !== 0) {
        const size = sizeFormate(item.filesize);
        const t128: MusicQualityTypeKg = { type: '128k', size, hash: item.hash };
        types.push(t128 as MusicQualityType);
        const d128: QualityDetail = { size };
        _types.set('128k', d128);
      }
      if (n320 !== 0) {
        const size = sizeFormate(n320);
        const t320: MusicQualityTypeKg = { type: '320k', size, hash: h320 };
        types.push(t320 as MusicQualityType);
        const d320: QualityDetail = { size };
        _types.set('320k', d320);
      }
      if (item.sqfilesize !== 0) {
        const size = sizeFormate(item.sqfilesize);
        const tf: MusicQualityTypeKg = { type: 'flac', size, hash: item.sqhash };
        types.push(tf as MusicQualityType);
        const df: QualityDetail = { size };
        _types.set('flac', df);
      }
      if (item.filesize_high !== 0) {
        const size = sizeFormate(item.filesize_high);
        const th: MusicQualityTypeKg = { type: 'flac24bit', size, hash: item.hash_high };
        types.push(th as MusicQualityType);
        const dh: QualityDetail = { size };
        _types.set('flac24bit', dh);
      }

      const authorNames: string[] = item.authors.map((a: KMAuthor) => a.author_name);
      const typeUrl: Map<string, string> = new Map();
      const musicInfo: MusicInfo = {
        name: decodeName(item.songname),
        singer: formatSingerName(authorNames),
        source: 'kg',
        songmid: item.audio_id,
        hash: item.hash,
        albumId: item.album_id,
        albumName: decodeName(item.remark),
        interval: formatPlayTime(item.duration),
        img: null,
        lrc: null,
        otherSource: null,
        types,
        _types,
        typeUrl,
      };
      return musicInfo;
    });
  }
}

export const leaderboard: LeaderboardInterface = new KgLeaderboardImpl();

export default leaderboard;
