// 播控插件：HarmonyOS AVPlayer 封装（由 PlayerService 委托调用）

import { media } from '@kit.MediaKit';
import { delayMs } from '../../utils/Utils';
import { BusinessError } from '@kit.BasicServicesKit';
// 日志经由应用日志门面，既输出 hilog 也进入「设置 → 运行日志」
import { appLog as hilog } from '../log/AppLogger';
import { playerState } from '../../store/PlayerStoreState';
import { stateEvent } from '../../event/StateEvent';
import { appEvent } from '../../event/AppEvent';
import type { MusicInfo, Progress } from '../../types/MusicTypes';
import { backgroundRunningManager } from '../../service/BackgroundRunningManager';

const DOMAIN: number = 0x0001;
const TAG: string = 'AvPlayerPlugin';

function formatPlaySeconds(sec: number): string {
  if (isNaN(sec) || sec < 0) {
    return '00:00';
  }
  const m: number = Math.floor(sec / 60);
  const s: number = Math.floor(sec % 60);
  return `${m.toString().padStart(2, '0')}:${s.toString().padStart(2, '0')}`;
}

// 初始化配置接口
interface PlayerConfig {
  volume: number;
  playRate: number;
  cacheSize: number | null;
  isHandleAudioFocus: boolean | null;
  isEnableAudioOffload: boolean | null;
}

// 播放器状态
let isPlayerInitialized = false;
let isPrepared = false;

/** 最近一次 stateChange 上报的状态（用于切歌前判断 stop/reset 顺序；create 后视为 idle） */
let lastMediaState: string = 'idle';

// 播放器实例
let avPlayer: media.AVPlayer | null = null;

/** 等待 AVPlayer 进入某一组状态（由 stateChange 驱动） */
interface MediaStateWait {
  targets: string[];
  resolve: () => void;
  reject: (e: Error) => void;
  timerId: number;
}

let mediaStateWaits: MediaStateWait[] = [];

function fulfillMediaStateWaits(state: string): void {
  const still: MediaStateWait[] = [];
  for (let i = 0; i < mediaStateWaits.length; i++) {
    const w = mediaStateWaits[i];
    if (w.targets.indexOf(state) >= 0) {
      clearTimeout(w.timerId);
      w.resolve();
    } else {
      still.push(w);
    }
  }
  mediaStateWaits = still;
}

function waitForMediaState(targets: string[], timeoutMs: number): Promise<void> {
  if (targets.indexOf(lastMediaState) >= 0) {
    return Promise.resolve();
  }
  return new Promise<void>((resolve, reject) => {
    const waiter: MediaStateWait = {
      targets,
      resolve: (): void => {
        resolve();
      },
      reject,
      timerId: 0,
    };
    waiter.timerId = setTimeout((): void => {
      const ix = mediaStateWaits.indexOf(waiter);
      if (ix >= 0) {
        mediaStateWaits.splice(ix, 1);
      }
      reject(
        new Error(`AVPlayer wait [${targets.join(',')}] timeout, last=${lastMediaState}`)
      );
    }, timeoutMs) as number;
    mediaStateWaits.push(waiter);
  });
}


/** 串行化 setResource，避免连点切歌与上一异步 reset/prepare 交叉 */
let setResourceChain: Promise<void> = Promise.resolve();

/** 是否处于可对 AVPlayer 调用 setVolume / setSpeed 的状态（与系统要求：prepared/playing/paused/completed 对齐） */
function avSupportsVolumeAndSpeed(): boolean {
  return isPrepared;
}

function playbackSpeedForRate(rate: number): media.PlaybackSpeed {
  if (rate <= 1.0) {
    return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
  }
  if (rate <= 1.25) {
    return media.PlaybackSpeed.SPEED_FORWARD_1_25_X;
  }
  if (rate <= 1.5) {
    return media.PlaybackSpeed.SPEED_FORWARD_1_50_X;
  }
  if (rate <= 2.0) {
    return media.PlaybackSpeed.SPEED_FORWARD_2_00_X;
  }
  return media.PlaybackSpeed.SPEED_FORWARD_1_00_X;
}

