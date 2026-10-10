/**
 * 本地歌的在线歌词匹配（打分 / 自动采用判定 / 逐平台搜索）
 *
 * 移植自 RzdMusic 的 core/LyricMatch.ets（其源头是 listen 的 LyricMatch），
 * 打分与接受条件一字未改（宁缺勿错：配错的歌词比没有歌词更难解释）。
 *
 * 适配点（结合本工程的音源架构）：
 * - 搜索走本工程的 MusicFeatureEntry.searchMusic（按平台、返回 SearchResultItem），
 *   平台清单由调用方传入：core 层不读设置，是否启用/排序由
 *   service 层按「设置 → 音源管理」给出（见 SourcePolicy.orderedEnabledSources）。
 * - MatchSongInfo 保留全量平台身份字段（songmid/hash/copyrightId/albumId/interval）：
 *   本工程 getLyricFromSource 按源分发取词（kw/tx/wy 用 songmid、kg 用 hash+时长、
 *   mg 用 copyrightId），只存 songId 会取不到词；toPlatformMusicInfo 据此还原出
 *   可直接过播放链路的 MusicInfo。
 * - 时长直接用 SearchResultItem.duration（秒），不需要再解析 interval 字符串。
 *
 * 一个已知的保守行差异：searchMusic 内部把网络异常吞掉、返回空结果，
 * 调用方无法区分「接口挂了 / 断网」和「确实没有结果」。listen 靠「请求没抛异常」
 * 判定平台应答过；这里退化成「平台返回了非空结果」才算应答过。
 * 后果：一首在平台上完全搜不到的本地歌会「每次播放重搜一次」。
 * 这个方向是保守的：绝不会因为第一次播放恰好没网而永久失去歌词。
 */
import { appLog as hilog } from '../../log/AppLogger';
import { searchMusic, type SearchResultItem } from '../MusicFeatureEntry';
import type { MusicInfo, MusicSource, MusicQualityType } from '../../../types/MusicTypes';

const DOMAIN: number = 0x0003;
const TAG: string = 'LyricMatch';

/**
 * 本地歌在线匹配到的一条平台歌曲。
 *
 * source + 各源专属 id 是平台身份（取词按源分发，见 ResolvePlayback.getLyricFromSource）；
 * name / singer / durationMs 参与打分；interval 是 kg 取词的兜底线索；
 * img / albumName 供界面展示。
 */
export interface MatchSongInfo {
  /** 平台内的歌曲 id（统一身份，展示与评论用） */
  songId: string;
  name: string;
  singer: string;
  albumName: string;
  albumId: string;
  /** 平台 id：'kw' | 'kg' | 'tx' | 'wy' | 'mg' */
  source: string;
  /** 时长（毫秒，0 = 未知，打分里按「时长未知」处理） */
  durationMs: number;
  /** `mm:ss`；kg 取词的兜底线索（hash 缺失时按 歌名+时长 搜） */
  interval: string;
  img: string;
  /** kw/tx/wy 取词用的 songmid */
  songmid: string;
  /** kg 取词用的 hash */
  hash: string;
  /** mg 取词用的 copyrightId */
  copyrightId: string;
}

/** 差在这个范围内认为「就是同一首」 */
const DURATION_STRONG_MS: number = 3000;
/** 差在这个范围内算弱信号（不足以单独支撑匹配） */
const DURATION_WEAK_MS: number = 8000;
/** 差得比这还多，基本可以断定是另一个版本（现场版、加长版、串烧） */
const DURATION_REJECT_MS: number = 20000;

/** 一条候选的评估结果 */
export interface LyricCandidate {
  info: MatchSongInfo;
  /** 歌名归一化后完全一致 */
  nameExact: boolean;
  /** 歌名是包含关系（`晴天` vs `晴天live`） */
  nameClose: boolean;
  /** 歌手有交集 */
  singerHit: boolean;
  /** 本地歌手未知（标签与文件名都没给） */
  singerUnknown: boolean;
  /** 时长差（毫秒）；-1 = 有一边没有时长，比不了 */
  durationDiffMs: number;
  /** 够不够格自动采用 */
  autoOk: boolean;
  /** 排序用的综合分 */
  score: number;
}

