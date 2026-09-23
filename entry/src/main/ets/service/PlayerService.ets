// 播放器服务：列表与订阅在此维护；底层播控统一走 core/playback/AvPlayerPlugin.ets（已移除 plugins/player）。

// 日志经由应用日志门面，既输出 hilog 也进入「设置 → 运行日志」
import { appLog as hilog } from '../core/log/AppLogger';
import type { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
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
import { dislikeList } from '../core/dislike/DislikeList';
import { on, EventTypes } from './EventBus';
import { LyricHub } from './player/LyricHub';
import {
  playModeToAvLoopMode,
  buildAvMetadata,
  createAvSessionCallbacks,
} from './player/PlaybackSession';
import {
  nextIndexFor,
  prevIndexFor,
  pickRandomIndex,
  indexAfterRemoval,
  indexAfterMove,
  indexAfterRemoveAt,
  insertNextPlan,
  indexInRefinedList,
  trimRandomHistory,
} from './player/QueueRules';
import type { LyricLineState, LyricLineListener } from './player/LyricHub';
import { playbackEvents } from './player/PlaybackEvents';
import { ProgressPoller } from './player/ProgressPoller';
import {
  savePlaybackSnapshot,
  loadPlaybackSnapshot,
  clearPlaybackSnapshot,
  SAVE_PROGRESS_INTERVAL_MS,
} from './player/PlaybackProgressStore';
import {
  saveQueueSnapshot,
  loadQueueSnapshot,
  clearQueueSnapshot,
  type QueueSnapshot,
} from './player/QueueSnapshot';
import type {
  StateChangeListener,
  PlayStateListener,
  ProgressListener,
  ProgressInfoListener,
  MusicInfoListener,
  TrackCompletedListener,
} from './player/PlaybackEvents';
import type { PlayStatus, ProgressInfo } from './player/PlaybackTypes';
import { songInfoToMusicInfo, validatePlayUrl } from './player/PlaybackInputs';


export type { MusicInfo } from '../types/MusicTypes';
// 歌词状态类型统一由 LyricHub 定义，这里转出以保持既有引用不变
export type { LyricLineState, LyricLineListener };

// 默认音质：真正的取值由设置（player.playQuality）决定，
// 并按音乐实际支持的音质向下取，见 core/music/MusicParsingUtils.getPlayQuality
const DEFAULT_QUALITY: Quality = '128k';

const TAG = 'PlayerService';
const DOMAIN = 0x0002;

// 播放模式（唯一定义在 SettingsService）
export type { PlayMode } from './SettingsService';
type PlayMode = SettingsPlayMode;

// 播放状态与进度类型定义在 service/player/PlaybackTypes，这里 re-export 保持调用方路径不变
export type { PlayStatus, ProgressInfo } from './player/PlaybackTypes';

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

// 事件监听器类型定义在 service/player/PlaybackEvents（订阅中心），本文件只使用

/** 进度保存节流间隔（毫秒） */
// 节流间隔常量由 service/player/PlaybackProgressStore 提供

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

// 播放器服务类
export class PlayerService {
  private isInitialized: boolean = false;
  private currentStatus: PlayStatus = 'idle';
  private currentSong: SongInfo | null = null;
  private playList: SongInfo[] = [];
  private currentIndex: number = -1;
  private volume: number = 1.0;
  private playbackRate: number = 1.0;
  /** 进度轮询器（每秒读一次位置；连续失败自动停表） */
  private poller: ProgressPoller = new ProgressPoller({
    isPlaying: (): boolean => this.currentStatus === 'playing',
    readPosition: (): Promise<number> => avGetPosition(),
    readDuration: (): Promise<number> => avGetDuration(),
    onTick: (position: number, duration: number): void => this.notifyProgress(position, duration),
  });
  private playMode: PlayMode = 'listLoop';
  /** 首选音质（受"高品质音乐"设置影响） */
  private preferredQuality: Quality = DEFAULT_QUALITY;
  /** 播放完成的歌曲是否从播放队列移除 */
  private autoCleanPlayedList: boolean = false;
  private settingsListenerRegistered: boolean = false;
  // 随机播放历史（已播歌曲索引，避免短期内重复）
  private randomHistory: number[] = [];

  // 事件监听器数组
  // 订阅与广播统一由 service/player/PlaybackEvents 承担（原先 6 组样板各写一遍）

  // ===== 歌词状态（唯一数据源）=====
  // ===== 播放进度保存（续播）=====
  /** 启动时恢复的位置（秒），首次播放时生效 */
  private pendingResumePosition: number = 0;
  private lastProgressSavedAt: number = 0;

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
    // 音质：四档可选（128k / 320k / flac / flac24bit），与安卓版 player.playQuality 对齐
    this.preferredQuality = settings.playQuality;
    this.autoCleanPlayedList = settings.autoCleanPlayedList;
    backgroundRunningManager.setLoopMode(playModeToAvLoopMode(this.playMode));
    // 播控封面 / 蓝牙歌词开关（改变后立即用缓存元数据重放，不必等到下一首）
    backgroundRunningManager.setMetadataOptions(settings.showNotificationImage, settings.showBluetoothLyric);

    // 音量跟随设置（0-100 -> 0-1），设置被恢复/同步后也能立即生效
    const targetVolume = settings.volume / 100;
    if (Math.abs(targetVolume - this.volume) > 0.001) {
      this.setVolume(targetVolume).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'Failed to apply volume from settings: %{public}s', err.message);
      });
    }
    // 倍速跟随设置（setPlaybackRate 会写回设置，这里用内部赋值避免回环）
    if (Math.abs(settings.playRate - this.playbackRate) > 0.001) {
      this.playbackRate = settings.playRate;
      playerStateData.playRate = settings.playRate;
      playerState.playRate = settings.playRate;
      avSetPlaybackSpeed(settings.playRate).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'Failed to apply playRate from settings: %{public}s', err.message);
      });
    }
    hilog.info(DOMAIN, TAG, 'Player settings applied: mode=%{public}s, quality=%{public}s, autoClean=%{public}s',
      this.playMode, this.preferredQuality, this.autoCleanPlayedList.toString());
  }

  /** 创建 AVSession 播控回调：实现在 player/PlaybackSession，这里只把播放器动作注入进去 */
  private createAvSessionCallbacks(): AvSessionCallbacks {
    return createAvSessionCallbacks({
      play: (): Promise<void> => this.play(),
      pause: (): Promise<void> => this.pause(),
      stop: (): Promise<void> => this.stop(),
      playNext: (): Promise<void> => this.playNext(),
      playPrev: (): Promise<void> => this.playPrev(),
      seekTo: (seconds: number): Promise<void> => this.seekTo(seconds),
      getPlayMode: (): PlayMode => this.getPlayMode(),
      setPlayMode: (mode: PlayMode): void => this.setPlayMode(mode),
      cyclePlayMode: (): PlayMode => this.cyclePlayMode(),
      getCurrentSong: (): SongInfo | null => this.getCurrentSong(),
    });
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
      // 载入不喜欢规则，供播放时跳过
      await dislikeList.load();

      await avInitial({
        volume: this.volume,
        playRate: this.playbackRate,
        // 三项均来自设置（设置页可调），不再写死
        cacheSize: settingsService.get().playerCacheSizeMb * 1024 * 1024,
        isHandleAudioFocus: settingsService.get().audioFocus,
        isEnableAudioOffload: settingsService.get().audioOffload,
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
    // 先广播"整首播完"，让定时退出等订阅方在切歌前拿到事件
    this.notifyTrackCompleted();
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
        // 顺序播放：播放下一首，到末尾则停止（规则见 QueueRules.nextIndexFor）
        if (nextIndexFor(this.playList.length, this.currentIndex, 'sequential') < 0) {
          hilog.info(DOMAIN, TAG, 'Sequential mode: end of playlist, stopping');
          backgroundRunningManager.stopBackgroundRunning().catch((err: Error) => {
            hilog.warn(DOMAIN, TAG, 'stopBackgroundRunning failed: %{public}s', err.message);
          });
        } else {
          await this.playNextInternal();
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
    const sizeBefore = this.playList.length;
    this.playList.splice(index, 1);
    // 下标换算交给纯函数（含"移除当前时回退一格"的规则）
    this.currentIndex = indexAfterRemoval(sizeBefore, this.currentIndex, index);
    // 索引变化后随机历史会失效，直接清空避免越界
    this.randomHistory = [];
    hilog.info(DOMAIN, TAG, 'Auto cleaned played song from queue: %{public}s (left=%{public}d)',
      song.title, this.playList.length);
    this.persistQueue();
  }

  /** 随机播放下一首（避开当前与最近播放过的一半，避免短时间内重复） */
  private async playRandomNext(): Promise<void> {
    const size = this.playList.length;
    if (size === 0) {
      return;
    }
    if (size === 1) {
      // 只有一首歌，直接重播
      const song = this.playList[0];
      this.randomHistory = [0];
      await this.setSource(song, song.url);
      await this.play();
      return;
    }
    const recentCount = Math.max(1, Math.floor(size * 0.5));
    const exclude = new Set<number>(this.randomHistory.slice(-recentCount));
    const randomIdx = pickRandomIndex(size, this.currentIndex, exclude);
    if (randomIdx < 0) {
      return;
    }
    this.randomHistory.push(randomIdx);
    this.randomHistory = trimRandomHistory(this.randomHistory, 100, 50);
    await this.playSongByIndex(randomIdx);
  }

  /**
   * 播放指定索引的歌曲（会获取URL）
   * @param respectAutoPlay 为用户手动选歌场景，此时受"自动播放"设置控制
   */
  private async playSongByIndex(index: number, respectAutoPlay: boolean = false, skipDepth: number = 0): Promise<void> {
    if (index < 0 || index >= this.playList.length) {
      hilog.warn(DOMAIN, TAG, 'playSongByIndex: invalid index %{public}d, listLen=%{public}d', index, this.playList.length);
      return;
    }
    this.currentIndex = index;
    const song = this.playList[index];
    // 切歌会改当前下标：队列快照同步（否则重启后回到的是旧位置）
    this.persistQueue();

    // 不喜欢列表：命中的歌曲自动跳过（最多跳过整份列表长度，避免死循环）
    if (skipDepth < this.playList.length && dislikeList.isDisliked(song.title, song.artist)) {
      hilog.info(DOMAIN, TAG, 'Skip disliked song: %{public}s - %{public}s', song.title, song.artist);
      const nextIndex = index + 1;
      if (nextIndex < this.playList.length) {
        await this.playSongByIndex(nextIndex, respectAutoPlay, skipDepth + 1);
      } else if (this.playMode === 'listLoop' && this.playList.length > 1) {
        await this.playSongByIndex(0, respectAutoPlay, skipDepth + 1);
      } else {
        hilog.info(DOMAIN, TAG, 'All remaining songs are disliked, stop');
      }
      return;
    }

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

  /** 更新 AVSession 元数据：拼装在 player/PlaybackSession.buildAvMetadata */
  private updateAvMetadata(): void {
    const info = playerStateData.musicInfo;
    const metadata: AvMediaMetadata = buildAvMetadata({
      musicInfo: info,
      durationSeconds: playerStateData.progress.maxPlayTime,
    });
    hilog.info(DOMAIN, TAG, 'updateAvMetadata: title=%{public}s, durationMs=%{public}d, hasImg=%{public}s',
      metadata.title, metadata.duration, String(metadata.mediaImage !== undefined));
    backgroundRunningManager.updateMetadata(metadata).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'updateMetadata failed: %{public}s', err.message);
    });
  }

  // 启动进度定时器（轮询 AvPlayerPlugin）
  /** 启动进度轮询（节奏与失败容错在 player/ProgressPoller） */
  private startProgressTimer(): void {
    this.poller.start();
  }
  private stopProgressTimer(): void {
    this.poller.stop();
  }
  private notifyStateChange(): void {
    playbackEvents.state.emit((listener: StateChangeListener): void => {
      listener(this.currentStatus);
    });
  }

  // 通知播放状态变化
  private notifyPlayStateChange(isPlay: boolean): void {
    playbackEvents.playState.emit((listener: PlayStateListener): void => {
      listener(isPlay);
    });
  }

  // 通知进度变化
  private notifyProgress(position: number, duration: number): void {
    if (duration <= 0) return;

    playerStateData.progress.nowPlayTime = position;
    playerStateData.progress.nowPlayTimeStr = formatPlayTime(position);
    playerStateData.progress.maxPlayTime = duration;
    playerStateData.progress.maxPlayTimeStr = formatPlayTime(duration);
    playerStateData.progress.progress = duration ? position / duration : 0;

    playbackEvents.progress.emit((listener: ProgressListener): void => {
      listener(position, duration);
    });

    // 快照直接复用上面已算好的字段，避免同一组时长格式化两次
    const progressInfo: ProgressInfo = {
      nowPlayTime: playerStateData.progress.nowPlayTime,
      maxPlayTime: playerStateData.progress.maxPlayTime,
      progress: playerStateData.progress.progress,
      nowPlayTimeStr: playerStateData.progress.nowPlayTimeStr,
      maxPlayTimeStr: playerStateData.progress.maxPlayTimeStr,
    };

    // 歌词当前行跟随播放位置推进（内部做了"行未变化不通知"的判断）
    this.updateLyricIndexFromPosition(position);

    // 保存播放进度（节流：默认每 5 秒写一次，避免频繁落盘）
    this.saveProgressThrottled(position);

    playbackEvents.progressInfo.emit((listener: ProgressInfoListener): void => {
      listener(progressInfo);
    });
  }

  // 设置播放源
  async setSource(song: SongInfo, url: string, duration: number | null = null): Promise<void> {
    if (!this.isInitialized) {
      await this.init();
    }

    // 地址先校验：错误信息能指明是哪首歌、什么问题
    this.assertPlayableUrl(song, url);

    hilog.info(DOMAIN, TAG, 'Setting source: %{public}s, url: %{public}s', song.title, url);
    this.currentSong = song;
    this.currentStatus = 'loading';
    this.notifyStateChange();

    const musicInfo: MusicInfo = songInfoToMusicInfo(song);
    playerStateData.musicInfo = musicInfo;
    this.notifyMusicInfoChange();
    // 切歌后异步加载歌词：既喂给系统（锁屏/控制中心/灵动岛），也供桌面歌词使用
    this.loadLyricForSong(musicInfo);

    try {
      await avSetResource(musicInfo, url, null, false);
      this.currentStatus = 'paused';
      this.notifyStateChange();
      this.applyDurationHint(song, duration);

      // 更新 AVSession 元数据
      this.updateAvMetadata();

      // 在音频播放前创建并激活 AVSession，确保播控中心能感知
      await backgroundRunningManager.initSession();
      this.recordPlayedSongSafe(song);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to set source: code=%{public}d, name=%{public}s, msg=%{public}s', error.code, error.name || 'unknown', error.message || 'unknown');
      this.currentStatus = 'error';
      this.notifyStateChange();
      const msg: string = error.message || 'Unknown error';
      throw new Error(`AVPlayer setSource failed: ${msg}`);
    }
  }

  /** 播放地址预校验：不合法直接置错误态并抛出可读原因（上层据此提示/换源） */
  private assertPlayableUrl(song: SongInfo, url: string): void {
    const urlError: string = validatePlayUrl(url, song.title);
    if (urlError.length === 0) {
      return;
    }
    hilog.error(DOMAIN, TAG, 'invalid play url for %{public}s: %{public}s',
      song.title, url.substring(0, 50));
    this.currentStatus = 'error';
    this.notifyStateChange();
    throw new Error(urlError);
  }

  /**
   * 写入总时长：优先用调用方给的真实时长（换源/试听更准），
   * 没有则退回歌曲信息里的时长，都没有就不动（等播放器上报）。
   */
  private applyDurationHint(song: SongInfo, duration: number | null): void {
    const seconds: number = duration && duration > 0 ? duration : song.duration;
    if (seconds > 0) {
      playerStateData.progress.maxPlayTime = seconds;
      playerStateData.progress.maxPlayTimeStr = formatPlayTime(seconds);
    }
  }

  /** 记录试听历史（失败只告警：历史写不进去不该影响播放） */
  private recordPlayedSongSafe(song: SongInfo): void {
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
    playbackEvents.musicInfo.emit((listener: MusicInfoListener): void => {
      listener(this.getCurrentMusicInfo());
    });
  }

  // 播放
  async play(): Promise<void> {
    if (!this.isInitialized) {
      hilog.error(DOMAIN, TAG, 'Play failed: player not initialized');
      return;
    }

    // 续播：应用启动后只恢复了歌曲信息（没有音频源），首次播放时按需准备源并跳到上次位置
    if (this.pendingResumePosition > 0 && this.currentSong) {
      const song = this.currentSong;
      const resumeAt = this.pendingResumePosition;
      this.pendingResumePosition = 0;
      try {
        const url = await this.fetchMusicUrl(song);
        if (url && url.length > 0) {
          await this.setSource(song, url, song.duration);
          await this.seekTo(resumeAt);
          hilog.info(DOMAIN, TAG, 'Resumed playback at %{public}d s: %{public}s', resumeAt, song.title);
        }
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'Resume playback failed: %{public}s',
          err instanceof Error ? err.message : JSON.stringify(err));
      }
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
    // 暂停时立即落盘进度，避免用户直接退出导致进度丢失
    this.saveProgress();

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
    // 停止前落盘进度
    this.saveProgress();
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
    const safeRate = Math.min(Math.max(rate, 0.5), 2.0);
    this.playbackRate = safeRate;
    playerStateData.playRate = safeRate;
    playerState.playRate = safeRate;

    try {
      await avSetPlaybackSpeed(safeRate);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set playback rate: %{public}s', JSON.stringify(err));
    }
    // 倍速也是用户偏好：持久化，下次进 App 仍生效
    settingsService.update({ playRate: safeRate }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'persist playRate failed: %{public}s', err.message);
    });
    hilog.info(DOMAIN, TAG, 'Playback rate set to: %{public}s', safeRate.toString());
  }

  /**
   * 启动阶段应用「上次的倍速」。
   *
   * 刻意不走 setPlaybackRate()：那个入口会把当前值持久化，启动时若用默认值调用
   * （曾经就是 setPlaybackRate(1.0)），会把用户上次选的 1.25x/1.5x 直接抹掉，
   * 表现为「重启后倍速设置丢了」。这里只同步状态 + 交给播放器，不写回设置。
   */
  async applySavedPlaybackRate(): Promise<void> {
    const rate: number = settingsService.get().playRate;
    this.playbackRate = rate;
    playerStateData.playRate = rate;
    playerState.playRate = rate;
    try {
      await avSetPlaybackSpeed(rate);
      hilog.info(DOMAIN, TAG, 'Applied saved playback rate: %{public}s', rate.toString());
    } catch (err) {
      // 播放器可能还没创建：真正的应用会在下一次 setSource 时随 prepare 生效
      hilog.warn(DOMAIN, TAG, 'Deferred saved playback rate: %{public}s', JSON.stringify(err));
    }
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

    // 到队首回到末尾（规则见 QueueRules.prevIndexFor）
    const prevIndex = prevIndexFor(this.playList.length, this.currentIndex);
    if (prevIndex < 0) {
      return;
    }
    await this.playSongByIndex(prevIndex);
  }

  // 设置播放列表（不触发播放）
  setPlayList(list: SongInfo[], startIndex: number = 0): void {
    this.playList = list;
    this.currentIndex = startIndex;
    this.randomHistory = startIndex >= 0 ? [startIndex] : [];
    this.persistQueue();
    // 注意：这里不调用setSource，因为URL可能为空
    // 播放应该由调用方在获取到URL后显式调用setSource + play
  }

  /**
   * 下一首播放：把歌曲插到当前曲目之后（对齐安卓版「下一首播放」）。
   * 队列里没有这首时不重复插入；当前没有播放内容时退化为单曲队列。
   */
  insertNext(song: SongInfo): void {
    if (this.playList.length === 0 || this.currentIndex < 0) {
      this.setPlayList([song], 0);
      return;
    }
    const existsAt = this.playList.findIndex((item: SongInfo) => item.id === song.id);
    const insertAt = this.currentIndex + 1;
    if (existsAt === insertAt) {
      return;
    }
    if (existsAt >= 0) {
      this.playList.splice(existsAt, 1);
      // 插入点与下标换算在 QueueRules（摘掉的位置在当前之前时插入点左移）
      const plan: number[] = insertNextPlan(this.currentIndex, existsAt);
      this.playList.splice(plan[0], 0, song);
      this.currentIndex = plan[1];
    } else {
      this.playList.splice(insertAt, 0, song);
    }
    hilog.info(DOMAIN, TAG, 'Inserted as next: %{public}s (queue=%{public}d, index=%{public}d)',
      song.title, this.playList.length, this.currentIndex);
    this.persistQueue();
  }

  /**
   * 用「更完整的同一张列表」替换队列，并保持当前正在播放的曲目（安卓渐进式 temp list 的效果）。
   * 歌单详情先播已加载的第一页，随后后台补全全部页时调用。
   */
  refineQueueWithFullList(fullList: SongInfo[]): void {
    if (fullList.length === 0 || this.playList.length === 0) {
      return;
    }
    const current = this.playList[this.currentIndex];
    if (!current) {
      return;
    }
    // 队列已经被换掉（用户又点了别的歌单/歌曲）就不再覆盖
    if (this.playList.length > fullList.length) {
      return;
    }
    const nextIndex = indexInRefinedList(fullList, current.id);
    if (nextIndex < 0) {
      return;
    }
    this.playList = fullList;
    this.currentIndex = nextIndex;
    hilog.info(DOMAIN, TAG, 'Queue refined with full list: %{public}d songs, index=%{public}d',
      fullList.length, nextIndex);
    this.persistQueue();
  }

  // 获取当前播放状态
  getStatus(): PlayStatus {
    return this.currentStatus;
  }

  // 获取当前歌曲信息
  getCurrentSong(): SongInfo | null {
    return this.currentSong;
  }

  /** 当前播放队列快照（播放队列面板用） */
  getPlayList(): SongInfo[] {
    return this.playList.slice();
  }

  /** 当前曲目在队列中的下标（无则为 -1） */
  getCurrentIndex(): number {
    return this.currentIndex;
  }

  /**
   * 调整队列顺序（播放队列面板拖动排序）
   *
   * 只改顺序不打断播放：把「当前曲目」的新下标同步回去即可。
   * @returns 是否真的发生了移动
   */
  moveInQueue(from: number, to: number): boolean {
    if (from === to || from < 0 || to < 0
      || from >= this.playList.length || to >= this.playList.length) {
      return false;
    }
    const moved = this.playList.splice(from, 1)[0];
    this.playList.splice(to, 0, moved);
    // 下标换算在 QueueRules（保持「正在播放的那首」不变）
    this.currentIndex = indexAfterMove(this.currentIndex, from, to);
    hilog.info(DOMAIN, TAG, 'Queue reordered: %{public}d -> %{public}d (index=%{public}d)',
      from, to, this.currentIndex);
    this.persistQueue();
    return true;
  }

  /**
   * 从队列移除某一首（播放队列面板长按删除）
   *
   * 移除当前正在播放的那首时不停播，只把 currentIndex 归位到「下一首原来的歌」；
   * 队列被清空则退化为停止后的空队列。
   */
  removeFromQueue(index: number): boolean {
    if (index < 0 || index >= this.playList.length) {
      return false;
    }
    const removed = this.playList.splice(index, 1)[0];
    // 移除的是当前曲目时不停播：下标指向原位置的下一首（越界退回队尾），规则在 QueueRules
    this.currentIndex = indexAfterRemoveAt(this.currentIndex, index, this.playList.length);
    hilog.info(DOMAIN, TAG, 'Removed from queue: %{public}s (queue=%{public}d, index=%{public}d)',
      removed?.title ?? '', this.playList.length, this.currentIndex);
    this.persistQueue();
    return true;
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

  // ==================== 整首播完事件 ====================
  // 供定时退出（"播完当前歌曲再退出"）等场景订阅；每首歌播完触发一次

  onTrackCompleted(listener: TrackCompletedListener): () => void {
    return playbackEvents.trackCompleted.on(listener);
  }

  private notifyTrackCompleted(): void {
    playbackEvents.trackCompleted.emit((listener: TrackCompletedListener): void => {
      listener();
    });
  }

  // 订阅状态变化
  onStatusChange(listener: StateChangeListener): () => void {
    return playbackEvents.state.on(listener);
  }

  // 订阅播放进度
  onProgress(listener: ProgressListener): () => void {
    return playbackEvents.progress.on(listener);
  }

  // 订阅音乐信息变化
  onMusicInfoChange(listener: MusicInfoListener): () => void {
    return playbackEvents.musicInfo.on(listener);
  }

  // 订阅播放状态变化
  onPlayStateChange(listener: PlayStateListener): () => void {
    return playbackEvents.playState.on(listener);
  }

  // 订阅进度信息变化
  onProgressInfoChange(listener: ProgressInfoListener): () => void {
    return playbackEvents.progressInfo.on(listener);
  }

  // ==================== 歌词 ====================

  // ==================== 歌词（委托给 LyricHub） ====================
  // 时间轴、当前句、简繁转换、拉取与订阅都在 service/player/LyricHub.ets，
  // 这里保留对外 API，避免调用方改动；宿主回调负责把状态同步到系统播控。

  private lyricHub: LyricHub = new LyricHub({
    getPosition: (): number => playerStateData.progress.nowPlayTime,
    getCurrentSongKey: (): string => this.currentSongKey(),
    onStateChanged: (rawLyric: string, currentLine: string): void => {
      backgroundRunningManager.updateLyric(rawLyric, currentLine).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'updateLyric failed: %{public}s', err.message);
      });
    },
  });

  /** 当前歌曲的稳定 key（源 + songmid/id），用于丢弃过期的歌词请求 */
  private currentSongKey(): string {
    return `${playerStateData.musicInfo.source ?? ''}_${playerStateData.musicInfo.songmid ?? playerStateData.musicInfo.id ?? ''}`;
  }

  /**
   * 订阅"当前歌词行"变化。
   * 系统播控、桌面歌词、播放页都从这里取，避免各自解析 LRC、各自跑时间轴。
   */
  onLyricLineChange(listener: LyricLineListener): () => void {
    return this.lyricHub.subscribe(listener);
  }

  getLyricState(): LyricLineState {
    return this.lyricHub.getState();
  }

  getLyricText(): string {
    return this.lyricHub.getText();
  }

  /** 外部（播放页）已经拿到歌词时直接喂进来，避免重复请求 */
  setLyricData(lyricText: string): void {
    this.lyricHub.setData(lyricText);
  }

  /** 应用歌词简繁转换（设置变化后即时生效） */
  applyLyricConversion(): void {
    this.lyricHub.applyConversion();
  }

  /** 歌词偏移等设置变化后立即按当前位置重算当前句 */
  refreshLyricIndex(): void {
    this.lyricHub.refreshIndex();
  }

  private loadLyricForSong(musicInfo: MusicInfo): void {
    this.lyricHub.loadForSong(musicInfo);
  }

  private updateLyricIndexFromPosition(positionSec: number): void {
    this.lyricHub.updateIndex(positionSec);
  }

  // ==================== 播放进度保存 / 续播 ====================

  /** 节流保存：默认 5 秒一次 + 暂停/停止时立即保存 */
  private saveProgressThrottled(positionSec: number): void {
    if (!settingsService.get().savePlayTime) {
      return;
    }
    const now = Date.now();
    if (now - this.lastProgressSavedAt < SAVE_PROGRESS_INTERVAL_MS) {
      return;
    }
    this.lastProgressSavedAt = now;
    this.saveProgress(positionSec);
  }

  /** 立即保存当前进度（暂停/停止/退出时调用） */
  saveProgress(positionSec?: number): void {
    const position = positionSec ?? playerStateData.progress.nowPlayTime;
    void savePlaybackSnapshot(this.currentSong, position, settingsService.get().savePlayTime);
  }

  /** 清除进度（用户关闭设置或清空数据时） */
  clearSavedProgress(): void {
    void clearPlaybackSnapshot();
    void clearQueueSnapshot();
  }

  /**
   * 队列落盘的唯一出口。
   *
   * 队列的每一次变更（换列表 / 插队 / 调序 / 移除 / 自动清理 / 切歌）都要走这里，
   * 这样「重启后队列还在」与「队列状态」天然一致；入口分散时漏一处就会出现
   * 「界面里明明加过，重启就没了」这类只有真机能发现的问题。
   */
  private persistQueue(): void {
    void saveQueueSnapshot(this.playList, this.currentIndex, settingsService.get().savePlayTime);
  }

  /**
   * 启动时恢复上次播放的歌曲与位置。
   * 只恢复"歌曲信息 + 待续播位置"，不自动播放；用户点播放时再取源并 seek。
   */
  async restoreLastPlayback(): Promise<void> {
    if (!settingsService.get().savePlayTime) {
      return;
    }
    try {
      const snapshot = await loadPlaybackSnapshot(true);
      if (!snapshot) {
        return;
      }
      const song = snapshot.song;
      this.currentSong = song;
      const savedQueue: QueueSnapshot | null = await loadQueueSnapshot(true);
      this.restoreQueue(song, savedQueue);
      // 与 setSource 用同一份映射（此前这里手写了一遍，字段口径已经出现偏差）
      playerStateData.musicInfo = songInfoToMusicInfo(song);
      playerStateData.progress.nowPlayTime = snapshot.position;
      playerStateData.progress.nowPlayTimeStr = formatPlayTime(snapshot.position);
      playerStateData.progress.progress = 0;
      this.pendingResumePosition = snapshot.position;
      this.currentStatus = 'idle';
      this.notifyMusicInfoChange();
      this.notifyProgress(playerStateData.progress.nowPlayTime, playerStateData.progress.maxPlayTime);
      hilog.info(DOMAIN, TAG, 'Restored last playback: %{public}s @ %{public}d s',
        song.title, snapshot.position);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'restoreLastPlayback failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
    }
  }

  /**
   * 恢复播放队列：优先用队列快照（重启后「下一首/队列面板」仍然可用）；
   * 快照里没有当前这首歌（例如用户中途换过歌）时把它插到队首，保证「当前曲目」一定在队列里。
   */
  private restoreQueue(currentSong: SongInfo, saved: QueueSnapshot | null): void {
    if (!saved || saved.songs.length === 0) {
      this.playList = [currentSong];
      this.currentIndex = 0;
      return;
    }
    const songs: SongInfo[] = saved.songs.slice();
    const at: number = songs.findIndex((item: SongInfo) => item.id === currentSong.id
      && (item.source ?? '') === (currentSong.source ?? ''));
    if (at >= 0) {
      songs[at] = currentSong;
      this.playList = songs;
      this.currentIndex = at;
      return;
    }
    songs.unshift(currentSong);
    this.playList = songs;
    this.currentIndex = 0;
  }

  /** 把整段歌词与当前句推给 AVSession（锁屏/控制中心/灵动岛歌词） */

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
