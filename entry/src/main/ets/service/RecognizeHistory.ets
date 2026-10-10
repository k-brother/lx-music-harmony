/**
 * 听歌识曲历史记录
 *
 * 独立 preferences 存储：识曲历史是用户数据（不是设置项），不进设置存储、
 * 也不参与设置快照与备份包，省得每次读写设置都连带它，
 * 上限 20 条；同 trackId 重复识别时去重置顶（RzdMusic 只去重 ID，会堆积同一首歌）。
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { appLog as hilog } from '../core/log/AppLogger';
import type { RecognizedSong } from '../core/music/recognize/RecognitionTypes';

const TAG = 'RecognizeHistory';
const DOMAIN: number = 0x0001;
const STORE_NAME = 'recognize_history';
const HISTORY_KEY = 'history';
const MAX_HISTORY: number = 20;

class RecognizeHistoryService {
  private store: preferences.Preferences | null = null;
  private cache: RecognizedSong[] = [];

  /** 页面进入时挂载（幂等）；未挂载前 getAll 返回空数组 */
  async attach(context: common.Context): Promise<void> {
    if (this.store !== null) {
      return;
    }
    this.store = await preferences.getPreferences(context, STORE_NAME);
    await this.load();
  }

  getAll(): RecognizedSong[] {
    return this.cache;
  }

  async add(song: RecognizedSong): Promise<void> {
    const next: RecognizedSong[] = this.cache.filter((item: RecognizedSong): boolean => item.trackId !== song.trackId);
    next.unshift(song);
    while (next.length > MAX_HISTORY) {
      next.pop();
    }
    this.cache = next;
    await this.persist();
  }

  async clear(): Promise<void> {
    this.cache = [];
    await this.persist();
  }

  private async load(): Promise<void> {
    if (this.store === null) {
      return;
    }
    try {
      const raw: preferences.ValueType = this.store.getSync(HISTORY_KEY, '[]') as preferences.ValueType;
      const parsed: Object = JSON.parse(raw as string) as Object;
      if (Array.isArray(parsed)) {
        this.cache = parsed as RecognizedSong[];
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'load history failed: %{public}s', JSON.stringify(err));
      this.cache = [];
    }
  }

  private async persist(): Promise<void> {
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync(HISTORY_KEY, JSON.stringify(this.cache));
      await this.store.flush();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'persist history failed: %{public}s', JSON.stringify(err));
    }
  }
}

export const recognizeHistory = new RecognizeHistoryService();
