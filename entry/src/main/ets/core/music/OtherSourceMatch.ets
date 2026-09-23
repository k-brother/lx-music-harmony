/**
 * 跨源匹配（手动换源用）
 *
 * 从 ResolvePlayback 抽出：拿「歌名 + 歌手」去全源搜索，按相似度排序、每源去重，
 * 返回最像的若干条候选。纯组合逻辑，单独一个文件便于调阈值/看排序效果。
 */
import { searchMusic as sdkSearchMusic } from './MusicSdkAggregate';
import { appLog as hilog } from '../log/AppLogger';
import {
  normalizeSingerText,
  normalizeCompareText,
  scoreCandidate,
  musicInfoTrace,
} from './playback/CandidateMatch';
import type { MusicInfo } from '../../types/MusicTypes';

const TAG = 'ONLINE_MUSIC';
const DOMAIN = 0x0003;

/**
 * 获取其他源的音乐信息
 */
export async function getOtherSource(musicInfo: MusicInfo): Promise<MusicInfo[]> {
  try {
    const safeSinger = normalizeSingerText(musicInfo.singer);
    const keyword = `${musicInfo.name} ${safeSinger}`.trim();
    const baseName = normalizeCompareText(musicInfo.name || '');
    const baseSinger = normalizeCompareText(safeSinger);
    const results = await sdkSearchMusic(keyword, 1, 10);
    if (!results || results.length === 0) {
      hilog.warn(DOMAIN, TAG, 'getOtherSource empty search result: %{public}s', musicInfoTrace(musicInfo));
      return [];
    }
    const merged: MusicInfo[] = [];
    const seenKeys: Set<string> = new Set<string>();
    for (let i = 0; i < results.length; i++) {
      const group = results[i];
      if (!group || !group.list || group.list.length === 0) {
        continue;
      }
      for (let j = 0; j < group.list.length; j++) {
        const item = group.list[j];
        if (!item || item.source === musicInfo.source) {
          continue;
        }
        const itemSinger = normalizeSingerText(item.singer);
        const dedupeKey = `${item.source || ''}|${item.songmid || item.id || ''}|${item.name || ''}|${itemSinger}`;
        if (seenKeys.has(dedupeKey)) {
          continue;
        }
        seenKeys.add(dedupeKey);
        const normalizedItem: MusicInfo = item;
        normalizedItem.singer = itemSinger;
        merged.push(normalizedItem);
      }
    }
    merged.sort((a: MusicInfo, b: MusicInfo) => {
      const sa = scoreCandidate(baseName, baseSinger, a);
      const sb = scoreCandidate(baseName, baseSinger, b);
      return sb - sa;
    });
    const ranked = merged.slice(0, 12);
    hilog.info(DOMAIN, TAG, 'getOtherSource merged=%{public}d ranked=%{public}d for %{public}s',
      merged.length, ranked.length, musicInfoTrace(musicInfo));
    return ranked;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'getOtherSource failed: %{public}s', (err as Error).message);
    return [];
  }
}
