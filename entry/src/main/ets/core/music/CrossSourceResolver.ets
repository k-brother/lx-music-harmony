/**
 * 自动跨源解析：当前源取链失败时，按用户音源顺序去其它源找同一首歌并真实取链。
 *
 * 与手动换源（OtherSourceMatch）的区别：
 * - candidates 由调用方按「音源管理」设置算好传入（尊重停用表与用户排序），最多尝试 MAX_ATTEMPT_SOURCES 个；
 * - 每源搜索回来后先按「歌名 + 歌手 + 时长」打分，只取分数最高的前几个候选去取链，避免对明显不是同一首歌的候选浪费请求；
 * - 取链传 allowToggleSource: false（内部回退链关闭，换源决策全部收敛在本模块），
 *   命中后返回候选完整元数据，由调用方改写播放列表中的歌曲并广播换源事件。
 *
 * 分层约定：不读设置、不弹提示——设置由 service 层读好传入，提示由 UI 层订阅事件。
 */
import type { BuiltinSource } from '../../types/MusicSource';
import type { MusicInfo, Quality } from '../../types/MusicTypes';
import { searchMusic as sdkSearchMusic } from './MusicSdkAggregate';
import { getMusicUrl } from './ResolvePlayback';
import { parseInterval } from './MusicParsingUtils';
import {
  crossSourceCandidates,
  MIN_CROSS_SOURCE_SCORE,
  scoreCrossSourceHit,
} from './SourcePolicy';
import { appLog as hilog } from '../log/AppLogger';

const TAG = 'CROSS_SOURCE';
const DOMAIN = 0x0003;

/** 最多尝试多少个源（搜 + 取链是有真实网络开销的，失控地逐个扫会拖垮切歌体验） */
const MAX_ATTEMPT_SOURCES = 4;
/** 每个源的搜索候选数 */
const SEARCH_LIMIT = 10;
/** 每个源最多对多少个高分候选真实取链 */
const URL_TRY_PER_SOURCE = 2;

/** 跨源命中结果：完整元数据 + 可播放 URL，调用方据此改写歌曲并换源播放 */
export interface CrossSourceHit {
  source: BuiltinSource;
  url: string;
  name: string;
  singer: string;
  id: string;
  songmid: string;
  hash: string;
  strMediaMid: string;
  songId: number;
  albumId: string;
  copyrightId: string;
  pic: string;
}

export interface CrossSourceResolveParams {
  /** 正在播放的歌（原歌曲元数据） */
  title: string;
  artist: string;
  durationSec: number;
  /** 当前（失败的）源 */
  currentSource: BuiltinSource;
  /** orderedEnabledSources 的产物：按用户偏好排序的可用源（service 层算好传入） */
  enabledSources: BuiltinSource[];
  /** 用户期望音质，取链时按歌曲实际支持向下兼容 */
  quality: Quality;
}

interface ScoredCandidate {
  item: MusicInfo;
  score: number;
}

/**
 * 跨源找同一首歌：按序逐源「搜索 → 打分 → 取链」，任一环节命中即返回。
 * 全部失败返回 null（调用方走原有失败逻辑）。
 */
export async function resolveCrossSource(params: CrossSourceResolveParams): Promise<CrossSourceHit | null> {
  const ordered = crossSourceCandidates(params.currentSource, params.enabledSources);
  const attempts = Math.min(ordered.length, MAX_ATTEMPT_SOURCES);
  const keyword = `${params.title} ${params.artist}`.trim();

  for (let i = 0; i < attempts; i++) {
    const source = ordered[i];
    let list: MusicInfo[] = [];
    try {
      const results = await sdkSearchMusic(keyword, 1, SEARCH_LIMIT, source);
      if (results && results.length > 0 && results[0].list) {
        list = results[0].list;
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'search failed on %{public}s: %{public}s',
        source, err instanceof Error ? err.message : JSON.stringify(err));
      continue;
    }
    if (list.length === 0) {
      continue;
    }

    const scored: ScoredCandidate[] = [];
    for (let j = 0; j < list.length; j++) {
      const item = list[j];
      const candidateDuration = item.interval ? parseInterval(item.interval) : 0;
      const score = scoreCrossSourceHit(
        params.title, params.artist, params.durationSec,
        item.name || '', item.singer || '', candidateDuration
      );
      if (score >= MIN_CROSS_SOURCE_SCORE) {
        scored.push({ item: item, score: score });
      }
    }
    if (scored.length === 0) {
      hilog.info(DOMAIN, TAG, 'no candidate on %{public}s for %{public}s - %{public}s',
        source, params.title, params.artist);
      continue;
    }
    scored.sort((a: ScoredCandidate, b: ScoredCandidate): number => b.score - a.score);

    const tries = scored.slice(0, URL_TRY_PER_SOURCE);
    for (let k = 0; k < tries.length; k++) {
      const item = tries[k].item;
      try {
        // 关闭 ResolvePlayback 内部换源回退：换源决策收敛在本模块，失败即 null
        const url = await getMusicUrl({
          musicInfo: item,
          quality: params.quality,
          allowToggleSource: false,
        });
        if (url && url.length > 0) {
          hilog.info(DOMAIN, TAG, 'resolved on %{public}s (score %{public}d) for %{public}s',
            source, tries[k].score, params.title);
          return {
            source: source,
            url: url,
            name: item.name || '',
            singer: item.singer || '',
            id: item.id || '',
            songmid: item.songmid || '',
            hash: item.hash || '',
            strMediaMid: item.strMediaMid || '',
            songId: item.songId || 0,
            albumId: item.albumId || '',
            copyrightId: item.copyrightId || '',
            pic: item.img || item.pic || '',
          };
        }
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'getMusicUrl failed on %{public}s: %{public}s',
          source, err instanceof Error ? err.message : JSON.stringify(err));
      }
    }
  }
  return null;
}