/** 在 prepare 完成之后调用（此时尚未依赖 stateChange 置位） */
function applyStoredVolumeAndSpeedAfterPrepare(): void {
  if (!avPlayer) {
    return;
  }
  try {
    avPlayer.setVolume(playerState.volume);
    avPlayer.setSpeed(playbackSpeedForRate(playerState.playRate));
  } catch (e) {
    const msg: string = e instanceof Error ? e.message : JSON.stringify(e);
    hilog.warn(DOMAIN, TAG, 'apply volume/speed after prepare: %{public}s', msg);
  }
}

/** 在已处于可操控状态时同步 playerState 中的音量与倍速到 AVPlayer */
function applyStoredVolumeAndSpeedIfReady(): void {
  if (!avPlayer || !avSupportsVolumeAndSpeed()) {
    return;
  }
  try {
    avPlayer.setVolume(playerState.volume);
    avPlayer.setSpeed(playbackSpeedForRate(playerState.playRate));
  } catch (e) {
    const msg: string = e instanceof Error ? e.message : JSON.stringify(e);
    hilog.warn(DOMAIN, TAG, 'apply volume/speed: %{public}s', msg);
  }
}

/**
 * 切换媒体前将 AVPlayer 拉回 idle，再设 url → initialized → prepare。
 * 从 playing/paused/prepared/completed 需先 stop 到 stopped，否则 reset/prepare 易报「unsupport prepare」。
 */
async function resetForNewTrack(): Promise<void> {
  if (!avPlayer) {
    return;
  }
  const active: boolean =
    lastMediaState === 'playing' ||
    lastMediaState === 'paused' ||
    lastMediaState === 'prepared' ||
    lastMediaState === 'completed';
  try {
    if (active) {
      await avPlayer.stop();
      await waitForMediaState(['stopped'], 8000);
    }
  } catch (e) {
    const m: string = e instanceof Error ? e.message : JSON.stringify(e);
    hilog.warn(DOMAIN, TAG, 'stop before new track: %{public}s', m);
  }
  try {
    await avPlayer.reset();
    await waitForMediaState(['idle'], 8000);
  } catch (e) {
    const m: string = e instanceof Error ? e.message : JSON.stringify(e);
    hilog.warn(DOMAIN, TAG, 'reset before new track: %{public}s', m);
    // reset 后若未及时收到 idle 回调，短轮询兜底（部分机型 reset 后无二次 idle 上报）
    let spin = 0;
    while (lastMediaState !== 'idle' && spin < 80) {
      await delayMs(50);
      spin++;
    }
  }
}

/** 一曲自然播放结束（如列表自动下一曲），由 PlayerService 等注册 */
let onTrackCompleted: (() => void) | null = null;
/** 播放错误回调：由 PlayerService 注册（见 setOnPlaybackError） */
let onPlaybackError: ((code: number, message: string) => void) | null = null;

export function setOnTrackCompleted(handler: (() => void) | null): void {
  onTrackCompleted = handler;
}

/**
 * 播放期错误回调（非「状态不允许该操作」那类可忽略的错）。
 *
 * 此前错误只写进日志：用户看到的是「进度条不动、也没声音」，界面还以为在播。
 * 现在把错误交给 PlayerService 处理（置错误态 + 按队列跳到下一首 + 通知界面提示）。
 */
export function setOnPlaybackError(handler: ((code: number, message: string) => void) | null): void {
  onPlaybackError = handler;
}

// 初始化播放器
export async function initial(config: PlayerConfig): Promise<void> {
  try {
    const volume = config.volume;
    const playRate = config.playRate;
    const cacheSize = config.cacheSize ?? 1024 * 1024;
    const isHandleAudioFocus = config.isHandleAudioFocus ?? true;
    const isEnableAudioOffload = config.isEnableAudioOffload ?? false;

    // 创建AVPlayer实例
    avPlayer = await media.createAVPlayer();
    lastMediaState = 'idle';

    // 设置事件监听器（必须在设置URL之前）
    setupAVPlayerCallbacks();

    // idle/initialized 态禁止 setVolume/setSpeed（会报 5400102）；音量与倍速写入 playerState，在 prepare 完成后再下发
    playerState.volume = volume;
    playerState.playRate = playRate;

    hilog.info(
      DOMAIN,
      TAG,
      'Player initialized (volume/rate will apply after prepare): %{public}s, %{public}s',
      volume.toString(),
      playRate.toString()
    );
    isPlayerInitialized = true;
    
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, 'Failed to initialize player: %{public}s', errorMsg);
    throw new Error(errorMsg);
  }
}

