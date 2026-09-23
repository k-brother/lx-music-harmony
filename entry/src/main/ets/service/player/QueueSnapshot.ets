/**
 * 播放队列快照存储（重启后续播整队列用）
 *
 * 此前只存了「最后一首歌 + 位置」：重启后队列被清成单曲，用户点「下一首」直接没反应，
 * 而主流音乐 App 重启后队列面板里还是原来那张列表。
 *
 * 这里只负责序列化与校验：
 * - 落盘前把 `url` 清空（音源地址有时效，重启后必然失效，留着只会让人误以为能直接播）；
 * - 读取时逐条校验（缺 id/标题的丢弃），并限制条数，避免异常数据把存储撑爆；
 * - 与「保存播放进度」共用同一个开关语义（enabled）。
 */
import { getStorageService } from '../../core/interfaces/IStorageService';
import { appLog as hilog } from '../../core/log/AppLogger';
import type { SongInfo } from '../PlayerService';

const DOMAIN = 0x0002;
const TAG = 'QueueSnapshot';
const QUEUE_KEY = 'playback.lastQueue';
/** 队列快照最多存多少首（防异常数据） */
const MAX_SNAPSHOT_SONGS = 300;

/** 队列快照 */
export interface QueueSnapshot {
  songs: SongInfo[];
  index: number;
  savedAt: number;
}

/** 落盘前清洗：去掉时效性字段，只留「重新取源需要的标识」 */
function toPersistable(song: SongInfo): SongInfo {
  return {
    id: song.id,
    songmid: song.songmid,
    url: '',
    title: song.title,
    artist: song.artist,
    album: song.album,
    artwork: song.artwork,
    duration: song.duration,
    source: song.source,
    hash: song.hash,
    strMediaMid: song.strMediaMid,
    songId: song.songId,
    albumId: song.albumId,
    copyrightId: song.copyrightId,
  };
}

/** 读取时校验：缺标识或标题的记录直接丢弃 */
function isValidSong(song: SongInfo | null): boolean {
  return !!song && typeof song.id === 'string' && song.id.length > 0
    && typeof song.title === 'string' && song.title.length > 0;
}

/** 保存队列快照（enabled 由「设置 → 保存播放进度」决定；空队列不写，避免把上次的队列覆盖成空） */
export async function saveQueueSnapshot(
  songs: SongInfo[], index: number, enabled: boolean
): Promise<void> {
  if (!enabled || songs.length === 0) {
    return;
  }
  const sliced: SongInfo[] = songs.slice(0, MAX_SNAPSHOT_SONGS);
  const persistable: SongInfo[] = [];
  for (let i = 0; i < sliced.length; i++) {
    if (isValidSong(sliced[i])) {
      persistable.push(toPersistable(sliced[i]));
    }
  }
  if (persistable.length === 0) {
    return;
  }
  const snapshot: QueueSnapshot = {
    songs: persistable,
    index: Math.max(0, Math.min(index, persistable.length - 1)),
    savedAt: Date.now(),
  };
  try {
    await getStorageService().setString(QUEUE_KEY, JSON.stringify(snapshot));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'save queue failed: %{public}s', JSON.stringify(err));
  }
}

/** 读取队列快照（未开启续播、无记录或数据不可用时返回 null） */
export async function loadQueueSnapshot(enabled: boolean): Promise<QueueSnapshot | null> {
  if (!enabled) {
    return null;
  }
  try {
    const raw = await getStorageService().getString(QUEUE_KEY, '');
    if (raw.length === 0) {
      return null;
    }
    const snapshot = JSON.parse(raw) as QueueSnapshot;
    if (!snapshot || !Array.isArray(snapshot.songs) || snapshot.songs.length === 0) {
      return null;
    }
    const songs: SongInfo[] = [];
    for (let i = 0; i < snapshot.songs.length && songs.length < MAX_SNAPSHOT_SONGS; i++) {
      const song = snapshot.songs[i];
      if (isValidSong(song)) {
        // 地址一律置空：调用方取源时本来就会重新拉
        song.url = '';
        songs.push(song);
      }
    }
    if (songs.length === 0) {
      return null;
    }
    const rawIndex: number = typeof snapshot.index === 'number' ? snapshot.index : 0;
    return {
      songs,
      index: Math.max(0, Math.min(rawIndex, songs.length - 1)),
      savedAt: typeof snapshot.savedAt === 'number' ? snapshot.savedAt : 0,
    };
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'load queue failed: %{public}s', JSON.stringify(err));
    return null;
  }
}

/** 清空队列快照（关闭续播设置 / 清空数据时） */
export async function clearQueueSnapshot(): Promise<void> {
  try {
    await getStorageService().remove(QUEUE_KEY);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'clear queue failed: %{public}s', JSON.stringify(err));
  }
}