/** 匹配结果：平台 + 那条在线歌 */
export interface LyricMatch {
  source: string;
  info: MatchSongInfo;
}

/** 自动匹配的结果 */
export interface AutoMatchResult {
  /** 匹配到的在线歌（没匹配到就是 null） */
  match: LyricMatch | null;
  /**
   * 至少有一个平台正常应答过。
   *
   * 全平台都请求失败（断网、接口全都不可用）时是 false —— 调用方据此决定
   * **不要**把这次当成「已经搜过了」记下来，否则第一次播放恰好没网的用户
   * 以后有网也永远不会再匹配，等于永久没有歌词。
   */
  searched: boolean;
}

/** 歌名归一化：小写、去掉空白与括号（与 listen/RzdMusic 同一套口径） */
export function normalizeForMatch(name: string): string {
  let out: string = '';
  for (let i: number = 0; i < name.length; i++) {
    const ch: string = name.charAt(i).toLowerCase();
    if (ch === ' ' || ch === '\t' || ch === '（' || ch === '）' || ch === '(' || ch === ')') {
      continue;
    }
    out += ch;
  }
  return out;
}

/** 歌手名拆成一个个名字（搜索结果里常见 `A/B`、`A、B`、`A feat. B`） */
export function singerTokens(singer: string): string[] {
  const out: string[] = [];
  let current: string = '';
  for (let i: number = 0; i < singer.length; i++) {
    const ch: string = singer.charAt(i);
    if (ch === '/' || ch === '、' || ch === ',' || ch === '，' || ch === ';' || ch === '；'
      || ch === '&' || ch === '|' || ch === ' ' || ch === '\t') {
      if (current.length > 0) {
        out.push(current);
        current = '';
      }
      continue;
    }
    current += ch;
  }
  if (current.length > 0) {
    out.push(current);
  }
  return out;
}

function singerHit(localSinger: string, remoteSinger: string): boolean {
  // 先按分隔符拆，再逐个归一化（归一化会吃掉空格，反过来做就拆不开了）
  const local: string[] = singerTokens(localSinger);
  const remote: string[] = singerTokens(remoteSinger);
  if (local.length === 0 || remote.length === 0) {
    return false;
  }
  for (const rawOne of local) {
    const one: string = normalizeForMatch(rawOne);
    // 单个字符的名字（`A`、`李`）容易误命中，要求至少两个字
    if (one.length < 2) {
      continue;
    }
    for (const rawOther of remote) {
      const other: string = normalizeForMatch(rawOther);
      if (other.length < 2) {
        continue;
      }
      if (other === one || other.includes(one) || one.includes(other)) {
        return true;
      }
    }
  }
  return false;
}

/**
 * 给一条候选打分
 *
 * 歌名不一致的直接出局（同名歌太多，靠歌手猜不可靠）；歌名一致之后，
 * 歌手与时长是「第二个信号」，至少要有一个才能自动采用。
 *
 * 本函数与 listen/RzdMusic 的实现逐行一致，不要放宽。
 */