// 设置AVPlayer事件回调
function setupAVPlayerCallbacks(): void {
  if (!avPlayer) return;
  
  // 状态变化回调
  avPlayer.on('stateChange', async (state: string, reason: media.StateChangeReason) => {
    hilog.info(DOMAIN, TAG, 'Player state changed: %{public}s', state);
    lastMediaState = state;
    fulfillMediaStateWaits(state);

    switch (state) {
      case 'idle':
        hilog.info(DOMAIN, TAG, 'Player state: idle');
        isPrepared = false;
        break;
      case 'initialized':
        hilog.info(DOMAIN, TAG, 'Player state: initialized');
        isPrepared = false;
        break;
      case 'prepared':
        hilog.info(DOMAIN, TAG, 'Player state: prepared - ready to play');
        isPrepared = true;
        // 音量/倍速统一在 setResourceUnlocked 内于 wait prepared 之后下发，避免 prepare() 已返回但状态仍为 initialized 时触发 5400102
        break;
      case 'playing':
        hilog.info(DOMAIN, TAG, 'Player state: playing');
        appEvent.playerPlaying();
        break;
      case 'paused':
        hilog.info(DOMAIN, TAG, 'Player state: paused');
        appEvent.playerPause();
        break;
      case 'completed':
        hilog.info(DOMAIN, TAG, 'Player state: completed');
        if (onTrackCompleted !== null) {
          onTrackCompleted();
        }
        appEvent.stop();
        break;
      case 'stopped':
        hilog.info(DOMAIN, TAG, 'Player state: stopped');
        isPrepared = false;
        break;
      case 'released':
        hilog.info(DOMAIN, TAG, 'Player state: released');
        isPlayerInitialized = false;
        isPrepared = false;
        break;
      case 'error':
        hilog.warn(DOMAIN, TAG, 'Player state: error');
        isPrepared = false;
        break;
    }
  });
  
  // 错误回调（5400102 多为「当前状态不允许该操作」，勿 reset，否则会打断刚 prepared 的播放链）
  avPlayer.on('error', (err: BusinessError) => {
    hilog.error(DOMAIN, TAG, 'Player error: code=%{public}d, message=%{public}s', err.code, err.message);
    if (err.code === 5400102) {
      return;
    }
    lastMediaState = 'error';
    fulfillMediaStateWaits('error');
    // 交给上层：置错误态、按队列跳过并提示用户（这里只负责汇报，不做业务决策）
    if (onPlaybackError) {
      try {
        onPlaybackError(err.code, err.message ?? '');
      } catch (notifyErr) {
        hilog.warn(DOMAIN, TAG, 'onPlaybackError handler failed: %{public}s', JSON.stringify(notifyErr));
      }
    }
    void (async (): Promise<void> => {
      try {
        if (avPlayer) {
          await avPlayer.reset();
        }
      } catch (e) {
        const m: string = e instanceof Error ? e.message : JSON.stringify(e);
        hilog.warn(DOMAIN, TAG, 'error handler reset: %{public}s', m);
      }
    })();
  });
  
  // 时间更新回调（用于进度条；AVPlayer 时间为毫秒，与 store 中秒制一致）
  avPlayer.on('timeUpdate', (timeMs: number) => {
    const durMs: number = avPlayer?.duration ?? 0;
    const nowSec: number = timeMs / 1000;
    const maxSec: number = durMs / 1000;
    const prog: Progress = {
      nowPlayTime: nowSec,
      maxPlayTime: maxSec,
      progress: durMs > 0 ? timeMs / durMs : 0,
      nowPlayTimeStr: formatPlaySeconds(nowSec),
      maxPlayTimeStr: formatPlaySeconds(maxSec),
    };
    stateEvent.playProgressChanged(prog);
  });
  
  // 时长更新回调
  avPlayer.on('durationUpdate', (duration: number) => {
    hilog.info(DOMAIN, TAG, 'Duration updated: %{public}d ms', duration);
  });
  
  // 搜索完成回调
  avPlayer.on('seekDone', (seekDoneTime: number) => {
    hilog.info(DOMAIN, TAG, 'Seek completed at: %{public}d ms', seekDoneTime);
  });
  
  // 缓冲更新回调
  avPlayer.on('bufferingUpdate', (infoType: media.BufferingInfoType, value: number) => {
    if (infoType === media.BufferingInfoType.BUFFERING_START) {
      hilog.info(DOMAIN, TAG, 'Buffering started: %{public}d', value);
    } else if (infoType === media.BufferingInfoType.BUFFERING_END) {
      hilog.info(DOMAIN, TAG, 'Buffering ended: %{public}d', value);
    }
  });
}

