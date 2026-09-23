import { hilog } from '@kit.PerformanceAnalysisKit';
import { getStorageService } from '../core/interfaces/IStorageService';

const DOMAIN = 0x0006;
const TAG = 'PlayHistoryService';
const PLAY_HISTORY_KEY = 'playHistory';
const MAX_HISTORY_COUNT = 120;

export interface PlayHistoryItem {
  id: string;
  name: string;
  singer: string;
  album: string;
  pic: string;
  source: string;
  duration: number;
  songmid: string;
  playedAt: number;
}

export interface PlayHistoryInput {
  id: string;
  name: string;
  singer?: string;
  album?: string;
  pic?: string | null;
  source?: string;
  duration?: number;
  songmid?: string;
}

function normalizeHistoryItem(input: PlayHistoryInput): PlayHistoryItem | null {
  const id = (input.id || input.songmid || '').trim();
  const name = (input.name || '').trim();
  if (!id || !name) {
    return null;
  }
  return {
    id,
    name,
    singer: (input.singer || '').trim(),
    album: (input.album || '').trim(),
    pic: (input.pic || '').trim(),
    source: (input.source || 'kw').trim(),
    duration: Math.max(0, input.duration || 0),
    songmid: (input.songmid || id).trim(),
    playedAt: Date.now(),
  };
}

export async function getPlayHistory(limit: number = MAX_HISTORY_COUNT): Promise<PlayHistoryItem[]> {
  try {
    const raw = await getStorageService().getString(PLAY_HISTORY_KEY, '[]');
    const parsed = JSON.parse(raw) as PlayHistoryItem[];
    if (!Array.isArray(parsed)) {
      return [];
    }
    return parsed.slice(0, Math.max(0, limit));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'getPlayHistory failed: %{public}s', JSON.stringify(err));
    return [];
  }
}

export async function recordPlayedSong(input: PlayHistoryInput): Promise<void> {
  const item = normalizeHistoryItem(input);
  if (!item) {
    return;
  }
  try {
    const list = await getPlayHistory(MAX_HISTORY_COUNT);
    const deduped: PlayHistoryItem[] = [item];
    for (let i = 0; i < list.length; i++) {
      const cur = list[i];
      if (cur.id === item.id && cur.source === item.source) {
        continue;
      }
      deduped.push(cur);
      if (deduped.length >= MAX_HISTORY_COUNT) {
        break;
      }
    }
    await getStorageService().setString(PLAY_HISTORY_KEY, JSON.stringify(deduped));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'recordPlayedSong failed: %{public}s', JSON.stringify(err));
  }
}

export async function clearPlayHistory(): Promise<void> {
  try {
    await getStorageService().setString(PLAY_HISTORY_KEY, '[]');
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'clearPlayHistory failed: %{public}s', JSON.stringify(err));
  }
}

/**
 * 删除单条播放历史。
 *
 * 同一首歌可能因为听过多次而有多条记录（playedAt 不同），因此按「id + source + playedAt」
 * 三元组定位，避免删掉别的重复项；返回删除后剩下的列表供调用方直接刷新界面。
 */
export async function removePlayHistoryItem(
  id: string, source: string, playedAt: number): Promise<PlayHistoryItem[]> {
  const list = await getPlayHistory(MAX_HISTORY_COUNT);
  const remained: PlayHistoryItem[] = list.filter((item: PlayHistoryItem): boolean =>
    !(item.id === id && item.source === source && item.playedAt === playedAt));
  if (remained.length === list.length) {
    return list;
  }
  try {
    await getStorageService().setString(PLAY_HISTORY_KEY, JSON.stringify(remained));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'removePlayHistoryItem failed: %{public}s', JSON.stringify(err));
  }
  return remained;
}