export function scoreCandidate(info: MatchSongInfo, name: string, singer: string,
  durationMs: number): LyricCandidate {
  // 搜索结果是各平台 JSON 拼出来的，字段缺失比类型声明更常见 —— 一律按空串兜底
  const remoteName: string = typeof info.name === 'string' ? info.name : '';
  const remoteSinger: string = typeof info.singer === 'string' ? info.singer : '';
  const target: string = normalizeForMatch(name);
  const candidate: string = normalizeForMatch(remoteName);
  const nameExact: boolean = target.length > 0 && candidate === target;
  const nameClose: boolean = !nameExact && target.length > 1 && candidate.length > 1
    && (candidate.includes(target) || target.includes(candidate));

  const localSinger: string = singer.trim();
  const singerUnknown: boolean = localSinger.length === 0;
  const hit: boolean = !singerUnknown && singerHit(localSinger, remoteSinger);

  const remoteMs: number = info.durationMs > 0 ? info.durationMs : 0;
  let diff: number = -1;
  if (durationMs > 0 && remoteMs > 0) {
    diff = Math.abs(durationMs - remoteMs);
  }

  let score: number = 0;
  if (nameExact) {
    score += 60;
  } else if (nameClose) {
    score += 35;
  }
  if (hit) {
    score += 25;
  }
  if (diff >= 0 && diff <= DURATION_STRONG_MS) {
    score += 15;
  } else if (diff >= 0 && diff <= DURATION_WEAK_MS) {
    score += 8;
  }
  const durationStrong: boolean = diff >= 0 && diff <= DURATION_STRONG_MS;
  const durationTooFar: boolean = diff >= DURATION_REJECT_MS;
  if (durationTooFar) {
    // 时长差太多：多半是另一个版本（现场版 / 串烧 / 加长版），直接判出局
    score = 0;
  }

  // 「宁缺勿错」：歌名完全一致时，歌手或时长有一个对上就采用；
  // 歌名只是包含关系时，要求歌手与时长**都**对上，否则可能配到另一个版本。
  let autoOk: boolean = false;
  if (score > 0 && !durationTooFar) {
    if (nameExact) {
      autoOk = hit || durationStrong;
    } else if (nameClose) {
      autoOk = hit && durationStrong;
    }
  }

  return {
    info: info,
    nameExact: nameExact,
    nameClose: nameClose,
    singerHit: hit,
    singerUnknown: singerUnknown,
    durationDiffMs: diff,
    autoOk: autoOk,
    score: score
  };
}

/** 从候选里挑一条能自动采用的（时长最接近的优先）；没有返回 null */
export function pickAutoMatch(candidates: LyricCandidate[]): MatchSongInfo | null {
  let best: LyricCandidate | null = null;
  for (const candidate of candidates) {
    if (!candidate.autoOk) {
      continue;
    }
    if (best === null) {
      best = candidate;
      continue;
    }
    const better: boolean = candidate.score > best.score
      || (candidate.score === best.score && closerDuration(candidate, best));
    if (better) {
      best = candidate;
    }
  }
  return best === null ? null : best.info;
}

function closerDuration(a: LyricCandidate, b: LyricCandidate): boolean {
  if (a.durationDiffMs < 0) {
    return false;
  }
  if (b.durationDiffMs < 0) {
    return true;
  }
  return a.durationDiffMs < b.durationDiffMs;
}

// ------------------------------------------------------------ 平台搜索适配

/** 平台搜索结果 -> 本文件的 MatchSongInfo（保留全量平台身份字段供取词/取封面） */
export function fromSearchResultItem(item: SearchResultItem): MatchSongInfo {
  const songId: string = typeof item.songmid === 'string' && item.songmid.length > 0
    ? item.songmid : (typeof item.id === 'string' ? item.id : '');
  return {
    songId: songId,
    name: typeof item.name === 'string' ? item.name : '',
    singer: typeof item.singer === 'string' ? item.singer : '',
    albumName: typeof item.album === 'string' ? item.album : '',
    albumId: typeof item.albumId === 'string' ? item.albumId : '',
    source: typeof item.source === 'string' ? item.source : '',
    durationMs: typeof item.duration === 'number' && item.duration > 0 ? item.duration * 1000 : 0,
    interval: typeof item.interval === 'string' ? item.interval : '',
    img: typeof item.pic === 'string' ? item.pic : '',
    songmid: typeof item.songmid === 'string' ? item.songmid : '',
    hash: typeof item.hash === 'string' ? item.hash : '',
    copyrightId: typeof item.copyrightId === 'string' ? item.copyrightId : ''
  };
}

/**
 * MatchSongInfo -> 可直接过播放链路的 MusicInfo。
 *
 * getLyricFromSource 按源分发取词（kw=songmid、kg=hash+时长、tx/wy=songmid、
 * mg=copyrightId），缺哪个都会取不到词，所以这里全量回填。
 */
export function toPlatformMusicInfo(info: MatchSongInfo): MusicInfo {
  const types: MusicQualityType[] = [{ type: '128k', size: null }];
  return {
    id: info.songId,
    name: info.name,
    singer: info.singer,
    source: (info.source.length > 0 ? info.source : 'tx') as MusicSource,
    songmid: info.songmid.length > 0 ? info.songmid : info.songId,
    albumId: info.albumId,
    albumName: info.albumName,
    interval: info.interval.length > 0 ? info.interval : null,
    img: info.img.length > 0 ? info.img : null,
    hash: info.hash.length > 0 ? info.hash : undefined,
    copyrightId: info.copyrightId.length > 0 ? info.copyrightId : undefined,
    lrc: null,
    otherSource: null,
    types: types,
    _types: new Map(),
    typeUrl: new Map(),
  };
}

