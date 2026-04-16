// 播放器服务：列表与订阅在此维护；底层播控统一走 core/playback/AvPlayerPlugin.ets（已移除 plugins/player）。

import hilog from '@ohos.hilog';
import { BusinessError } from '@kit.BasicServicesKit';
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
import type { MusicInfo, MusicSource } from '../types/MusicTypes';
import { formatPlayTime } from '../utils/CommonUtils';
import { recordPlayedSong } from './PlayHistoryService';

export type { MusicInfo } from '../types/MusicTypes';

const TAG = 'PlayerService';
const DOMAIN = 0x0002;

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

// 播放器服务类
// 导出单例
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

  // 事件监听器数组
  private stateListeners: StateChangeListener[] = [];
  private progressListeners: ProgressListener[] = [];
  private musicInfoListeners: MusicInfoListener[] = [];
  private playStateListeners: PlayStateListener[] = [];
  private progressInfoListeners: ProgressInfoListener[] = [];

  // 初始化播放器（委托 AvPlayerPlugin）
  async init(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'PlayerService init called');

    if (this.isInitialized) {
      hilog.info(DOMAIN, TAG, 'PlayerService already initialized');
      return;
    }

    try {
      hilog.info(DOMAIN, TAG, 'Skipping media permissions for network audio playback');

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
        void this.onAvTrackCompleted();
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

  private async onAvTrackCompleted(): Promise<void> {
    this.stopProgressTimer();
    this.currentStatus = 'stopped';
    playerStateData.isPlay = false;
    this.notifyStateChange();
    this.notifyPlayStateChange(false);
    await this.playNext();
  }

  // 启动进度定时器（轮询 AvPlayerPlugin）
  private startProgressTimer(): void {
    this.stopProgressTimer();
    this.progressFailCount = 0;
    this.progressTimer = setInterval(() => {
      if (this.currentStatus === 'playing') {
        void (async (): Promise<void> => {
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
        })();
      }
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
    const previousStatus = this.currentStatus;
    hilog.info(DOMAIN, TAG, 'Previous status: %{public}s, artwork: %{public}s', previousStatus, song.artwork || 'null');
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
    hilog.info(DOMAIN, TAG, 'MusicInfo set: name=%{public}s, pic=%{public}s', musicInfo.name, musicInfo.pic || 'null');
    this.notifyMusicInfoChange();

    try {
      hilog.info(DOMAIN, TAG, 'AvPlayerPlugin setResource: %{public}s', url.substring(0, 80));
      await avSetResource(musicInfo, url, null, false);
      this.currentStatus = 'paused';
      this.notifyStateChange();

      if (duration) {
        playerStateData.progress.maxPlayTime = duration;
        playerStateData.progress.maxPlayTimeStr = formatPlayTime(duration);
      }

      // 记录试听历史，供“我的-试听列表”展示最近听过的歌曲
      void recordPlayedSong({
        id: song.id,
        songmid: song.id,
        name: song.title,
        singer: song.artist,
        album: song.album,
        pic: song.artwork,
        source: song.source || 'kw',
        duration: song.duration,
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
    if (this.currentIndex < this.playList.length - 1) {
      this.currentIndex++;
      const song = this.playList[this.currentIndex];
      await this.setSource(song, song.url);
      await this.play();
    } else {
      hilog.info(DOMAIN, TAG, 'Already at the last song');
    }
  }

  // 播放上一曲
  async playPrev(): Promise<void> {
    if (this.currentIndex > 0) {
      this.currentIndex--;
      const song = this.playList[this.currentIndex];
      await this.setSource(song, song.url);
      await this.play();
    } else {
      hilog.info(DOMAIN, TAG, 'Already at the first song');
    }
  }

  // 设置播放列表（不触发播放）
  setPlayList(list: SongInfo[], startIndex: number = 0): void {
    this.playList = list;
    this.currentIndex = startIndex;
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
      hilog.error(DOMAIN, TAG, 'Failed to release player: %{public}s', JSON.stringify(err));
    }

    this.isInitialized = false;
    this.currentStatus = 'idle';
    this.stateListeners = [];
    this.progressListeners = [];
    this.musicInfoListeners = [];
    this.playStateListeners = [];
    this.progressInfoListeners = [];
    hilog.info(DOMAIN, TAG, 'Player destroyed');
  }

  // 更新播放选项
  async updateOptions(): Promise<void> {
    hilog.info(DOMAIN, TAG, 'updateOptions called');
    await avUpdateOptions();
  }
}

// 导出单例
export const playerService = new PlayerService();

// 默认导出
export default playerService;

// 播放器状态返回类型接口
interface PlayerStateReturnType {
  musicInfo: MusicInfo;
  isPlay: boolean;
  progress: ProgressData;
  volume: number;
  playRate: number;
}

// 导出全局状态访问
export function usePlayerState(): PlayerStateReturnType {
  return {
    musicInfo: playerStateData.musicInfo,
    isPlay: playerStateData.isPlay,
    progress: playerStateData.progress,
    volume: playerStateData.volume,
    playRate: playerStateData.playRate,
  };
}
