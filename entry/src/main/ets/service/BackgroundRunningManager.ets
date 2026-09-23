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
import { registerMediaControlCommands } from './player/MediaControlCommands';
import type { AvMediaMetadata, AvSessionCallbacks } from './player/AvSessionTypes';

const TAG: string = 'BackgroundRunningMgr';
const DOMAIN: number = 0x0002;

// 元数据与回调类型在 player/AvSessionTypes（这里 re-export，调用方路径不变）
export type { AvMediaMetadata, AvSessionCallbacks };
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
  /** 播控中心/锁屏显示封面（设置项 player.isShowNotificationImage 对齐） */
  private showNotificationImage: boolean = true;
  /** 蓝牙/车机歌词：是否把整段 LRC 写入 AVSession 元数据 */
  private showBluetoothLyric: boolean = false;
  /** 系统桌面歌词是否已接管（决定元数据里是否必须带整段 LRC） */
  private systemDesktopLyricActive: boolean = false;
  /** 会话就绪前收到的桌面歌词意图（启动恢复时常见） */
  private pendingSystemDesktopLyric: boolean = false;
  private sessionReadyListeners: Array<() => void> = [];

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
   * 同步「播控封面 / 蓝牙歌词」两个开关。
   * 由 PlayerService 在初始化与设置变化时调用；
   * 关闭蓝牙歌词时不再下发整段 LRC（当前句仍会下发，锁屏单行歌词不受影响）。
   */
  setMetadataOptions(showNotificationImage: boolean, showBluetoothLyric: boolean): void {
    const changed = this.showNotificationImage !== showNotificationImage
      || this.showBluetoothLyric !== showBluetoothLyric;
    this.showNotificationImage = showNotificationImage;
    this.showBluetoothLyric = showBluetoothLyric;
    if (!changed) {
      return;
    }
    // 立刻用缓存元数据重放一次，开关切换无需等下一首歌
    const pending = this.pendingMetadata;
    if (pending && this.session) {
      this.setAvMetadata(pending).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 're-apply metadata options failed: %{public}s', err.message);
      });
    }
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

      // 5.1 声明会话能力：后台播放模式 / 播控中心控件 / 支持的循环模式。
      //     不做这一步时，播控中心只会显示最基本的播放暂停，进度条与速度入口都是灰的。
      await this.applySessionCapabilities();

      // 6. 设置播放状态（可在激活后设置）
      if (this.hasPendingPlaybackState) {
        await this.applyPendingPlaybackState();
      }

      // 7. 会话就绪：通知依赖会话的能力（系统桌面歌词等）补挂
      this.notifySessionReady();
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to create/activate AVSession: %{public}s', msg);
      this.session = null;
    }
  }

  /**
   * 注册播控中心控制命令
   */
  /** 注册播控命令：8 条命令的统一注册/错误处理在 player/MediaControlCommands */
  private registerControlCommands(): void {
    if (!this.session) {
      return;
    }
    registerMediaControlCommands(this.session, this.callbacks);
  }

  /**
   * 会话能力声明（API 24/26 新增，设备不支持时静默跳过）。
   *
   * - setBackgroundPlayMode：明确告知系统音频可后台继续，避免切后台被回收；
   * - setMediaCenterControlType：播控中心按应用能力显示控件，这里只声明
   *   已注册回调的四种（上/下一首、循环、收藏），不声明未实现的快进/倍速，
   *   否则用户点下去没有反应；
   * - setSupportedLoopModes：让播控中心的循环按钮知道有哪几档。
   */
  private async applySessionCapabilities(): Promise<void> {
    const session = this.session;
    if (!session) {
      return;
    }
    if (canIUse('SystemCapability.Multimedia.AVSession.Core')) {
      try {
        await session.setBackgroundPlayMode(avSession.BackgroundPlayMode.ENABLE_BACKGROUND_PLAY);
      } catch (err) {
        hilog.info(DOMAIN, TAG, 'setBackgroundPlayMode skipped: %{public}s',
          (err as Error)?.message ?? '');
      }
    }
    try {
      await session.setMediaCenterControlType(
        ['playPrevious', 'playNext', 'setLoopMode', 'toggleFavorite']);
    } catch (err) {
      hilog.info(DOMAIN, TAG, 'setMediaCenterControlType skipped: %{public}s',
        (err as Error)?.message ?? '');
    }
    try {
      await session.setSupportedLoopModes([
        avSession.LoopMode.LOOP_MODE_LIST,
        avSession.LoopMode.LOOP_MODE_SINGLE,
        avSession.LoopMode.LOOP_MODE_SEQUENCE,
        avSession.LoopMode.LOOP_MODE_SHUFFLE,
      ]);
    } catch (err) {
      hilog.info(DOMAIN, TAG, 'setSupportedLoopModes skipped: %{public}s',
        (err as Error)?.message ?? '');
    }
  }

  /**
   * 构造「点击通知回到本应用」的 WantAgent。
   *
   * 播控会话的 setLaunchAbility 与后台长时任务的 startBackgroundRunning 都要它，
   * 之前两处各写一遍（只差一个 wantAgentFlags），抽成一处避免取包名/Ability 名两处漂移。
   */
  private async buildLaunchWantAgent(updatePresent: boolean): Promise<WantAgent | null> {
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
        wantAgentFlags: updatePresent ? [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG] : [],
      };
      return await wantAgent.getWantAgent(wantAgentInfo);
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.warn(DOMAIN, TAG, 'buildLaunchWantAgent failed: %{public}s', msg);
      return null;
    }
  }

  private async setLaunchAbility(): Promise<void> {
    if (!this.session || !this.context) {
      return;
    }
    try {
      const wantAgentObj = await this.buildLaunchWantAgent(true);
      if (!wantAgentObj) {
        return;
      }
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
      // 播控封面可关（安卓版 player.isShowNotificationImage）；关闭时只发文本元数据，减少抖动
      if (metadata.mediaImage && this.showNotificationImage) {
        avMetadata.mediaImage = metadata.mediaImage;
      }
      // 整段 LRC：蓝牙歌词或系统桌面歌词开启时必须下发（后者靠它逐句滚动）；
      // 当前句始终下发，保证锁屏/播控/胶囊的单行歌词
      if (metadata.lyric && (this.showBluetoothLyric || this.systemDesktopLyricActive)) {
        avMetadata.lyric = metadata.lyric;
      }
      if (metadata.singleLyricText) {
        avMetadata.singleLyricText = metadata.singleLyricText;
      }
      await this.session.setAVMetadata(avMetadata);
      hilog.info(DOMAIN, TAG,
        'AVMetadata set: title=%{public}s, artist=%{public}s, durationMs=%{public}d, lrc=%{public}s, single=%{public}s',
        metadata.title, metadata.artist, metadata.duration,
        String(avMetadata.lyric !== undefined), String(avMetadata.singleLyricText !== undefined));
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to set AVMetadata: %{public}s', msg);
    }
  }

  /**
   * 更新媒体元数据（歌曲信息变化时调用）
   */
  async updateMetadata(metadata: AvMediaMetadata): Promise<void> {
    // 同一首歌的元数据可能被多次重设（切音质、改封面开关等），
    // 这些调用不带歌词，直接覆盖会把已下发的 LRC 丢掉，这里做一次继承。
    const previous = this.pendingMetadata;
    if (previous && previous.assetId === metadata.assetId) {
      if (!metadata.lyric && previous.lyric) {
        metadata.lyric = previous.lyric;
      }
      if (!metadata.singleLyricText && previous.singleLyricText) {
        metadata.singleLyricText = previous.singleLyricText;
      }
    }
    this.pendingMetadata = metadata;
    if (!this.session) {
      hilog.info(DOMAIN, TAG, 'Metadata cached (session not yet created): title=%{public}s', metadata.title);
      return;
    }
    await this.setAvMetadata(metadata);
  }

  /**
   * 只更新歌词相关信息，其余元数据沿用上一次的值。
   * 频次与歌词行切换同频（每首歌几十次），不会造成额外负担。
   */
  async updateLyric(lyricText: string, singleLyricText: string): Promise<void> {
    const base = this.pendingMetadata;
    if (!base) {
      return;
    }
    const merged: AvMediaMetadata = {
      assetId: base.assetId,
      title: base.title,
      artist: base.artist,
      duration: base.duration,
      album: base.album,
      mediaImage: base.mediaImage,
      lyric: lyricText,
      singleLyricText: singleLyricText,
    };
    this.pendingMetadata = merged;
    if (!this.session) {
      return;
    }
    await this.setAvMetadata(merged);
  }

  // ==================== 系统桌面歌词（HarmonyOS 26+） ====================

  /**
   * 系统是否支持原生桌面歌词。
   * 支持时优先用系统能力（与华为音乐一致的观感、跟随系统主题/位置设置）。
   */
  async isSystemDesktopLyricSupported(): Promise<boolean> {
    try {
      if (!canIUse('SystemCapability.Multimedia.AVSession.Core')) {
        return false;
      }
      return await avSession.isDesktopLyricSupported();
    } catch (err) {
      hilog.info(DOMAIN, TAG, 'System desktop lyric not supported: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      return false;
    }
  }

  /**
   * 开启/关闭系统桌面歌词。
   * @returns 是否成功使用系统能力（false 时调用方应回退到内置悬浮窗）
   */
  async enableSystemDesktopLyric(enable: boolean): Promise<boolean> {
    if (!this.session) {
      // 启动恢复桌面歌词时会话通常还没建立（要等首次播放）。
      // 这里先记住意图，等会话就绪后由 onSessionReady 的订阅者补挂系统歌词，
      // 避免用户端表现成「永久退化成内置黑色浮窗」。
      this.pendingSystemDesktopLyric = enable;
      hilog.info(DOMAIN, TAG, 'System desktop lyric deferred until session ready: enable=%{public}s',
        enable.toString());
      return false;
    }
    try {
      await this.session.enableDesktopLyric(enable);
      // 只是「启用能力」还不够：系统歌词窗口默认不可见，必须显式置为可见，
      // 否则用户开了桌面歌词却只在桌面上看到一片空白（胶囊里只有歌名）。
      await this.session.setDesktopLyricVisible(enable);
      this.setSystemDesktopLyricActive(enable);
      const visible = await this.session.isDesktopLyricVisible();
      hilog.info(DOMAIN, TAG, 'System desktop lyric enabled=%{public}s visible=%{public}s',
        enable.toString(), visible.toString());
      return true;
    } catch (err) {
      const code: number = (err as BusinessError)?.code ?? 0;
      // 6600111 = 设备不支持桌面歌词能力
      hilog.warn(DOMAIN, TAG, 'enableSystemDesktopLyric failed: code=%{public}d, msg=%{public}s',
        code, (err as Error)?.message ?? '');
      return false;
    }
  }

  /**
   * 系统桌面歌词是否正在接管。
   *
   * 与「蓝牙歌词」区分：系统桌面歌词/锁屏歌词必须拿到整段 LRC 才能逐句滚动，
   * 所以元数据下发按「蓝牙歌词 || 系统桌面歌词」决定是否带 LRC，
   * 否则用户开了桌面歌词却只能看到一句静态文本。
   */
  setSystemDesktopLyricActive(active: boolean): void {
    if (this.systemDesktopLyricActive === active) {
      return;
    }
    this.systemDesktopLyricActive = active;
    hilog.info(DOMAIN, TAG, 'System desktop lyric active=%{public}s', active.toString());
    // 立即用缓存元数据重放一次，开启歌词无需等下一首
    this.reapplyPendingMetadata();
  }

  /** 订阅「会话已创建并激活」：依赖会话的能力在这里补挂 */
  onSessionReady(listener: () => void): void {
    this.sessionReadyListeners.push(listener);
  }

  private notifySessionReady(): void {
    // 先把启动阶段记下的桌面歌词意图补上（不依赖订阅者注册顺序）
    if (this.pendingSystemDesktopLyric && this.session) {
      const session = this.session;
      this.pendingSystemDesktopLyric = false;
      session.enableDesktopLyric(true).then(() => {
        this.setSystemDesktopLyricActive(true);
        hilog.info(DOMAIN, TAG, 'Pending system desktop lyric applied after session ready');
      }).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'apply pending desktop lyric failed: %{public}s', err.message);
      });
    }
    for (const listener of this.sessionReadyListeners) {
      try {
        listener();
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'session-ready listener failed: %{public}s',
          err instanceof Error ? err.message : JSON.stringify(err));
      }
    }
  }

  /** 用缓存元数据重放（开关切换/歌词状态变化时调用） */
  private reapplyPendingMetadata(): void {
    const pending = this.pendingMetadata;
    if (!pending || !this.session) {
      return;
    }
    this.setAvMetadata(pending).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 're-apply metadata failed: %{public}s', err.message);
    });
  }

  /** 系统桌面歌词显示/隐藏 */
  async setSystemDesktopLyricVisible(visible: boolean): Promise<boolean> {
    if (!this.session) {
      return false;
    }
    try {
      await this.session.setDesktopLyricVisible(visible);
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setSystemDesktopLyricVisible failed: %{public}s',
        (err as Error)?.message ?? '');
      return false;
    }
  }

  /** 系统桌面歌词锁定（锁定后不可拖动、点击穿透） */
  async setSystemDesktopLyricLocked(locked: boolean): Promise<boolean> {
    if (!this.session) {
      return false;
    }
    try {
      const state: avSession.DesktopLyricState = { isLocked: locked };
      await this.session.setDesktopLyricState(state);
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setSystemDesktopLyricLocked failed: %{public}s',
        (err as Error)?.message ?? '');
      return false;
    }
  }

  /**
   * 订阅系统桌面歌词的可见性与锁定状态变化。
   *
   * 系统歌词窗口是系统自己渲染的：用户在系统侧把它关掉、或者点了锁定，
   * 只有这两个回调能知道。不订阅的话应用里的开关会一直停在"已开启"，
   * 用户再点一次也没任何反应。
   */
  observeSystemDesktopLyric(
    onVisibility: (visible: boolean) => void,
    onState: (state: avSession.DesktopLyricState) => void): void {
    if (!this.session) {
      return;
    }
    try {
      this.session.onDesktopLyricVisibilityChanged(onVisibility);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'onDesktopLyricVisibilityChanged failed: %{public}s',
        (err as Error)?.message ?? '');
    }
    try {
      this.session.onDesktopLyricStateChanged(onState);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'onDesktopLyricStateChanged failed: %{public}s',
        (err as Error)?.message ?? '');
    }
  }

  /** 取消系统桌面歌词状态订阅（关闭桌面歌词时调用） */
  unobserveSystemDesktopLyric(): void {
    if (!this.session) {
      return;
    }
    try {
      this.session.offDesktopLyricVisibilityChanged();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'offDesktopLyricVisibilityChanged failed: %{public}s',
        (err as Error)?.message ?? '');
    }
    try {
      this.session.offDesktopLyricStateChanged();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'offDesktopLyricStateChanged failed: %{public}s',
        (err as Error)?.message ?? '');
    }
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
      const wantAgentObj = await this.buildLaunchWantAgent(false);
      if (!wantAgentObj) {
        this.isTaskRunning = false;
        return;
      }

      if (canIUse('SystemCapability.ResourceSchedule.BackgroundTaskManager.ContinuousTask')) {
        // @SuppressWarnings syscap
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
        // @SuppressWarnings syscap
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
