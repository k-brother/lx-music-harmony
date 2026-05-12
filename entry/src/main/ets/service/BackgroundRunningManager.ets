// 后台任务管理器：管理音频后台播放的长时任务与 AVSession
// HarmonyOS 要求后台音频播放必须同时满足：
//   1. 接入 AVSession（提供音频后台约束能力）
//   2. 申请 AUDIO_PLAYBACK 类型长时任务
//
// 官方文档关键要求：
//   - 创建 AVSession 后必须设元数据（AVMetadata）并至少注册一个控制命令，播控中心才能显示
//   - mediaImage 直接传 string URL 即可，不需要转 PixelMap
//   - 通知栏播控页随音频流启动时发送

import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { bundleManager, common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { avSession } from '@kit.AVSessionKit';
import hilog from '@ohos.hilog';

const TAG: string = 'BackgroundRunningMgr';
const DOMAIN: number = 0x0002;

// 媒体元数据结构（用于播控中心显示）
export interface AvMediaMetadata {
  assetId: string;
  title: string;
  artist: string;
  album?: string;
  duration: number; // 毫秒
  mediaImage?: string; // 封面URL（播控中心要求为 URL string 或 PixelMap，直接传 string 即可）
  lyric?: string; // LRC格式歌词
}

// AVSession 播控命令回调接口
export interface AvSessionCallbacks {
  onPlay: () => void;
  onPause: () => void;
  onStop: () => void;
  onPlayNext: () => void;
  onPlayPrevious: () => void;
  onSeek: (positionMs: number) => void;
  onSetLoopMode: (loopMode: avSession.LoopMode) => void;
  onToggleFavorite: (assetId: string) => void;
}

export class BackgroundRunningManager {
  private session: avSession.AVSession | null = null;
  private isTaskRunning: boolean = false;
  private context: common.UIAbilityContext | null = null;
  private callbacks: AvSessionCallbacks | null = null;
  private currentLoopMode: avSession.LoopMode = avSession.LoopMode.LOOP_MODE_LIST;
  // 缓存最新的 metadata 和播放状态，确保 session 创建后立即同步
  private pendingMetadata: AvMediaMetadata | null = null;
  private pendingIsPlaying: boolean = false;
  private pendingPositionMs: number = 0;
  private pendingSpeed: number = 1.0;
  private hasPendingPlaybackState: boolean = false;

  private static instance: BackgroundRunningManager | null = null;

  static getInstance(): BackgroundRunningManager {
    if (!BackgroundRunningManager.instance) {
      BackgroundRunningManager.instance = new BackgroundRunningManager();
    }
    return BackgroundRunningManager.instance;
  }

  /** 初始化，需要在 EntryAbility 中调用以传入 context */
  init(context: common.UIAbilityContext): void {
    this.context = context;
    hilog.info(DOMAIN, TAG, 'BackgroundRunningManager initialized');
  }

  /**
   * 注册播控命令回调（由 PlayerService 调用）
   * 必须在 initSession/startBackgroundRunning 之前调用
   */
  setCallbacks(callbacks: AvSessionCallbacks): void {
    this.callbacks = callbacks;
    hilog.info(DOMAIN, TAG, 'AVSession callbacks registered');
  }

  /**
   * 主动初始化 AVSession（当播放服务就绪时调用）
   * 提前创建会话并激活，确保系统播控中心能感知应用
   */
  async initSession(): Promise<void> {
    if (!this.context) {
      hilog.warn(DOMAIN, TAG, 'Context not initialized, skip initSession');
      return;
    }
    if (!this.callbacks) {
      hilog.warn(DOMAIN, TAG, 'Callbacks not set, skip initSession');
      return;
    }
    await this.ensureSession();
  }

  /**
   * 创建并激活 AVSession
   * 官方文档明确要求：元数据必须在 activate() 之前设置，控制命令也必须在 activate() 之前注册
   */
  private async ensureSession(): Promise<void> {
    if (this.session) {
      hilog.info(DOMAIN, TAG, 'AVSession already exists, skip creation');
      return;
    }
    if (!this.context) {
      hilog.warn(DOMAIN, TAG, 'Context not initialized, skip AVSession creation');
      return;
    }
    try {
      hilog.info(DOMAIN, TAG, 'Creating AVSession...');
      // 1. 创建类型为 'audio' 的会话
      this.session = await avSession.createAVSession(this.context, 'LXMusic', 'audio');
      hilog.info(DOMAIN, TAG, 'AVSession created, sessionId=%{public}s', this.session.sessionId);

      // 2. 注册播控命令监听（必须在 activate 之前）
      this.registerControlCommands();

      // 3. 设置启动Ability
      await this.setLaunchAbility();

      // 4. 先设置元数据（官方要求：必须在 activate 之前设置）
      if (this.pendingMetadata) {
        hilog.info(DOMAIN, TAG, 'Setting metadata before activate: %{public}s', this.pendingMetadata.title);
        await this.setAvMetadata(this.pendingMetadata);
      } else {
        hilog.warn(DOMAIN, TAG, 'No pending metadata, session will activate without metadata');
      }

      // 5. 激活会话（元数据和控制命令已就绪）
      await this.session.activate();
      hilog.info(DOMAIN, TAG, 'AVSession activated successfully');

      // 6. 设置播放状态（可在激活后设置）
      if (this.hasPendingPlaybackState) {
        await this.applyPendingPlaybackState();
      }
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to create/activate AVSession: %{public}s', msg);
      this.session = null;
    }
  }

  /**
   * 注册播控中心控制命令
   */
  private registerControlCommands(): void {
    if (!this.session) {
      return;
    }

    // 播放
    try {
      this.session.on('play', () => {
        hilog.info(DOMAIN, TAG, 'AVSession command: play');
        try {
          this.callbacks?.onPlay();
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'onPlay callback error: %{public}s', (err as Error)?.message);
        }
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'register play command error: %{public}s', (err as Error)?.message);
    }

    // 暂停
    try {
      this.session.on('pause', () => {
        hilog.info(DOMAIN, TAG, 'AVSession command: pause');
        try {
          this.callbacks?.onPause();
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'onPause callback error: %{public}s', (err as Error)?.message);
        }
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'register pause command error: %{public}s', (err as Error)?.message);
    }

    // 停止
    try {
      this.session.on('stop', () => {
        hilog.info(DOMAIN, TAG, 'AVSession command: stop');
        try {
          this.callbacks?.onStop();
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'onStop callback error: %{public}s', (err as Error)?.message);
        }
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'register stop command error: %{public}s', (err as Error)?.message);
    }

    // 下一首
    try {
      this.session.on('playNext', () => {
        hilog.info(DOMAIN, TAG, 'AVSession command: playNext');
        try {
          this.callbacks?.onPlayNext();
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'onPlayNext callback error: %{public}s', (err as Error)?.message);
        }
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'register playNext command error: %{public}s', (err as Error)?.message);
    }

    // 上一首
    try {
      this.session.on('playPrevious', () => {
        hilog.info(DOMAIN, TAG, 'AVSession command: playPrevious');
        try {
          this.callbacks?.onPlayPrevious();
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'onPlayPrevious callback error: %{public}s', (err as Error)?.message);
        }
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'register playPrevious command error: %{public}s', (err as Error)?.message);
    }

    // 进度调节
    try {
      this.session.on('seek', (positionMs: number) => {
        hilog.info(DOMAIN, TAG, 'AVSession command: seek %{public}d', positionMs);
        try {
          this.callbacks?.onSeek(positionMs);
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'onSeek callback error: %{public}s', (err as Error)?.message);
        }
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'register seek command error: %{public}s', (err as Error)?.message);
    }

    // 循环模式切换
    try {
      this.session.on('setLoopMode', (loopMode: avSession.LoopMode) => {
        hilog.info(DOMAIN, TAG, 'AVSession command: setLoopMode %{public}d', loopMode);
        try {
          this.callbacks?.onSetLoopMode(loopMode);
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'onSetLoopMode callback error: %{public}s', (err as Error)?.message);
        }
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'register setLoopMode command error: %{public}s', (err as Error)?.message);
    }

    // 收藏
    try {
      this.session.on('toggleFavorite', (assetId: string) => {
        hilog.info(DOMAIN, TAG, 'AVSession command: toggleFavorite assetId=%{public}s', assetId);
        try {
          this.callbacks?.onToggleFavorite(assetId);
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'onToggleFavorite callback error: %{public}s', (err as Error)?.message);
        }
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'register toggleFavorite command error: %{public}s', (err as Error)?.message);
    }

    hilog.info(DOMAIN, TAG, 'All control commands registered');
  }

  /**
   * 设置点击播控卡片启动的Ability
   */
  private async setLaunchAbility(): Promise<void> {
    if (!this.session || !this.context) {
      return;
    }
    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: bundleInfo.name,
            abilityName: 'EntryAbility',
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const wantAgentObj: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);
      await this.session.setLaunchAbility(wantAgentObj);
      hilog.info(DOMAIN, TAG, 'setLaunchAbility succeeded');
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.warn(DOMAIN, TAG, 'setLaunchAbility failed: %{public}s', msg);
    }
  }

  /**
   * 补发缓存的播放状态到新创建的 session（在激活后调用）
   */
  private async applyPendingPlaybackState(): Promise<void> {
    if (!this.session || !this.hasPendingPlaybackState) {
      return;
    }
    try {
      const playbackState: avSession.AVPlaybackState = {
        state: this.pendingIsPlaying
          ? avSession.PlaybackState.PLAYBACK_STATE_PLAY
          : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        speed: this.pendingSpeed,
        position: {
          elapsedTime: this.pendingPositionMs,
          updateTime: new Date().getTime()
        },
        loopMode: this.currentLoopMode,
      };
      await this.session.setAVPlaybackState(playbackState);
      hilog.info(DOMAIN, TAG, 'Pending playback state applied: isPlaying=%{public}s', String(this.pendingIsPlaying));
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.warn(DOMAIN, TAG, 'applyPendingPlaybackState error: %{public}s', msg);
    }
  }

  /**
   * 设置 AVSession 元数据
   * mediaImage 直接使用 string URL，官方文档确认支持
   */
  private async setAvMetadata(metadata: AvMediaMetadata): Promise<void> {
    if (!this.session) {
      hilog.warn(DOMAIN, TAG, 'setAvMetadata skipped: session not created');
      return;
    }
    try {
      const avMetadata: avSession.AVMetadata = {
        assetId: metadata.assetId,
        title: metadata.title,
        artist: metadata.artist,
        duration: metadata.duration,
      };
      if (metadata.album) {
        avMetadata.album = metadata.album;
      }
      if (metadata.mediaImage) {
        avMetadata.mediaImage = metadata.mediaImage;
      }
      if (metadata.lyric) {
        avMetadata.lyric = metadata.lyric;
      }
      await this.session.setAVMetadata(avMetadata);
      hilog.info(DOMAIN, TAG, 'AVMetadata set successfully: title=%{public}s, artist=%{public}s, durationMs=%{public}d',
        metadata.title, metadata.artist, metadata.duration);
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to set AVMetadata: %{public}s', msg);
    }
  }

  /**
   * 更新媒体元数据（歌曲信息变化时调用）
   */
  async updateMetadata(metadata: AvMediaMetadata): Promise<void> {
    this.pendingMetadata = metadata;
    if (!this.session) {
      hilog.info(DOMAIN, TAG, 'Metadata cached (session not yet created): title=%{public}s', metadata.title);
      return;
    }
    await this.setAvMetadata(metadata);
  }

  /**
   * 更新播放状态（播放/暂停/进度变化时调用）
   */
  async updatePlaybackState(
    isPlaying: boolean,
    positionMs: number = 0,
    speed: number = 1.0
  ): Promise<void> {
    this.pendingIsPlaying = isPlaying;
    this.pendingPositionMs = positionMs;
    this.pendingSpeed = speed;
    this.hasPendingPlaybackState = true;
    if (!this.session) {
      hilog.info(DOMAIN, TAG, 'PlaybackState cached (session not yet created)');
      return;
    }
    try {
      const playbackState: avSession.AVPlaybackState = {
        state: isPlaying
          ? avSession.PlaybackState.PLAYBACK_STATE_PLAY
          : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        speed: speed,
        position: {
          elapsedTime: positionMs,
          updateTime: new Date().getTime()
        },
        loopMode: this.currentLoopMode,
      };
      await this.session.setAVPlaybackState(playbackState);
      hilog.info(DOMAIN, TAG, 'PlaybackState updated: isPlaying=%{public}s', String(isPlaying));
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.warn(DOMAIN, TAG, 'Failed to update playback state: %{public}s', msg);
    }
  }

  /**
   * 更新循环模式
   */
  setLoopMode(mode: avSession.LoopMode): void {
    this.currentLoopMode = mode;
    hilog.info(DOMAIN, TAG, 'LoopMode set to: %{public}d', mode);
  }

  /** 启动后台长时任务（在开始播放时调用） */
  async startBackgroundRunning(): Promise<void> {
    if (!this.context) {
      hilog.warn(DOMAIN, TAG, 'Context not initialized, skip background task');
      return;
    }

    // 确保 AVSession 已创建（兜底：如果 initSession 失败，此处重试）
    await this.ensureSession();

    if (this.isTaskRunning) {
      hilog.info(DOMAIN, TAG, 'Background task already running');
      return;
    }

    // 先置标志位，防止并发调用导致重复申请
    this.isTaskRunning = true;

    try {
      const bundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );

      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: bundleInfo.name,
            abilityName: 'EntryAbility',
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
      };

      const wantAgentObj: WantAgent = await wantAgent.getWantAgent(wantAgentInfo);
      if (canIUse('SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask')) {
        await backgroundTaskManager.startBackgroundRunning(
          this.context,
          ['audioPlayback'],
          wantAgentObj
        );
        hilog.info(DOMAIN, TAG, 'Background task started successfully');
      } else {
        hilog.warn(DOMAIN, TAG, 'Background task not supported on this device');
      }
    } catch (err) {
      // 失败时回退标志位，允许后续重试
      this.isTaskRunning = false;
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to start background task: %{public}s', msg);
    }
  }

  /** 停止后台长时任务（在暂停/停止播放时调用） */
  async stopBackgroundRunning(): Promise<void> {
    if (!this.isTaskRunning) {
      return;
    }

    try {
      if (this.context && canIUse('SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask')) {
        await backgroundTaskManager.stopBackgroundRunning(this.context);
      }
      this.isTaskRunning = false;
      hilog.info(DOMAIN, TAG, 'Background task stopped');
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to stop background task: %{public}s', msg);
    }
  }

  /** 销毁资源（应用退出时调用） */
  async destroy(): Promise<void> {
    await this.stopBackgroundRunning();
    try {
      if (this.session) {
        await this.session.destroy();
        this.session = null;
        hilog.info(DOMAIN, TAG, 'AVSession destroyed');
      }
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to destroy AVSession: %{public}s', msg);
    }
  }
}

export const backgroundRunningManager = BackgroundRunningManager.getInstance();
