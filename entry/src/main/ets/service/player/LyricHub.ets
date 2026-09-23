/**
 * 歌词中枢（从 PlayerService 抽出）
 *
 * 职责：LRC 解析与时间轴、当前句计算、简繁转换、订阅广播、拉取歌词（走缓存）。
 * 不关心播放器实现，通过 LyricHubHost 拿「当前播放位置 / 当前歌曲 key」，
 * 并在状态变化时回调宿主（宿主负责同步系统播控 / 桌面歌词）。
 *
 * 抽出来的收益：
 * - PlayerService 不再同时承担"播控 + 歌词时间轴"，单一职责；
 * - 时间轴与转换逻辑可独立推演（纯计算 + 一个位置来源），也便于后续加逐字歌词；
 * - 系统播控、桌面歌词、播放页仍然只订阅同一份状态，行为不变。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { parseLrc, getCurrentLyricIndex, type LyricLine } from '../../core/music/MusicParsingUtils';
import { convertChinese } from '../../core/lyric/ChineseConvert';
import { getLyricInfo } from '../../core/music/MusicFeatureEntry';
import { settingsService } from '../SettingsService';
import { playKeyOf } from '../../core/music/PlayKeys';
import type { MusicInfo, LyricInfo } from '../../types/MusicTypes';

const DOMAIN = 0x0002;
const TAG = 'LyricHub';

/** 当前歌词状态（系统播控、桌面歌词、播放页共用） */
export interface LyricLineState {
  hasLyric: boolean;
  index: number;
  current: string;
  next: string;
  next2: string;
}

export type LyricLineListener = (state: LyricLineState) => void;

/** 宿主能力：歌词中枢需要播放器提供的最小上下文 */
export interface LyricHubHost {
  /** 当前播放位置（秒） */
  getPosition: () => number;
  /** 当前歌曲 key（用于丢弃切歌后才返回的过期歌词） */
  getCurrentSongKey: () => string;
  /** 状态变化时同步给系统播控（整段 LRC + 当前句） */
  onStateChanged: (rawLyric: string, currentLine: string) => void;
}

export class LyricHub {
  private lines: LyricLine[] = [];
  /** 已按设置做过简繁转换的歌词文本 */
  private rawText: string = '';
  /** 原始歌词文本（切换简繁设置后可重算） */
  private sourceText: string = '';
  private index: number = -1;
  /** 已发起加载的歌曲 key，避免同一首歌重复请求 */
  private loadKey: string = '';
  private listeners: LyricLineListener[] = [];
  private host: LyricHubHost;

  constructor(host: LyricHubHost) {
    this.host = host;
  }

  /** 订阅当前句变化；订阅时立刻回推一次，避免新订阅者空白 */
  subscribe(listener: LyricLineListener): () => void {
    this.listeners.push(listener);
    try {
      listener(this.getState());
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'listener init failed: %{public}s', JSON.stringify(err));
    }
    return (): void => {
      const at = this.listeners.indexOf(listener);
      if (at > -1) {
        this.listeners.splice(at, 1);
      }
    };
  }

  getState(): LyricLineState {
    return {
      hasLyric: this.lines.length > 0,
      index: this.index,
      current: this.lineAt(this.index),
      next: this.lineAt(this.index + 1),
      next2: this.lineAt(this.index + 2),
    };
  }

  /** 已转换后的歌词文本（播放页展示 / 媒体元数据用） */
  getText(): string {
    return this.rawText;
  }

  hasLyric(): boolean {
    return this.lines.length > 0;
  }

  /** 外部已经拿到歌词时直接喂进来，避免重复请求 */
  setData(lyricText: string): void {
    this.sourceText = lyricText ?? '';
    this.applyConversion();
    this.index = -1;
    this.updateIndex(this.host.getPosition());
  }

  /** 应用简繁转换（切设置后即时生效，无需重新请求歌词） */
  applyConversion(): void {
    const text = convertChinese(this.sourceText, settingsService.get().s2tMode);
    this.rawText = text;
    this.lines = text.length > 0 ? parseLrc(text) : [];
    this.notify();
    this.pushToHost();
  }

  clear(): void {
    this.rawText = '';
    this.sourceText = '';
    this.lines = [];
    this.index = -1;
    this.notify();
  }

  /** 切歌后自动拉取歌词（走歌词缓存，重复播放不重复请求） */
  loadForSong(musicInfo: MusicInfo): void {
    const key = playKeyOf(musicInfo);
    if (key === this.loadKey) {
      return;
    }
    this.loadKey = key;
    this.clear();
    if (!musicInfo.songmid && !musicInfo.id) {
      return;
    }
    getLyricInfo({ musicInfo }).then((info: LyricInfo): void => {
      // 期间可能已切歌，丢弃过期结果
      if (this.host.getCurrentSongKey() !== key) {
        return;
      }
      if (info.lyric && info.lyric.length > 0) {
        this.setData(info.lyric);
      }
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'loadForSong failed: %{public}s', err.message);
    });
  }

  /** 播放进度推进时刷新当前句；行变化才通知（含偏移设置） */
  updateIndex(positionSec: number): void {
    if (this.lines.length === 0) {
      return;
    }
    const next = getCurrentLyricIndex(this.lines, positionSec + settingsService.get().lyricOffset);
    if (next === this.index) {
      return;
    }
    this.index = next;
    this.notify();
    this.pushToHost();
  }

  /** 歌词偏移等设置变化后，强制按当前位置重算（-2 保证必然触发一次通知） */
  refreshIndex(): void {
    this.index = -2;
    this.updateIndex(this.host.getPosition());
  }

  private lineAt(at: number): string {
    return at >= 0 && at < this.lines.length ? this.lines[at].text : '';
  }

  private notify(): void {
    const state = this.getState();
    for (let i = 0; i < this.listeners.length; i++) {
      try {
        this.listeners[i](state);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'listener failed: %{public}s', JSON.stringify(err));
      }
    }
  }

  private pushToHost(): void {
    if (this.lines.length === 0) {
      return;
    }
    this.host.onStateChanged(this.rawText, this.getState().current);
  }
}
