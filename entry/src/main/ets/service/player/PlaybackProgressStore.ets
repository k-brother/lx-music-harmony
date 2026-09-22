/**
 * 播放进度快照存储（续播用）
 *
 * 只负责「存/取/清」一条快照，不掺业务：恢复时如何回填播放器状态由 PlayerService 决定。
 */
import { getStorageService } from '../../core/interfaces/IStorageService';
import { appLog as hilog } from '../../core/log/AppLogger';
import type { SongInfo } from '../PlayerService';

const DOMAIN = 0x0002;
const TAG = 'PlaybackProgress';
const SNAPSHOT_KEY = 'playback.lastSnapshot';
/** 节流间隔：默认每 5 秒落一次盘 */
export const SAVE_PROGRESS_INTERVAL_MS = 5000;

/** 进度快照 */
export interface PlaybackSnapshot {
  song: SongInfo;
  position: number;
}

/** 保存快照（enabled 由「设置 → 保存播放进度」决定） */
export async function savePlaybackSnapshot(
  song: SongInfo | null, positionSec: number, enabled: boolean
): Promise<void> {
  if (!enabled || !song || !song.title) {
    return;
  }
  const snapshot: PlaybackSnapshot = {
    song,
    position: Math.max(0, Math.floor(positionSec)),
  };
  try {
    await getStorageService().setString(SNAPSHOT_KEY, JSON.stringify(snapshot));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'save snapshot failed: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
  }
}

/** 读取快照（无记录或已关闭续播时返回 null） */
export async function loadPlaybackSnapshot(enabled: boolean): Promise<PlaybackSnapshot | null> {
  if (!enabled) {
    return null;
  }
  try {
    const raw = await getStorageService().getString(SNAPSHOT_KEY, '');
    if (raw.length === 0) {
      return null;
    }
    const snapshot = JSON.parse(raw) as PlaybackSnapshot;
    if (!snapshot || !snapshot.song || !snapshot.song.title) {
      return null;
    }
    return snapshot;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'load snapshot failed: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    return null;
  }
}

/** 清除快照（关闭设置或清空数据时） */
export async function clearPlaybackSnapshot(): Promise<void> {
  try {
    await getStorageService().remove(SNAPSHOT_KEY);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'clear snapshot failed: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
  }
}