// 检查播放器是否初始化
export function isInitialized(): boolean {
  return isPlayerInitialized;
}

// 设置播放资源（autoPlay=false 时仅 prepare，由调用方再调 setPlay，与 PlayerService.setSource+play 一致）
export async function setResource(
  musicInfo: MusicInfo,
  url: string,
  startTime: number | null = null,
  autoPlay: boolean = true
): Promise<void> {
  const prev = setResourceChain;
  let release: () => void = (): void => {};
  setResourceChain = new Promise<void>((resolve) => {
    release = resolve;
  });
  await prev;
  try {
    await setResourceUnlocked(musicInfo, url, startTime, autoPlay);
  } finally {
    release();
  }
}

async function setResourceUnlocked(
  musicInfo: MusicInfo,
  url: string,
  startTime: number | null = null,
  autoPlay: boolean = true
): Promise<void> {
  try {
    if (!isPlayerInitialized || !avPlayer) {
      const config: PlayerConfig = {
        volume: playerState.volume,
        playRate: playerState.playRate,
        cacheSize: 1024 * 1024,
        isHandleAudioFocus: true,
        isEnableAudioOffload: false
      };
      await initial(config);
    }

    if (!avPlayer) {
      throw new Error('AVPlayer not initialized');
    }

    isPrepared = false;

    hilog.info(DOMAIN, TAG, 'setResource url: %{public}s', url.length > 160 ? `${url.substring(0, 160)}...` : url);

    await resetForNewTrack();

    // 仅在 idle 下设置媒体地址（官方：idle → initialized）
    if (lastMediaState !== 'idle') {
      hilog.warn(DOMAIN, TAG, 'Expected idle before set url, got %{public}s — retry reset', lastMediaState);
      await avPlayer.reset();
      await waitForMediaState(['idle'], 8000);
    }

    // 设置播放URL
    const useUrl = url;

    avPlayer.url = useUrl;
    try {
      await waitForMediaState(['initialized'], 5000);
    } catch (e) {
      const m: string = e instanceof Error ? e.message : JSON.stringify(e);
      hilog.warn(DOMAIN, TAG, 'wait initialized: %{public}s', m);
    }

    // prepare() 返回后状态可能仍为 initialized，需等 stateChange → prepared 再调音量/倍速/play
    await avPlayer.prepare();
    try {
      await waitForMediaState(['prepared'], 15000);
    } catch (waitErr) {
      const wm: string = waitErr instanceof Error ? waitErr.message : JSON.stringify(waitErr);
      hilog.error(DOMAIN, TAG, 'wait prepared failed: %{public}s, lastState=%{public}s', wm, lastMediaState);
      throw waitErr instanceof Error ? waitErr : new Error(wm);
    }
    isPrepared = true;
    applyStoredVolumeAndSpeedAfterPrepare();

    // 如果有起始时间，跳转到该位置
    if (startTime && startTime > 0) {
      await avPlayer.seek(startTime, media.SeekMode.SEEK_CLOSEST);
    }

    stateEvent.playerMusicInfoChanged(musicInfo);

    if (autoPlay) {
      await avPlayer.play();
      stateEvent.playStateChanged(true);
      appEvent.play();
      // 自动播放时启动后台长时任务
      void backgroundRunningManager.startBackgroundRunning();
    }
    
    hilog.info(DOMAIN, TAG, 'Resource set successfully: %{public}s', musicInfo.name);
    
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, 'Failed to set resource: %{public}s', errorMsg);
    throw new Error(errorMsg);
  }
}


// 播放
export async function setPlay(): Promise<void> {
  if (!avPlayer || !isPrepared) {
    hilog.warn(DOMAIN, TAG, 'Player not ready for play');
    throw new Error('AVPLAYER_NOT_READY');
  }
  try {
    await avPlayer.play();
    appEvent.play();
    appEvent.playerPlaying();
    // 后台任务/AVSession 已由 PlayerService.play() 统一管理
    hilog.info(DOMAIN, TAG, 'Playback started');
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, 'Failed to play: %{public}s', errorMsg);
    throw err instanceof Error ? err : new Error(errorMsg);
  }
}

