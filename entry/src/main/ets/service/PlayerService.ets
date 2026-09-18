// 播放器服务：列表与订阅在此维护；底层播控统一走 core/playback/AvPlayerPlugin.ets（已移除 plugins/player）。

import hilog from '@ohos.hilog';
import type { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { toggleLoveList, type MusicItem } from './ListService';
import { avSession } from '@kit.AVSessionKit';
import {
  initial as avInitial,
  isInitialized as avIsInitialized,
  setResource as avSetResource,
  setPlay as avSetPlay,
  setPause as avSetPause,
  setStop as avSetStop,
  setCurrentTime as avSetCurrentTime,
  getPosition as avGetPosition,
  getDuration as avGetDuration,
  setVolume as avSetVolume,
  setPlaybackSpeed as avSetPlaybackSpeed,
  updateOptions as avUpdateOptions,
  destroy as avDestroy,
  setOnTrackCompleted,
} from '../core/playback/AvPlayerPlugin';
import { playerState } from '../store/PlayerStoreState';
import type { MusicInfo, MusicSource, Quality } from '../types/MusicTypes';
import { formatPlayTime } from '../utils/CommonUtils';
import { recordPlayedSong } from './PlayHistoryService';
import { backgroundRunningManager, type AvMediaMetadata, type AvSessionCallbacks } from './BackgroundRunningManager';
import { getMusicUrl } from '../core/music/MusicFeatureEntry';
import { settingsService, type PlayMode as SettingsPlayMode } from './SettingsService';
import { on, EventTypes } from './EventBus';

export type { MusicInfo } from '../types/MusicTypes';

// 高品质/默认音质（高品质会按音乐实际支持的音质向下取，见 getPlayQuality）
const HIGH_QUALITY: Quality = 'flac24bit';
const DEFAULT_QUALITY: Quality = '128k';

const TAG = 'PlayerService';
const DOMAIN = 0x0002;

// 播放模式（唯一定义在 SettingsService）
export type { PlayMode } from './SettingsService';
type PlayMode = SettingsPlayMode;

// 播放状态
export type PlayStatus = 'idle' | 'loading' | 'playing' | 'paused' | 'stopped' | 'buffering' | 'error';

// 歌曲信息
export interface SongInfo {
  id: string;
  songmid?: string;
  url: string;
  title: string;
  artist: string;
  album: string;
  artwork: string | null;
  duration: number;
  source?: string; // 音乐源（kw/kg/tx/wy/mg）
  hash?: string;
  strMediaMid?: string;
  songId?: number;
  albumId?: string;
  copyrightId?: string;
}

// 事件监听器类型
type StateChangeListener = (status: PlayStatus) => void;
type ProgressListener = (position: number, duration: number) => void;
type MusicInfoListener = (info: MusicInfo) => void;
type PlayStateListener = (isPlay: boolean) => void;

// 进度信息接口
export interface ProgressInfo {
  nowPlayTime: number;
  maxPlayTime: number;
  progress: number;
  nowPlayTimeStr: string;
  maxPlayTimeStr: string;
}

type ProgressInfoListener = (progress: ProgressInfo) => void;

// 播放器状态存储
interface ProgressData {
  nowPlayTime: number;
  nowPlayTimeStr: string;
  maxPlayTime: number;
  maxPlayTimeStr: string;
  progress: number;
}

interface PlayerStateData {
  musicInfo: MusicInfo;
  isPlay: boolean;
  progress: ProgressData;
  volume: number;
  playRate: number;
}

// 播放器状态实例
const playerStateData: PlayerStateData = {
  musicInfo: {
    id: '',
    name: '',
    singer: '',
    source: 'kw',
    interval: null,
    img: null,
    lrc: null,
  },
  isPlay: false,
  progress: {
    nowPlayTime: 0,
    nowPlayTimeStr: '00:00',
    maxPlayTime: 0,
    maxPlayTimeStr: '00:00',
    progress: 0
  },
  volume: 1.0,
  playRate: 1.0
};

// 进度返回接口
interface ProgressReturnType {
  nowPlayTime: number;
  maxPlayTime: number;
  progress: number;
  nowPlayTimeStr: string;
  maxPlayTimeStr: string;
}

// 播放模式循环顺序（用于播控中心切换时的状态流转）
const LOOP_MODE_ORDER: PlayMode[] = ['listLoop', 'singleLoop', 'random', 'sequential'];

// PlayMode → avSession.LoopMode 映射
function playModeToAvLoopMode(mode: PlayMode): avSession.LoopMode {
  switch (mode) {
    case 'singleLoop':
      return avSession.LoopMode.LOOP_MODE_SINGLE;
    case 'random':
      return avSession.LoopMode.LOOP_MODE_SHUFFLE;
    case 'sequential':
      return avSession.LoopMode.LOOP_MODE_SEQUENCE;
    case 'listLoop':
    default:
      return avSession.LoopMode.LOOP_MODE_LIST;
  }
}

// avSession.LoopMode → PlayMode 映射
function avLoopModeToPlayMode(mode: avSession.LoopMode): PlayMode {
  switch (mode) {
    case avSession.LoopMode.LOOP_MODE_SINGLE:
      return 'singleLoop';
    case avSession.LoopMode.LOOP_MODE_SHUFFLE:
      return 'random';
    case avSession.LoopMode.LOOP_MODE_SEQUENCE:
      return 'sequential';
    case avSession.LoopMode.LOOP_MODE_LIST:
    default:
      return 'listLoop';
  }
}

// 播放器服务类
export class PlayerService {
  private isInitialized: boolean = false;
  private currentStatus: PlayStatus = 'idle';
  private currentSong: SongInfo | null = null;
  private playList: SongInfo[] = [];
  private currentIndex: number = -1;
  private volume: number = 1.0;
  private playbackRate: number = 1.0;
  private progressTimer: number = -1;
  private progressFailCount: number = 0;
  private playMode: PlayMode = 'listLoop';
  /** 首选音质（受"高品质音乐"设置影响） */
  private preferredQuality: Quality = HIGH_QUALITY;
  /** 播放完成的歌曲是否从播放队列移除 */
  private autoCleanPlayedList: boolean = false;
  private settingsListenerRegistered: boolean = false;
  // 随机播放历史（已播歌曲索引，避免短期内重复）
  private randomHistory: number[] = [];

  // 事件监听器数组
  private stateListeners: StateChangeListener[] = [];
  private progressListeners: ProgressListener[] = [];
  private musicInfoListeners: MusicInfoListener[] = [];
  private playStateListeners: PlayStateListener[] = [];
  private progressInfoListeners: ProgressInfoListener[] = [];

  /**
   * 设置上下文。
   * 播放器自身不再直接访问 Preferences（统一走 SettingsService），
   * 这里保留入口是为了与启动流程的解耦：调用方仍需告知"应用已就绪"。
   */
  setContext(_context: common.UIAbilityContext): void {
    // 注册 AVSession 播控回调
    backgroundRunningManager.setCallbacks(this.createAvSessionCallbacks());
    // 设置变化时实时生效（音量/音质/播放模式/自动清理）
    if (!this.settingsListenerRegistered) {
      this.settingsListenerRegistered = true;
      on(EventTypes.SETTING_CHANGED, (): void => {
        this.syncFromSettings();
      });
    }
    this.syncFromSettings();
  }

  /** 把设置快照同步到播放器内部状态（不写回设置，避免循环） */
  private syncFromSettings(): void {
    const settings = settingsService.get();
    if (LOOP_MODE_ORDER.includes(settings.playMode)) {
      this.playMode = settings.playMode;
    }
    this.preferredQuality = settings.highQuality ? HIGH_QUALITY : DEFAULT_QUALITY;
    this.autoCleanPlayedList = settings.autoCleanPlayedList;
    backgroundRunningManager.setLoopMode(playModeToAvLoopMode(this.playMode));

    // 音量跟随设置（0-100 -> 0-1），设置被恢复/同步后也能立即生效
    const targetVolume = settings.volume / 100;
    if (Math.abs(targetVolume - this.volume) > 0.001) {
      this.setVolume(targetVolume).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'Failed to apply volume from settings: %{public}s', err.message);
      });
    }
    hilog.info(DOMAIN, TAG, 'Player settings applied: mode=%{public}s, quality=%{public}s, autoClean=%{public}s',
      this.playMode, this.preferredQuality, this.autoCleanPlayedList.toString());
  }

  /** 创建 AVSession 播控回调 */
  private createAvSessionCallbacks(): AvSessionCallbacks {
    const handleErr = (action: string, err: Error): void => {
      hilog.error(DOMAIN, TAG, 'AVSession %{public}s failed: %{public}s', action, err.message || 'unknown');
    };
    return {
      onPlay: (): void => {
        this.play().catch((err: Error) => handleErr('play', err));
      },
      onPause: (): void => {
        this.pause().catch((err: Error) => handleErr('pause', err));
      },
      onStop: (): void => {
        this.stop().catch((err: Error) => handleErr('stop', err));
      },
      onPlayNext: (): void => {
        this.playNext().catch((err: Error) => handleErr('playNext', err));
      },
      onPlayPrevious: (): void => {
        this.playPrev().catch((err: Error) => handleErr('playPrev', err));
      },
      onSeek: (positionMs: number): void => {
        this.seekTo(positionMs / 1000).catch((err: Error) => handleErr('seek', err));
      },
      onSetLoopMode: (loopMode: avSession.LoopMode): void => {
        // 播控中心传来的 mode 是"当前"状态，应用需要据此切换到"下一个"循环模式
        const currentAvMode = playModeToAvLoopMode(this.playMode);
        if (currentAvMode === loopMode) {
          // 需要切换到下一个模式
          this.cyclePlayMode();
        } else {
          // 直接同步到播控中心传来的模式
          this.setPlayMode(avLoopModeToPlayMode(loopMode));
        }
      },
      onToggleFavorite: (_assetId: string): void => {
        const currentSong = this.getCurrentSong();
        if (!currentSong) {
          hilog.warn(DOMAIN, TAG, 'Toggle favorite: no current song');
          return;
        }
        const musicItem: MusicItem = {
          id: currentSong.id,
          name: currentSong.title,
          singer: currentSong.artist,
          album: currentSong.album,
          albumId: currentSong.albumId || null,
          duration: currentSong.duration,
          source: currentSong.source || 'kw',
          pic: currentSong.artwork || '',
          lrc: null,
        };
        toggleLoveList(musicItem).then((isLoved: boolean) => {
          hilog.info(DOMAIN, TAG, 'Toggle favorite: %{public}s is now %{public}s',
            currentSong.title, isLoved ? 'loved' : 'unloved');
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'Toggle favorite failed: %{public}s', err.message);
        });
      },
    };
  }

  /** 保存播放模式 */
  private async savePlayModeToSettings(): Promise<void> {
    try {
      await settingsService.update({ playMode: this.playMode });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to save playMode: %{public}s', JSON.stringify(err));
    }
  }

  /** 设置播放模式 */
  setPlayMode(mode: PlayMode): void {
    this.playMode = mode;
    backgroundRunningManager.setLoopMode(playModeToAvLoopMode(mode));
    this.savePlayModeToSettings().catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'savePlayModeToSettings failed: %{public}s', err.message);
    });
    hilog.info(DOMAIN, TAG, 'PlayMode set to: %{public}s', mode);
  }

  /** 切换到下一个循环模式 */
  cyclePlayMode(): PlayMode {
    const currentIdx = LOOP_MODE_ORDER.indexOf(this.playMode);
    const nextIdx = currentIdx >= 0 ? (currentIdx + 1) % LOOP_MODE_ORDER.length : 0;
    this.setPlayMode(LOOP_MODE_ORDER[nextIdx]);
    return this.playMode;
  }

  /** 获取当前播放模式 */
  getPlayMode(): PlayMode {
    return this.playMode;
  }

  /** 播放模式对应的中文名 */
  getPlayModeLabel(): string {
    switch (this.playMode) {
      case 'listLoop': return '列表循环';
      case 'singleLoop': return '单曲循环';
      case 'random': return '随机播放';
      case 'sequential': return '顺序播放';
      default: return '列表循环';
    }
  }

  // 初始化播放器（委托 AvPlayerPlugin）
  async init(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'PlayerService init called');

    if (this.isInitialized) {
      hilog.info(DOMAIN, TAG, 'PlayerService already initialized');
      return;
    }

    try {
      playerState.volume = this.volume;
      playerState.playRate = this.playbackRate;

      await avInitial({
        volume: this.volume,
        playRate: this.playbackRate,
        cacheSize: 1024 * 1024,
        isHandleAudioFocus: true,
        isEnableAudioOffload: false,
      });

      setOnTrackCompleted((): void => {
        this.onAvTrackCompleted().catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'onAvTrackCompleted failed: %{public}s', err.message);
        });
      });

      this.isInitialized = avIsInitialized();
      this.currentStatus = 'idle';
      hilog.info(DOMAIN, TAG, 'PlayerService initialized (AvPlayerPlugin)');
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to initialize player: %{public}s', msg);
      this.isInitialized = false;
      this.currentStatus = 'error';
      throw new Error('Failed to initialize AVPlayer: ' + msg);
    }
  }

  /** 歌曲播放完成回调 */
  private async onAvTrackCompleted(): Promise<void> {
    this.stopProgressTimer();
    const finishedSong = this.currentSong;
    this.currentStatus = 'stopped';
    playerStateData.isPlay = false;
    this.notifyStateChange();
    this.notifyPlayStateChange(false);

    // 更新 AVSession 状态
    backgroundRunningManager.updatePlaybackState(false).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'updatePlaybackState failed: %{public}s', err.message);
    });

    // 自动清理已播放列表：单曲循环不清理，其余模式在切歌前把播完的歌移出队列
    if (this.autoCleanPlayedList && this.playMode !== 'singleLoop' && finishedSong) {
      this.removeSongFromQueue(finishedSong);
    }

    switch (this.playMode) {
      case 'singleLoop':
        // 单曲循环：重播当前歌曲
        if (this.currentSong) {
          await this.setSource(this.currentSong, this.currentSong.url);
          await this.play();
        }
        break;
      case 'random':
        // 随机播放：随机选下一首
        await this.playRandomNext();
        break;
      case 'sequential':
        // 顺序播放：播放下一首，到末尾则停止
        if (this.currentIndex < this.playList.length - 1) {
          await this.playNextInternal();
        } else {
          hilog.info(DOMAIN, TAG, 'Sequential mode: end of playlist, stopping');
          backgroundRunningManager.stopBackgroundRunning().catch((err: Error) => {
            hilog.warn(DOMAIN, TAG, 'stopBackgroundRunning failed: %{public}s', err.message);
          });
        }
        break;
      case 'listLoop':
      default:
        // 列表循环：播放下一首，到末尾则回到第一首
        await this.playNextInternal();
        break;
    }
  }

  /**
   * 把播放完成的歌曲从播放队列中移除（"自动清理已播放列表"设置）。
   * 只影响内存中的播放队列，不会删除用户歌单里的歌曲。
   */
  private removeSongFromQueue(song: SongInfo): void {
    const index = this.playList.indexOf(song);
    if (index < 0) {
      return;
    }
    this.playList.splice(index, 1);
    if (index < this.currentIndex) {
      this.currentIndex--;
    } else if (index === this.currentIndex) {
      // 让"下一首"正好落在后移补位的歌曲上（playNextInternal 会用 currentIndex + 1）
      this.currentIndex = index - 1;
    }
    if (this.currentIndex > this.playList.length - 1) {
      this.currentIndex = this.playList.length - 1;
    }
    // 队列索引变化后，随机播放历史需要重新映射，直接清空避免越界
    this.randomHistory = [];
    hilog.info(DOMAIN, TAG, 'Auto cleaned played song from queue: %{public}s (left=%{public}d)',
      song.title, this.playList.length);
  }

  /** 随机播放下一首 */
  private async playRandomNext(): Promise<void> {
    if (this.playList.length === 0) {
      return;
    }
    if (this.playList.length === 1) {
      // 只有一首歌，直接重播
      const song = this.playList[0];
      await this.playSongByIndex(0);
      return;
    }

    // 构建可用索引列表（排除最近播过的歌曲，占播放列表的50%）
    const recentCount = Math.max(1, Math.floor(this.playList.length * 0.5));
    const recent = this.randomHistory.slice(-recentCount);
    const availableIndices: number[] = [];
    for (let i = 0; i < this.playList.length; i++) {
      if (!recent.includes(i)) {
        availableIndices.push(i);
      }
    }

    // 如果所有歌都被排除（极少情况），则全部可用
    const pool = availableIndices.length > 0 ? availableIndices :
      this.playList.map((_, idx) => idx).filter(i => i !== this.currentIndex);

    const randomIdx = pool[Math.floor(Math.random() * pool.length)];
    this.randomHistory.push(randomIdx);
    // 限制历史长度
    if (this.randomHistory.length > 100) {
      this.randomHistory = this.randomHistory.slice(-50);
    }

    await this.playSongByIndex(randomIdx);
  }

  /**
   * 播放指定索引的歌曲（会获取URL）
   * @param respectAutoPlay 为用户手动选歌场景，此时受"自动播放"设置控制
   */
  private async playSongByIndex(index: number, respectAutoPlay: boolean = false): Promise<void> {
    if (index < 0 || index >= this.playList.length) {
      hilog.warn(DOMAIN, TAG, 'playSongByIndex: invalid index %{public}d, listLen=%{public}d', index, this.playList.length);
      return;
    }
    this.currentIndex = index;
    const song = this.playList[index];

    // 如果 URL 为空，需要先从音乐源获取
    let url = song.url;
    if (!url || url.trim().length === 0) {
      hilog.info(DOMAIN, TAG, 'playSongByIndex: URL empty for %{public}s, fetching from music source', song.title);
      url = await this.fetchMusicUrl(song);
      if (!url) {
        hilog.error(DOMAIN, TAG, 'playSongByIndex: failed to get URL for %{public}s', song.title);
        if (this.playMode === 'singleLoop') {
          await this.stop();
        } else if (this.playMode === 'random') {
          const nextIdx = Math.floor(Math.random() * this.playList.length);
          await this.playSongByIndex(nextIdx);
        } else if (index < this.playList.length - 1) {
          // sequential / listLoop: try next song
          await this.playSongByIndex(index + 1);
        } else if (this.playMode === 'listLoop') {
          await this.playSongByIndex(0);
        }
        return;
      }
      // 更新 playlist 中的 url
      this.playList[index].url = url;
    }

    await this.setSource(song, url);
    if (respectAutoPlay && !settingsService.get().autoPlay) {
      hilog.info(DOMAIN, TAG, 'AutoPlay disabled: loaded "%{public}s" without playing', song.title);
      return;
    }
    await this.play();
  }

  /**
   * 播放当前播放列表中的某一首（用户手动选歌入口，会自动获取播放地址）。
   * 受「设置 -> 播放设置 -> 自动播放」控制。
   */
  async playSelectedFromPlayList(index: number): Promise<void> {
    await this.playSongByIndex(index, true);
  }

  /** 内部下一曲实现（处理列表循环） */
  private async playNextInternal(): Promise<void> {
    if (this.playList.length === 0) {
      hilog.info(DOMAIN, TAG, 'Playlist is empty, cannot play next');
      return;
    }

    let nextIndex = this.currentIndex + 1;
    if (nextIndex >= this.playList.length) {
      nextIndex = 0; // 循环到第一首
    }

    await this.playSongByIndex(nextIndex);
  }

  /** 从音乐源获取播放URL */
  private async fetchMusicUrl(song: SongInfo): Promise<string> {
    try {
      const musicInfo: MusicInfo = {
        id: song.id,
        songmid: song.songmid || song.id,
        hash: song.hash,
        strMediaMid: song.strMediaMid,
        songId: song.songId,
        albumId: song.albumId,
        copyrightId: song.copyrightId,
        name: song.title,
        singer: song.artist,
        source: (song.source as MusicSource) || 'kw',
        interval: song.duration > 0 ? formatPlayTime(song.duration) : null,
        img: song.artwork,
        lrc: null,
      };
      const url = await getMusicUrl({ musicInfo, quality: this.preferredQuality });
      if (url) {
        hilog.info(DOMAIN, TAG, 'Fetched URL for %{public}s: %{public}s', song.title, url.substring(0, 80));
        return url;
      }
      hilog.warn(DOMAIN, TAG, 'fetchMusicUrl: no URL returned for %{public}s', song.title);
      return '';
    } catch (err) {
      const msg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'fetchMusicUrl failed for %{public}s: %{public}s', song.title, msg);
      return '';
    }
  }

  /** 更新 AVSession 元数据 */
  private updateAvMetadata(): void {
    const info = playerStateData.musicInfo;
    const progress = playerStateData.progress;
    const imgUrl = info.pic || info.img;
    // assetId 不能为空字符串，否则 setAVMetadata 会失败（HarmonyOS 官方文档要求）
    const assetId = info.id || info.songmid || `track_${Date.now()}`;
    const metadata: AvMediaMetadata = {
      assetId: assetId,
      title: info.name || '未知歌曲',
      artist: info.singer || '未知歌手',
      album: info.albumName || info.album || undefined,
      duration: Math.max(progress.maxPlayTime, 1) * 1000, // duration必须为正数，兼容0的情况兜底为1秒
    };
    if (imgUrl) {
      metadata.mediaImage = imgUrl;
    }
    hilog.info(DOMAIN, TAG, 'updateAvMetadata: title=%{public}s, durationMs=%{public}d, hasImg=%{public}s',
      metadata.title, metadata.duration, String(imgUrl !== null && imgUrl !== undefined));
    backgroundRunningManager.updateMetadata(metadata).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'updateMetadata failed: %{public}s', err.message);
    });
  }

  // 启动进度定时器（轮询 AvPlayerPlugin）
  private startProgressTimer(): void {
    this.stopProgressTimer();
    this.progressFailCount = 0;
    this.progressTimer = setInterval(() => {
      if (this.progressTimer === -1 || this.currentStatus !== 'playing') {
        return;
      }
      const capturedTimerId = this.progressTimer;
      (async (): Promise<void> => {
        try {
          const posSec = await avGetPosition();
          const durSec = await avGetDuration();
          this.progressFailCount = 0;
          this.notifyProgress(posSec, durSec);
        } catch (e) {
          this.progressFailCount++;
          if (this.progressFailCount >= 5) {
            this.stopProgressTimer();
            hilog.warn(DOMAIN, TAG, 'Progress timer stopped after 5 consecutive failures: %{public}s', (e as Error)?.message);
            return;
          }
          hilog.warn(DOMAIN, TAG, 'Progress poll failed (%{public}d/5): %{public}s', this.progressFailCount, (e as Error)?.message);
        }
      })().catch((_err: Error) => {
        // already handled inside
      });
    }, 1000);
  }

  // 停止进度定时器
  private stopProgressTimer(): void {
    if (this.progressTimer !== -1) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
    this.progressFailCount = 0;
  }

  // 通知状态变化
  private notifyStateChange(): void {
    for (let i = 0; i < this.stateListeners.length; i++) {
      try {
        this.stateListeners[i](this.currentStatus);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'state listener failed: %{public}s', JSON.stringify(err));
      }
    }
  }

  // 通知播放状态变化
  private notifyPlayStateChange(isPlay: boolean): void {
    for (let i = 0; i < this.playStateListeners.length; i++) {
      try {
        this.playStateListeners[i](isPlay);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'playState listener failed: %{public}s', JSON.stringify(err));
      }
    }
  }

  // 通知进度变化
  private notifyProgress(position: number, duration: number): void {
    if (duration <= 0) return;

    playerStateData.progress.nowPlayTime = position;
    playerStateData.progress.nowPlayTimeStr = formatPlayTime(position);
    playerStateData.progress.maxPlayTime = duration;
    playerStateData.progress.maxPlayTimeStr = formatPlayTime(duration);
    playerStateData.progress.progress = duration ? position / duration : 0;

    for (let i = 0; i < this.progressListeners.length; i++) {
      try {
        this.progressListeners[i](position, duration);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'progress listener failed: %{public}s', JSON.stringify(err));
      }
    }

    const progressInfo: ProgressInfo = {
      nowPlayTime: position,
      maxPlayTime: duration,
      progress: duration ? position / duration : 0,
      nowPlayTimeStr: formatPlayTime(position),
      maxPlayTimeStr: formatPlayTime(duration)
    };

    for (let i = 0; i < this.progressInfoListeners.length; i++) {
      try {
        this.progressInfoListeners[i](progressInfo);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'progressInfo listener failed: %{public}s', JSON.stringify(err));
      }
    }
  }

  // 设置播放源
  async setSource(song: SongInfo, url: string, duration: number | null = null): Promise<void> {
    if (!this.isInitialized) {
      await this.init();
    }

    // 检查URL是否有效
    if (!url || url.trim().length === 0) {
      hilog.error(DOMAIN, TAG, 'Invalid URL: empty or null for song: %{public}s', song.title);
      this.currentStatus = 'error';
      this.notifyStateChange();
      throw new Error(`Invalid URL for song: ${song.title}`);
    }

    // 检查URL格式
    if (!url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('fd://') && !url.startsWith('file://')) {
      hilog.error(DOMAIN, TAG, 'Invalid URL format: %{public}s for song: %{public}s', url.substring(0, 50), song.title);
      this.currentStatus = 'error';
      this.notifyStateChange();
      throw new Error(`Invalid URL format for song: ${song.title}`);
    }

    hilog.info(DOMAIN, TAG, 'Setting source: %{public}s, url: %{public}s', song.title, url);
    this.currentSong = song;
    this.currentStatus = 'loading';
    this.notifyStateChange();

    const src: MusicSource = (song.source ?? 'local') as MusicSource;
    const art: string | undefined = song.artwork !== null && song.artwork.length > 0 ? song.artwork : undefined;
    const alb: string | undefined = song.album.length > 0 ? song.album : undefined;
    const musicInfo: MusicInfo = {
      id: song.id,
      songmid: song.songmid || song.id,
      hash: song.hash,
      strMediaMid: song.strMediaMid,
      songId: song.songId,
      albumId: song.albumId,
      copyrightId: song.copyrightId,
      img: art ?? null,
      pic: art,
      lrc: null,
      name: song.title,
      singer: song.artist,
      source: src,
      interval: song.duration > 0 ? formatPlayTime(song.duration) : null,
      albumName: alb,
      album: alb,
    };
    playerStateData.musicInfo = musicInfo;
    this.notifyMusicInfoChange();

    try {
      await avSetResource(musicInfo, url, null, false);
      this.currentStatus = 'paused';
      this.notifyStateChange();

      if (duration) {
        playerStateData.progress.maxPlayTime = duration;
        playerStateData.progress.maxPlayTimeStr = formatPlayTime(duration);
      } else if (song.duration > 0) {
        playerStateData.progress.maxPlayTime = song.duration;
        playerStateData.progress.maxPlayTimeStr = formatPlayTime(song.duration);
      }

      // 更新 AVSession 元数据
      this.updateAvMetadata();

      // 在音频播放前创建并激活 AVSession，确保播控中心能感知
      await backgroundRunningManager.initSession();

      // 记录试听历史
      recordPlayedSong({
        id: song.id,
        songmid: song.id,
        name: song.title,
        singer: song.artist,
        album: song.album,
        pic: song.artwork,
        source: song.source || 'kw',
        duration: song.duration,
      }).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'recordPlayedSong failed: %{public}s', err.message);
      });
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to set source: code=%{public}d, name=%{public}s, msg=%{public}s', error.code, error.name || 'unknown', error.message || 'unknown');
      this.currentStatus = 'error';
      this.notifyStateChange();
      const msg: string = error.message || 'Unknown error';
      throw new Error(`AVPlayer setSource failed: ${msg}`);
    }
  }

  /**
   * 用户"选中歌曲"后的统一入口。
   * 受「设置 -> 播放设置 -> 自动播放」控制：关闭时只切换当前歌曲并保持暂停。
   */
  async playFromSelection(song: SongInfo, url: string, duration: number | null = null): Promise<void> {
    await this.setSource(song, url, duration);
    if (settingsService.get().autoPlay) {
      await this.play();
      return;
    }
    hilog.info(DOMAIN, TAG, 'AutoPlay disabled: loaded "%{public}s" without playing', song.title);
  }

  // 通知音乐信息变化
  private notifyMusicInfoChange(): void {
    const musicInfoCopy: MusicInfo = {
      id: playerStateData.musicInfo.id,
      songmid: playerStateData.musicInfo.songmid,
      hash: playerStateData.musicInfo.hash,
      strMediaMid: playerStateData.musicInfo.strMediaMid,
      songId: playerStateData.musicInfo.songId,
      albumId: playerStateData.musicInfo.albumId,
      copyrightId: playerStateData.musicInfo.copyrightId,
      img: playerStateData.musicInfo.img,
      pic: playerStateData.musicInfo.pic,
      lrc: playerStateData.musicInfo.lrc,
      name: playerStateData.musicInfo.name,
      singer: playerStateData.musicInfo.singer,
      source: playerStateData.musicInfo.source,
      interval: playerStateData.musicInfo.interval,
      albumName: playerStateData.musicInfo.albumName ?? undefined,
      album: playerStateData.musicInfo.album ?? undefined,
    };
    for (let i = 0; i < this.musicInfoListeners.length; i++) {
      try {
        this.musicInfoListeners[i](musicInfoCopy);
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'musicInfo listener failed: %{public}s', JSON.stringify(err));
      }
    }
  }

  // 播放
  async play(): Promise<void> {
    if (!this.isInitialized) {
      hilog.error(DOMAIN, TAG, 'Play failed: player not initialized');
      return;
    }

    hilog.info(DOMAIN, TAG, 'Play requested, currentStatus: %{public}s', this.currentStatus);
    try {
      await avSetPlay();
      hilog.info(DOMAIN, TAG, 'Play started successfully');
      this.currentStatus = 'playing';
      playerStateData.isPlay = true;
      this.notifyStateChange();
      this.notifyPlayStateChange(true);
      this.startProgressTimer();

      // 启动后台长时任务（AVSession 已在 setSource 中创建）
      backgroundRunningManager.startBackgroundRunning().catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'startBackgroundRunning failed: %{public}s', err.message);
      });

      // 更新 AVSession 播放状态
      backgroundRunningManager.updatePlaybackState(true,
        playerStateData.progress.nowPlayTime * 1000, this.playbackRate).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'play updatePlaybackState failed: %{public}s', err.message);
      });
    } catch (err) {
      if (err instanceof Error && err.message === 'AVPLAYER_NOT_READY') {
        hilog.warn(DOMAIN, TAG, 'Play skipped: AVPlayer not prepared (setSource may have failed)');
        return;
      }
      const error = err as BusinessError;
      if (error.code === 5400102) {
        hilog.info(DOMAIN, TAG, 'Player already in correct state, play ignored');
        this.currentStatus = 'playing';
        playerStateData.isPlay = true;
        this.notifyPlayStateChange(true);
      } else {
        hilog.error(DOMAIN, TAG, 'Failed to play: code=%{public}d, msg=%{public}s', error.code, error.message || 'unknown');
      }
    }
  }

  // 暂停
  async pause(): Promise<void> {
    if (!this.isInitialized) {
      hilog.error(DOMAIN, TAG, 'Pause failed: player not initialized');
      return;
    }

    hilog.info(DOMAIN, TAG, 'Pause requested');
    try {
      await avSetPause();
      hilog.info(DOMAIN, TAG, 'Pause successful');
      this.currentStatus = 'paused';
      playerStateData.isPlay = false;
      this.notifyStateChange();
      this.notifyPlayStateChange(false);
      this.stopProgressTimer();

      // 更新 AVSession 播放状态
      backgroundRunningManager.updatePlaybackState(false,
        playerStateData.progress.nowPlayTime * 1000).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'pause updatePlaybackState failed: %{public}s', err.message);
      });
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to pause: code=%{public}d, msg=%{public}s', error.code, error.message || 'unknown');
    }
  }

  // 停止
  async stop(): Promise<void> {
    if (!this.isInitialized) {
      return;
    }

    hilog.info(DOMAIN, TAG, 'Stop requested');
    try {
      await avSetStop();
      this.currentStatus = 'stopped';
      playerStateData.isPlay = false;
      this.notifyStateChange();
      this.notifyPlayStateChange(false);
      this.stopProgressTimer();

      // 更新 AVSession 播放状态
      backgroundRunningManager.updatePlaybackState(false).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'stop updatePlaybackState failed: %{public}s', err.message);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to stop: %{public}s', JSON.stringify(err));
    }
  }

  // 跳转
  async seekTo(position: number): Promise<void> {
    if (!this.isInitialized) {
      return;
    }

    hilog.info(DOMAIN, TAG, 'Seek to: %{public}d', position);
    try {
      await avSetCurrentTime(position * 1000);
      this.notifyProgress(position, playerStateData.progress.maxPlayTime);
      // 更新 AVSession 进度
      backgroundRunningManager.updatePlaybackState(
        this.currentStatus === 'playing', position * 1000, this.playbackRate).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'seekTo updatePlaybackState failed: %{public}s', err.message);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to seek: %{public}s', JSON.stringify(err));
    }
  }

  // 设置音量
  async setVolume(volume: number): Promise<void> {
    this.volume = Math.max(0, Math.min(1, volume));
    playerStateData.volume = this.volume;
    playerState.volume = this.volume;

    try {
      await avSetVolume(this.volume);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set volume: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, 'Volume set to: %{public}s', this.volume.toString());
  }

  // 设置播放速率
  async setPlaybackRate(rate: number): Promise<void> {
    this.playbackRate = rate;
    playerStateData.playRate = rate;
    playerState.playRate = rate;

    try {
      await avSetPlaybackSpeed(rate);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set playback rate: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, 'Playback rate set to: %{public}s', rate.toString());
  }

  // 播放下一曲
  async playNext(): Promise<void> {
    if (this.playList.length === 0) {
      hilog.info(DOMAIN, TAG, 'Playlist is empty, cannot play next');
      return;
    }

    if (this.playMode === 'random') {
      await this.playRandomNext();
    } else {
      await this.playNextInternal();
    }
  }

  // 播放上一曲
  async playPrev(): Promise<void> {
    if (this.playList.length === 0) {
      hilog.info(DOMAIN, TAG, 'Playlist is empty, cannot play prev');
      return;
    }

    if (this.playMode === 'random') {
      // 随机模式下，回到随机历史中的上一首
      if (this.randomHistory.length > 1) {
        // 移除当前（最后一项），取上一项
        this.randomHistory.pop();
        const prevIdx = this.randomHistory[this.randomHistory.length - 1];
        await this.playSongByIndex(prevIdx);
      } else {
        // 没有随机历史，随机选一首
        await this.playRandomNext();
      }
      return;
    }

    let prevIndex = this.currentIndex - 1;
    if (prevIndex < 0) {
      prevIndex = this.playList.length - 1; // 循环到最后一首
    }

    await this.playSongByIndex(prevIndex);
  }

  // 设置播放列表（不触发播放）
  setPlayList(list: SongInfo[], startIndex: number = 0): void {
    this.playList = list;
    this.currentIndex = startIndex;
    this.randomHistory = startIndex >= 0 ? [startIndex] : [];
    // 注意：这里不调用setSource，因为URL可能为空
    // 播放应该由调用方在获取到URL后显式调用setSource + play
  }

  // 获取当前播放状态
  getStatus(): PlayStatus {
    return this.currentStatus;
  }

  // 获取当前歌曲信息
  getCurrentSong(): SongInfo | null {
    return this.currentSong;
  }

  // 获取当前音乐信息
  getCurrentMusicInfo(): MusicInfo {
    return {
      id: playerStateData.musicInfo.id,
      songmid: playerStateData.musicInfo.songmid,
      hash: playerStateData.musicInfo.hash,
      strMediaMid: playerStateData.musicInfo.strMediaMid,
      songId: playerStateData.musicInfo.songId,
      albumId: playerStateData.musicInfo.albumId,
      copyrightId: playerStateData.musicInfo.copyrightId,
      img: playerStateData.musicInfo.img,
      pic: playerStateData.musicInfo.pic ?? undefined,
      lrc: playerStateData.musicInfo.lrc,
      name: playerStateData.musicInfo.name,
      singer: playerStateData.musicInfo.singer,
      source: playerStateData.musicInfo.source,
      interval: playerStateData.musicInfo.interval,
      albumName: playerStateData.musicInfo.albumName ?? undefined,
      album: playerStateData.musicInfo.album ?? undefined,
    };
  }

  // 获取当前播放位置
  async getCurrentPosition(): Promise<number> {
    if (!this.isInitialized) {
      return playerStateData.progress.nowPlayTime;
    }
    return await avGetPosition();
  }

  // 获取总时长
  async getDuration(): Promise<number> {
    if (!this.isInitialized) {
      return playerStateData.progress.maxPlayTime;
    }
    return await avGetDuration();
  }

  // 获取进度
  getProgress(): ProgressReturnType {
    return {
      nowPlayTime: playerStateData.progress.nowPlayTime,
      maxPlayTime: playerStateData.progress.maxPlayTime,
      progress: playerStateData.progress.progress,
      nowPlayTimeStr: playerStateData.progress.nowPlayTimeStr,
      maxPlayTimeStr: playerStateData.progress.maxPlayTimeStr
    };
  }

  // 判断是否正在播放
  isPlaying(): boolean {
    return playerStateData.isPlay;
  }

  // 订阅状态变化
  onStatusChange(listener: StateChangeListener): () => void {
    this.stateListeners.push(listener);
    return () => {
      const index = this.stateListeners.indexOf(listener);
      if (index > -1) {
        this.stateListeners.splice(index, 1);
      }
    };
  }

  // 订阅播放进度
  onProgress(listener: ProgressListener): () => void {
    this.progressListeners.push(listener);
    return () => {
      const index = this.progressListeners.indexOf(listener);
      if (index > -1) {
        this.progressListeners.splice(index, 1);
      }
    };
  }

  // 订阅音乐信息变化
  onMusicInfoChange(listener: MusicInfoListener): () => void {
    this.musicInfoListeners.push(listener);
    return () => {
      const index = this.musicInfoListeners.indexOf(listener);
      if (index > -1) {
        this.musicInfoListeners.splice(index, 1);
      }
    };
  }

  // 订阅播放状态变化
  onPlayStateChange(listener: PlayStateListener): () => void {
    this.playStateListeners.push(listener);
    return () => {
      const index = this.playStateListeners.indexOf(listener);
      if (index > -1) {
        this.playStateListeners.splice(index, 1);
      }
    };
  }

  // 订阅进度信息变化
  onProgressInfoChange(listener: ProgressInfoListener): () => void {
    this.progressInfoListeners.push(listener);
    return () => {
      const index = this.progressInfoListeners.indexOf(listener);
      if (index > -1) {
        this.progressInfoListeners.splice(index, 1);
      }
    };
  }

  // 销毁播放器
  async destroy(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'Destroying player...');
    this.stopProgressTimer();
    setOnTrackCompleted(null);

    try {
      await avDestroy();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to destroy player: %{public}s', JSON.stringify(err));
    }

    // 销毁时取消后台长时任务并清理 AVSession
    backgroundRunningManager.destroy().catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'destroy backgroundRunningManager failed: %{public}s', err.message);
    });

    this.isInitialized = false;
    this.currentStatus = 'idle';
    hilog.info(DOMAIN, TAG, 'Player destroyed');
  }

  // 更新播放选项
  async updateOptions(): Promise<void> {
    try {
      await avUpdateOptions();
      hilog.info(DOMAIN, TAG, 'Player options updated');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to update options: %{public}s', JSON.stringify(err));
    }
  }
}

// 导出单例
export const playerService = new PlayerService();

export default playerService;