/** 落盘/取盘用：匹配结果存成 JSON 字符串 */
export function infoToJson(info: MatchSongInfo): string {
  return JSON.stringify(info);
}

/** JSON 字符串 -> MatchSongInfo；解析不了返回 null（字段一律按空串兜底） */
export function infoFromJson(json: string): MatchSongInfo | null {
  if (json.length === 0) {
    return null;
  }
  try {
    const raw: MatchSongInfo = JSON.parse(json) as MatchSongInfo;
    if (raw === null || raw === undefined) {
      return null;
    }
    return {
      songId: typeof raw.songId === 'string' ? raw.songId : '',
      name: typeof raw.name === 'string' ? raw.name : '',
      singer: typeof raw.singer === 'string' ? raw.singer : '',
      albumName: typeof raw.albumName === 'string' ? raw.albumName : '',
      albumId: typeof raw.albumId === 'string' ? raw.albumId : '',
      source: typeof raw.source === 'string' ? raw.source : '',
      durationMs: typeof raw.durationMs === 'number' && raw.durationMs > 0 ? raw.durationMs : 0,
      interval: typeof raw.interval === 'string' ? raw.interval : '',
      img: typeof raw.img === 'string' ? raw.img : '',
      songmid: typeof raw.songmid === 'string' ? raw.songmid : '',
      hash: typeof raw.hash === 'string' ? raw.hash : '',
      copyrightId: typeof raw.copyrightId === 'string' ? raw.copyrightId : ''
    };
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'parse match json failed: %{public}s', JSON.stringify(e));
    return null;
  }
}

/** 在某个平台上搜一批候选（手动匹配面板用） */
export async function searchCandidates(keyword: string, platform: string): Promise<MatchSongInfo[]> {
  const text: string = keyword.trim();
  if (text.length === 0) {
    return [];
  }
  const results: SearchResultItem[] = await searchMusic({
    name: text,
    singer: null,
    source: platform,
    page: 1,
    limit: 20,
  });
  const out: MatchSongInfo[] = [];
  for (let i: number = 0; i < results.length; i++) {
    out.push(fromSearchResultItem(results[i]));
  }
  return out;
}

/**
 * 自动匹配：按调用方给的平台顺序逐个试，找到一条够格的就用它。
 *
 * 某个平台搜不动（网络、接口下线）只记一条日志就换下一个。
 */
export async function autoMatchLyric(name: string, singer: string,
  durationMs: number, platforms: string[]): Promise<AutoMatchResult> {
  if (name.trim().length === 0) {
    return { match: null, searched: false };
  }
  const keyword: string = singer.trim().length > 0 ? `${name} ${singer}` : name;
  let searched: boolean = false;
  for (let i: number = 0; i < platforms.length; i++) {
    const platform: string = platforms[i];
    let results: MatchSongInfo[] = [];
    try {
      results = await searchCandidates(keyword, platform);
    } catch (e) {
      hilog.info(DOMAIN, TAG, 'search on %{public}s failed: %{public}s',
        platform, (e as Error).message);
      continue;
    }
    if (results.length > 0) {
      // searchMusic 把网络异常吞成空结果，所以「有结果」是这里唯一能拿到的应答证据
      searched = true;
    } else {
      continue;
    }
    const candidates: LyricCandidate[] = [];
    for (let j: number = 0; j < results.length; j++) {
      candidates.push(scoreCandidate(results[j], name, singer, durationMs));
    }
    const best: MatchSongInfo | null = pickAutoMatch(candidates);
    if (best !== null) {
      hilog.info(DOMAIN, TAG, 'matched "%{public}s" on %{public}s', name, platform);
      return { match: { source: platform, info: best }, searched: true };
    }
    hilog.info(DOMAIN, TAG, 'no confident match on %{public}s (%{public}d results)',
      platform, results.length);
  }
  return { match: null, searched: searched };
}