// 暂停
export async function setPause(): Promise<void> {
  try {
    if (!avPlayer) {
      hilog.warn(DOMAIN, TAG, 'Player not initialized');
      return;
    }
    
    await avPlayer.pause();
    appEvent.pause();
    appEvent.playerPause();
    // 暂停播放时取消后台长时任务
    void backgroundRunningManager.stopBackgroundRunning();
    hilog.info(DOMAIN, TAG, 'Playback paused');
    
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, 'Failed to pause: %{public}s', errorMsg);
  }
}

// 停止
export async function setStop(): Promise<void> {
  try {
    if (!avPlayer) {
      hilog.warn(DOMAIN, TAG, 'Player not initialized');
      return;
    }
    
    await avPlayer.stop();
    appEvent.stop();
    // 停止播放时取消后台长时任务
    void backgroundRunningManager.stopBackgroundRunning();
    hilog.info(DOMAIN, TAG, 'Playback stopped');
    
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, 'Failed to stop: %{public}s', errorMsg);
  }
}

// 跳转
export async function setCurrentTime(time: number): Promise<void> {
  try {
    if (!avPlayer || !isPrepared) {
      hilog.warn(DOMAIN, TAG, 'Player not ready for seeking');
      return;
    }
    
    await avPlayer.seek(time, media.SeekMode.SEEK_CLOSEST);
    appEvent.setProgress(time);
    hilog.info(DOMAIN, TAG, 'Seek to: %{public}d ms', time);
    
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, 'Failed to seek: %{public}s', errorMsg);
  }
}

// 获取当前位置
export async function getPosition(): Promise<number> {
  try {
    if (!avPlayer || !isPrepared) {
      return playerState.progress.nowPlayTime;
    }
    return avPlayer.currentTime / 1000;
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, 'Failed to get position: %{public}s', errorMsg);
    return playerState.progress.nowPlayTime;
  }
}

// 获取总时长
export async function getDuration(): Promise<number> {
  try {
    if (!avPlayer || !isPrepared) {
      return playerState.progress.maxPlayTime;
    }
    return avPlayer.duration / 1000;
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, 'Failed to get duration: %{public}s', errorMsg);
    return playerState.progress.maxPlayTime;
  }
}


// 设置音量
export async function setVolume(volume: number): Promise<void> {
  try {
    const clampedVolume = Math.max(0, Math.min(1, volume));
    playerState.volume = clampedVolume;
    
    if (avPlayer && avSupportsVolumeAndSpeed()) {
      avPlayer.setVolume(clampedVolume);
    }

    hilog.info(DOMAIN, TAG, 'Volume set to: %{public}s', clampedVolume.toString());
    
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, 'Failed to set volume: %{public}s', errorMsg);
  }
}


// 设置播放速率
export async function setPlaybackSpeed(rate: number): Promise<void> {
  try {
    playerState.playRate = rate;
    
    if (avPlayer && avSupportsVolumeAndSpeed()) {
      avPlayer.setSpeed(playbackSpeedForRate(rate));
    }

    hilog.info(DOMAIN, TAG, 'Playback speed set to: %{public}s', rate.toString());
    
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, 'Failed to set playback speed: %{public}s', errorMsg);
  }
}

// 销毁播放器
export async function destroy(): Promise<void> {
  try {
    if (avPlayer) {
      await avPlayer.release();
      avPlayer = null;
    }
    
    isPlayerInitialized = false;
    isPrepared = false;
    // 销毁时取消后台长时任务并清理 AVSession
    void backgroundRunningManager.destroy();
    hilog.info(DOMAIN, TAG, 'Player destroyed');
    
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, 'Failed to destroy player: %{public}s', errorMsg);
  }
}

// 更新播放选项
export async function updateOptions(): Promise<void> {
  try {
    applyStoredVolumeAndSpeedIfReady();

    hilog.info(DOMAIN, TAG, 'Player options updated');
    
  } catch (err) {
    const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, 'Failed to update options: %{public}s', errorMsg);
  }
}
