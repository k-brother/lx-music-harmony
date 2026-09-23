import hilog from '@ohos.hilog';
import { showAppToast, TOAST_DURATION_DEFAULT } from '../utils/Toast';
import { common } from '@kit.AbilityKit';
import { playerService, MusicInfo, ProgressInfo, SongInfo } from '../service/PlayerService';
import { navigationService } from '../service/NavigationService';
import { RouteName, NavigationParams } from '../service/NavigationService';
import { isInLoveList } from '../service/ListService';
import { getCurrentLyricIndex, LyricLine } from '../core/music/MusicParsingUtils';
import { playedWordCount, type WordLyricLine } from '../core/lyric/WordLyric';
import { DesignTokens } from '../theme/DesignTokens';
import { Breakpoints } from '../theme/Breakpoints';
import { t } from '../service/LocalizationService';
import { settingsService, type PlayMode } from '../service/SettingsService';
import { DesktopLyricManager } from '../components/common/DesktopLyric';
import { sleepTimerService } from '../service/SleepTimerService';
import type { SleepTimerState } from '../service/SleepTimerService';
import { formatPlayTime } from '../utils/CommonUtils';
import { AlbumCover } from './PlayDetail/AlbumCover';
import { PlayerControls } from './PlayDetail/PlayerControls';
import { PlayDetailTopBar } from './PlayDetail/PlayDetailTopBar';
import { LyricPane } from './PlayDetail/LyricPane';
import {
  addSongToPlaylist,
  addToDislikeList,
  downloadSong,
  fetchSourceCandidates,
  saveCoverToFile,
  saveLyricToFile,
  shareSong,
  switchToSource,
  toggleLoveSong,
} from './PlayDetail/PlaySongActions';
import {
  PlayMediaAssets,
  type CoverOutcome,
  type LyricOutcome,
} from './PlayDetail/PlayMediaAssets';
import { MoreActionsSheet, type PlayActionSection } from './PlayDetail/MoreActionsSheet';
import { VolumeSheet } from './PlayDetail/VolumeSheet';
import { LyricOffsetSheet } from './PlayDetail/LyricOffsetSheet';
import { QueueSheet } from './PlayDetail/QueueSheet';
import { SourceSwitchSheet } from './PlayDetail/SourceSwitchSheet';
import { buildPlayActionSections, showSpeedMenu, speedToast } from './PlayDetail/PlayDetailMenus';
import {
  applyLyricDisplayChoice,
  cancelPendingSleepExit,
  chooseSleepTimer,
  nextPlayMode,
  playModeText,
} from './PlayDetail/PlaySettingsActions';
import { toRoma } from '../utils/RomaConverter';
import { hapticService } from '../service/HapticService';
import { appActionMenu, appToast } from '../service/DialogService';
import { copyText } from '../service/ShareService';

/** 宽屏下控制区（进度条 + 传送键 + 菜单入口）的最大宽度（vp） */
const PLAY_CONTROLS_MAX_WIDTH_VP: number = 640;
/** 播放页下滑关闭的触发位移（vp）：超过就返回，没到就回弹 */
const DISMISS_DRAG_THRESHOLD_VP: number = 96;
/** 平滑进度表的间隔（ms）：逐字歌词与进度条都按这个节奏推进 */
const SMOOTH_TICK_MS: number = 100;
/** 封面左右滑动切歌的触发位移（vp） */
const SWIPE_TRACK_THRESHOLD_VP: number = 60;

const DOMAIN: number = 0x0001;
const TAG: string = 'PlayDetailPage';

/** 字体阴影（设置 → 外观 → 字体阴影） */

interface PlaylistOptionRow {
  id: string;
  name: string;
}

interface ActionMenuResult {
  index: number;
}

@Component
export struct PlayDetailPage {
  @StorageProp('theme') theme: string = 'light';
  /** 一多：窗口断点（WindowService 广播）—— 宽屏走封面/歌词双栏 */
  @StorageProp('breakpoint') breakpoint: string = 'sm';
  @StorageProp('showLyricProgress') showLyricProgress: boolean = false;
  /** 歌词是否显示翻译（长按复制歌词时一并复制译文） */
  @StorageProp('showLyricTranslation') showLyricTranslation: boolean = true;
  /** 是否允许拖动进度条（设置 → 基础）：关闭时拖不动，防误触 */
  @StorageProp('allowProgressBarSeek') allowProgressBarSeek: boolean = true;
  /** 动态背景（设置 → 外观） */
  @StorageProp('dynamicBg') dynamicBg: boolean = false;
  /** 字体阴影（设置 → 外观） */
  @StorageProp('fontShadow') fontShadow: boolean = false;
  /** 深色模式下隐藏背景图 */
  @StorageProp('hideBgDark') hideBgDark: boolean = false;
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State renderKey: number = Date.now();
  @State currentTab: number = 0; // 0: 封面, 1: 歌词
  /** 下滑关闭手势的实时位移（vp，仅封面区跟随手指） */
  @State dismissDragY: number = 0;
  @State isPlaying: boolean = false;
  @State musicName: string = '';
  @State singer: string = '';
  @State album: string = '';
  @State pic: string = '';
  @State progress: number = 0;
  @State currentTime: string = '00:00';
  @State totalTime: string = '00:00';
  /** 进度条拖动中：只预览目标时间，松手才 seek */
  @State isSeeking: boolean = false;
  @State previewProgress: number = 0;
  @State lyricLines: string[] = [t('loading_lyric')];
  @State secondaryLyricLines: string[] = [];
  @State romaLines: string[] = [];
  /** 逐字歌词（与 lyricLines 一一对应；该行没有逐字数据时 words 为空） */
  @State wordLyricLines: WordLyricLine[] = [];
  /** 当前行已唱到第几个字（-1 = 当前行没有逐字数据） */
  @State playedWordCount: number = -1;
  /** 换源弹窗：候选列表与显示状态 */
  @State showSourceDialog: boolean = false;
  @State sourceCandidates: MusicInfo[] = [];
  @State currentLyricIndex: number = -1;
  @State playMode: string = 'listLoop';
  @State showDesktopLyric: boolean = false;
  @State timeoutExitEnabled: boolean = false;
  @State timeoutExitLabel: string = t('sleep_timer_setting');
  /** 定时到点后正在等当前歌曲播完（此时可取消退出） */
  @State sleepWaitingTrackEnd: boolean = false;
  @State showMoreActionsDialog: boolean = false;
  /** 音量面板 */
  @State showVolumeSheet: boolean = false;
  @State volumeDraft: number = 60;
  @State showLyricOffsetSheet: boolean = false;
  @State lyricOffsetDraft: number = 0;
  private lastVolumeBeforeMute: number = 0;
  /** 播放队列面板 */
  @State showQueueSheet: boolean = false;
  @State queueItems: SongInfo[] = [];
  @State queueIndex: number = -1;

  private unsubscribePlayState: (() => void) | null = null;
  private unsubscribeMusicInfo: (() => void) | null = null;
  private unsubscribeProgress: (() => void) | null = null;
  private unsubscribeSleepTimer: (() => void) | null = null;
  private alive: boolean = false;
  private pageSessionId: string = '';
  private lyricTimeline: LyricLine[] = [];
  /** 封面/歌词加载器：守卫、序号、重试都在里面（见 PlayDetail/PlayMediaAssets） */
  private assets: PlayMediaAssets = new PlayMediaAssets();
  /** 本首歌是否已经因为「封面图片加载失败」重拉过一次（防止 error 循环） */
  private coverErrorReloaded: boolean = false;
  /** 最近一次加载到的原始歌词文本（用于同步给桌面歌词窗口） */
  private lyricRawText: string = '';
  private swiperController: SwiperController = new SwiperController();
  /**
   * 平滑进度：进度轮询是秒级的，而歌词逐字高亮与进度条都需要更细的节奏。
   * 这里记录「上一拍的真实位置」与「上一拍的时间戳」，用本地时钟插值出 100ms 级的当前位置。
   */
  private smoothBaseSec: number = 0;
  private smoothBaseAtMs: number = 0;
  private smoothTimer: number = -1;
  /** 当前曲目总时长（秒），用于把平滑进度夹在合法范围内 */
  private durationSecHint: number = 0;
  @State smoothPositionSec: number = 0;

  aboutToAppear() {
    this.alive = true;
    this.assets.setAlive(true);
    if (!this.pageSessionId) {
      this.pageSessionId = `${Date.now()}_${Math.floor(Math.random() * 1000)}`;
    }
    hilog.info(DOMAIN, TAG, 'aboutToAppear session=%{public}s', this.pageSessionId);
    const currentMusicInfo = playerService.getCurrentMusicInfo();
    this.applyMusicInfo(currentMusicInfo);
    void this.refreshMediaAssets(currentMusicInfo, true);

    const progressData = playerService.getProgress();
    this.progress = progressData.progress;
    this.currentTime = progressData.nowPlayTimeStr;
    this.totalTime = progressData.maxPlayTimeStr;
    this.isPlaying = playerService.isPlaying();
    void this.loadPlaySettings();
    this.startSmoothTicker();

    this.unsubscribePlayState = playerService.onPlayStateChange((isPlay: boolean) => {
      if (!this.alive) return;
      this.isPlaying = isPlay;
      // 暂停/继续时把平滑进度的基准对齐到「当前插值出来的位置」，避免暂停后继续跑或续播时跳一下
      this.smoothBaseSec = this.smoothPositionSec;
      this.smoothBaseAtMs = Date.now();
    });

    this.unsubscribeMusicInfo = playerService.onMusicInfoChange((info: MusicInfo) => {
      if (!this.alive) return;
      this.applyMusicInfo(info);
      void this.refreshMediaAssets(info, false);
    });

    this.unsubscribeProgress = playerService.onProgressInfoChange((prog: ProgressInfo) => {
      if (!this.alive) return;
      this.progress = prog.progress;
      this.currentTime = prog.nowPlayTimeStr;
      this.totalTime = prog.maxPlayTimeStr;
      // 平滑进度的基准点：以真实播放位置为准，两次轮询之间用本地时钟插值
      this.smoothBaseSec = prog.nowPlayTime;
      this.smoothBaseAtMs = Date.now();
      this.durationSecHint = prog.maxPlayTime;
      this.smoothPositionSec = prog.nowPlayTime;
      this.advanceLyricByPosition(prog.nowPlayTime);
    });
    // 定时退出状态（含"等待当前歌曲播完"）跟随 SleepTimerService，避免两处状态不一致
    this.unsubscribeSleepTimer = sleepTimerService.onStateChange((state: SleepTimerState) => {
      if (!this.alive) return;
      this.timeoutExitEnabled = state.enabled || state.waitingTrackEnd;
      this.sleepWaitingTrackEnd = state.waitingTrackEnd;
      if (state.waitingTrackEnd) {
        this.timeoutExitLabel = t('sleep_waiting_track');
      } else {
        this.timeoutExitLabel = state.enabled ? t('sleep_enabled') : t('sleep_timer_setting');
      }
    });
    this.renderKey = Date.now();
  }

  aboutToDisappear() {
    hilog.info(DOMAIN, TAG, 'aboutToDisappear session=%{public}s', this.pageSessionId);
    this.alive = false;
    this.assets.setAlive(false);
    this.stopSmoothTicker();
    if (this.unsubscribePlayState) this.unsubscribePlayState();
    if (this.unsubscribeMusicInfo) this.unsubscribeMusicInfo();
    if (this.unsubscribeProgress) this.unsubscribeProgress();
    if (this.unsubscribeSleepTimer) this.unsubscribeSleepTimer();
  }

  onReady(params: Record<string, object | string | number | boolean | undefined>): void {
    hilog.info(DOMAIN, TAG, 'onReady session=%{public}s params=%{public}s', this.pageSessionId, JSON.stringify(params));
  }

  /** 封面 URL 判定统一走加载器（同一份规则页面与加载器不再各写一遍） */
  private normalizeCoverUrl(rawUrl: string): string {
    return PlayMediaAssets.normalizeCoverUrl(rawUrl);
  }

  private canRenderCover(url: string): boolean {
    return PlayMediaAssets.canRenderCover(url);
  }

  private downgradeCoverUrl(url: string): string {
    return PlayMediaAssets.downgradeCoverUrl(url);
  }

  private switchToCoverTab(): void {
    if (this.currentTab === 0) {
      return;
    }
    this.currentTab = 0;
    this.swiperController.changeIndex(0, false);
    if (!this.canRenderCover(this.pic)) {
      const currentMusicInfo = playerService.getCurrentMusicInfo();
      void this.ensureCoverReady(currentMusicInfo, false);
    }
  }

  private switchToLyricTab(): void {
    if (this.currentTab === 1) {
      return;
    }
    this.currentTab = 1;
    this.swiperController.changeIndex(1, false);
    const hasLyric = this.lyricTimeline.length > 0 ||
      (this.lyricLines.length > 0 && this.lyricLines[0] !== t('player_no_lyric'));
    if (!hasLyric) {
      const currentMusicInfo = playerService.getCurrentMusicInfo();
      void this.ensureLyricReady(currentMusicInfo, false);
    }
  }

  private applyMusicInfo(info: MusicInfo): void {
    if (!info || !info.name) {
      this.musicName = t('not_playing');
      this.singer = '';
      this.album = '';
      this.pic = '';
      return;
    }
    this.musicName = info.name;
    this.singer = info.singer || '';
    this.album = info.album ?? info.albumName ?? '';
    this.coverErrorReloaded = false;
    const currentSong = playerService.getCurrentSong();
    const artwork = currentSong && currentSong.artwork ? currentSong.artwork : '';
    this.pic = this.normalizeCoverUrl(info.pic ?? info.img ?? artwork ?? '');
    hilog.info(DOMAIN, TAG, 'applyMusicInfo session=%{public}s name=%{public}s picLen=%{public}d',
      this.pageSessionId, this.musicName, this.pic.length);
  }

  private async refreshMediaAssets(info: MusicInfo, force: boolean): Promise<void> {
    await Promise.all([
      this.ensureCoverReady(info, force),
      this.ensureLyricReady(info, force),
    ]);
  }

  /** 封面：交给加载器（含防风暴守卫与退避重试），这里只把结果写进 @State */
  private async ensureCoverReady(info: MusicInfo, force: boolean): Promise<void> {
    await this.assets.ensureCover(info, force, this.canRenderCover(this.pic), (outcome: CoverOutcome): void => {
      if (!this.alive) {
        return;
      }
      if (outcome.status === 'loaded') {
        this.pic = outcome.url;
      } else if (outcome.status === 'cleared') {
        // 明确置空以触发默认封面显示，避免无效旧值残留导致空白
        this.pic = '';
      }
    });
  }

  /** 歌词：同样由加载器负责守卫与重试，这里只应用解析结果 */
  private async ensureLyricReady(info: MusicInfo, force: boolean): Promise<void> {
    const hasUsableLyric = this.lyricTimeline.length > 0 ||
      (this.lyricLines.length > 0 && this.lyricLines[0] !== t('loading_lyric'));
    await this.assets.ensureLyric(info, force, hasUsableLyric, {
      onLoading: (): void => {
        // 已有可用歌词时后台刷新不抢 UI，避免切 tab 期间出现空白/失败占位闪烁
        if (!hasUsableLyric) {
          this.lyricLines = [t('loading_lyric')];
          this.secondaryLyricLines = [];
          this.currentLyricIndex = -1;
        }
      },
      onOutcome: (outcome: LyricOutcome): void => {
        if (!this.alive) {
          return;
        }
        if (outcome.status === 'empty') {
          this.lyricTimeline = [];
          this.lyricLines = [t('pure_music')];
          this.secondaryLyricLines = [];
          this.wordLyricLines = [];
          this.playedWordCount = -1;
          this.currentLyricIndex = -1;
          return;
        }
        if (outcome.status === 'failed') {
          // 已加载过同一首的歌词就保留，避免刷新失败把已有歌词清掉
          if (!(this.lyricTimeline.length > 0)) {
            this.lyricLines = [t('lyric_load_failed')];
            this.secondaryLyricLines = [];
            this.wordLyricLines = [];
            this.playedWordCount = -1;
            this.currentLyricIndex = -1;
          }
          return;
        }
        const payload = outcome.payload;
        if (!payload) {
          return;
        }
        this.lyricRawText = payload.rawText;
        this.lyricTimeline = payload.timeline;
        this.lyricLines = payload.lines;
        this.secondaryLyricLines = payload.secondaryLines;
        this.wordLyricLines = payload.wordLines;
        this.rebuildRomaLines();
        this.currentLyricIndex = payload.currentIndex;
        this.syncWordHighlight();
      },
    });
  }

  private async togglePlay(): Promise<void> {
    if (this.isPlaying) {
      await playerService.pause();
    } else {
      await playerService.play();
    }
  }

  /** 启动平滑进度表（页面可见时一直跑，播放中才有实际推进） */
  private startSmoothTicker(): void {
    this.stopSmoothTicker();
    this.smoothTimer = setInterval((): void => {
      if (!this.alive) {
        return;
      }
      const elapsedSec: number = this.isPlaying ? (Date.now() - this.smoothBaseAtMs) / 1000 : 0;
      const duration: number = this.durationSecHint;
      let position: number = this.smoothBaseSec + elapsedSec;
      if (duration > 0 && position > duration) {
        position = duration;
      }
      this.smoothPositionSec = position;
      this.advanceLyricByPosition(position);
    }, SMOOTH_TICK_MS);
  }

  private stopSmoothTicker(): void {
    if (this.smoothTimer !== -1) {
      clearInterval(this.smoothTimer);
      this.smoothTimer = -1;
    }
  }

  /**
   * 按当前位置推进歌词：当前句与逐字高亮都跟着平滑位置走。
   * 逐字高亮只在「设置了逐字歌词」且当前行真的有逐字数据时才计算。
   */
  private advanceLyricByPosition(positionSec: number): void {
    if (this.lyricTimeline.length === 0) {
      return;
    }
    const settings = settingsService.get();
    const shifted: number = positionSec + settings.lyricOffset;
    const index: number = getCurrentLyricIndex(this.lyricTimeline, shifted);
    if (index !== this.currentLyricIndex) {
      this.currentLyricIndex = index;
    }
    this.syncWordHighlight(positionSec, settings.wordLyric, settings.lyricOffset);
  }

  /** 计算当前行已唱到第几个字（没有逐字数据时置 -1，歌词退回普通渲染） */
  private syncWordHighlight(
    positionSec: number = this.smoothPositionSec,
    enabled: boolean = settingsService.get().wordLyric,
    offset: number = settingsService.get().lyricOffset): void {
    if (!enabled || this.currentLyricIndex < 0 || this.currentLyricIndex >= this.wordLyricLines.length) {
      this.playedWordCount = -1;
      return;
    }
    this.playedWordCount = playedWordCount(this.wordLyricLines[this.currentLyricIndex], positionSec + offset);
  }

  private async playPrev(): Promise<void> {
    await playerService.playPrev();
  }

  private async playNext(): Promise<void> {
    await playerService.playNext();
  }

  /**
   * 进度条 / 歌词进度线的拖动处理（两处共用一份实现）
   *
   * - 拖动中只更新预览，不发 seek（否则会疯狂打断播放）
   * - 松手（End/Click）才提交一次真正的 seek
   * - 「允许拖动进度条」关闭时只做展示并提示
   */
  private handleSeekChange(value: number, mode: SliderChangeMode): void {
    if (!this.allowProgressBarSeek) {
      // 只在手势开始/结束时提示一次，避免移动过程中刷屏
      if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.End) {
        this.showToast(t('toast_seek_disabled'));
      }
      return;
    }
    const ratio = Math.max(0, Math.min(1, value / 100));
    if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
      this.isSeeking = true;
      this.previewProgress = ratio;
      return;
    }
    this.isSeeking = false;
    void this.seekTo(ratio);
  }

  private async seekTo(progress: number): Promise<void> {
    const duration = playerService.getProgress().maxPlayTime;
    if (duration <= 0) return;
    const targetSec: number = duration * progress;
    await playerService.seekTo(targetSec);
    // seek 后立刻把平滑进度的基准挪到目标位置：进度条/逐字歌词不等下一次轮询就对上
    this.smoothBaseSec = targetSec;
    this.smoothBaseAtMs = Date.now();
    this.smoothPositionSec = targetSec;
    this.advanceLyricByPosition(targetSec);
  }

  /**
   * 进度条的当前值（0~1）。
   * 拖动中显示预览值；播放中用「插值出来的平滑位置」而不是每秒一跳的轮询值，
   * 进度条因此是匀速滑动的（主流播放器的观感）。
   */
  private displayProgress(): number {
    if (this.isSeeking) {
      return this.previewProgress;
    }
    if (this.durationSecHint > 0) {
      const ratio: number = this.smoothPositionSec / this.durationSecHint;
      return Math.max(0, Math.min(1, ratio));
    }
    return this.progress;
  }

  /** 拖动进度条时显示的预览时间（目标位置） */
  private previewTimeText(): string {
    const duration = playerService.getProgress().maxPlayTime;
    if (duration <= 0) {
      return '00:00';
    }
    return formatPlayTime(duration * this.previewProgress);
  }

  private showToast(message: string): void {
    showAppToast(this.getUIContext(), message, TOAST_DURATION_DEFAULT);
  }

  /** 传给命令式动作的提示回调（与页面内提示同一出口） */
  private toast(): (message: string) => void {
    return (message: string): void => {
      this.showToast(message);
    };
  }

  private async loadPlaySettings(): Promise<void> {
    try {
      // 从 PlayerService 读取播放模式（已在 init 时从偏好设置加载）
      const currentMode = playerService.getPlayMode();
      this.playMode = currentMode;

      const settings = settingsService.get();
      this.showDesktopLyric = settings.showDesktopLyric;
      this.timeoutExitEnabled = settings.sleepTimerEnabled;
      this.timeoutExitLabel = this.timeoutExitEnabled ? t('sleep_enabled') : t('sleep_timer_setting');
      // 应用启动时桌面歌词开关可能是开着的，这里补齐子窗口状态
      void DesktopLyricManager.setEnabled(this.showDesktopLyric);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'loadPlaySettings failed: %{public}s', JSON.stringify(err));
    }
  }

  private async savePlaySettings(): Promise<void> {
    try {
      // 同步播放模式到 PlayerService
      playerService.setPlayMode(this.playMode as 'listLoop' | 'singleLoop' | 'random' | 'sequential');

      // 只写「本页自己拥有的开关」：
      // - playMode 由 PlayerService.setPlayMode 负责落盘（这里不再重复写一遍）；
      // - sleepTimerEnabled 归 SleepTimerService（定时器的唯一所有者），
      //   页面里的 timeoutExitEnabled 只是它的一个视图，写回去会用过期状态覆盖真实状态。
      await settingsService.update({
        showDesktopLyric: this.showDesktopLyric,
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'savePlaySettings failed: %{public}s', JSON.stringify(err));
    }
  }

  private togglePlayMode(): void {
    this.playMode = nextPlayMode(this.playMode);
    hilog.info(DOMAIN, TAG, 'play mode -> %{public}s (label=%{public}s)',
      this.playMode, this.getPlayModeText());
    // 同步到 PlayerService（由 PlayerService 同步到 AVSession）
    playerService.setPlayMode(this.playMode as 'listLoop' | 'singleLoop' | 'random' | 'sequential');
    void this.savePlaySettings();
    this.showToast(`${t('settings_play_mode')}: ${this.getPlayModeText()}`);
  }

  private toggleDesktopLyric(): void {
    this.showDesktopLyric = !this.showDesktopLyric;
    // 真正创建/销毁桌面歌词子窗口
    void DesktopLyricManager.setEnabled(this.showDesktopLyric);
    void this.savePlaySettings();
    this.showToast(this.showDesktopLyric ? t('toast_desktop_on') : t('toast_desktop_off'));
  }

  private async toggleTimeoutExit(): Promise<void> {
    const outcome = await chooseSleepTimer();
    if (!outcome) {
      return;
    }
    this.timeoutExitEnabled = outcome.enabled;
    this.timeoutExitLabel = outcome.label;
    this.showToast(outcome.toast);
  }

  /** 加入歌单：命令式动作在 PlayDetail/PlaySongActions，页面只负责取当前歌曲与提示 */
  private async addToPlaylist(): Promise<void> {
    await addSongToPlaylist(playerService.getCurrentMusicInfo(), this.toast());
  }

  private showMoreActions(): void {
    this.showMoreActionsDialog = true;
  }

  /**
   * 「更多操作」的动作列表
   * 文案随状态变化（歌词页/封面页、桌面歌词开关、定时等待态），所以由页面构造后交给面板渲染。
   */
  /**
   * 「更多」面板的动作分组
   *
   * 14 个动作平铺时用户要逐行找，这里按用途分成四组（与主流播放器的「⋯」菜单一致）：
   * 歌曲信息与来源 / 播放相关 / 歌词相关 / 保存与分享。
   */
  /** 「更多」面板的动作分组（内容在 PlayDetail/PlayDetailMenus，含随状态变化的三条文案） */
  private actionSections(): PlayActionSection[] {
    return buildPlayActionSections({
      sleepWaitingTrackEnd: this.sleepWaitingTrackEnd,
      currentTab: this.currentTab,
      desktopLyricOn: this.showDesktopLyric,
      // 宽屏封面与歌词同屏，「切换封面/歌词」这一项没有意义
      wideLayout: Breakpoints.isWide(this.breakpoint),
    });
  }

  /** 面板回调：按 key 分发（避免下标与列表顺序耦合） */
  private onActionPicked(key: string): void {
    if (key === 'addToList') {
      void this.addToPlaylist();
    } else if (key === 'comment') {
      this.viewComments();
    } else if (key === 'switchTab') {
      if (this.currentTab === 0) {
        this.switchToLyricTab();
      } else {
        this.switchToCoverTab();
      }
    } else if (key === 'desktopLyric') {
      this.toggleDesktopLyric();
    } else if (key === 'sleepTimer') {
      if (this.sleepWaitingTrackEnd) {
        this.sleepWaitingTrackEnd = false;
        this.showToast(cancelPendingSleepExit());
      } else {
        void this.toggleTimeoutExit();
      }
    } else if (key === 'saveLyric') {
      void this.saveLyricToFile();
    } else if (key === 'saveCover') {
      void this.saveCoverToFile();
    } else if (key === 'speed') {
      void this.pickSpeed();
    } else if (key === 'lyricOffset') {
      this.openLyricOffsetSheet();
    } else if (key === 'dislike') {
      void this.pickDislike();
    } else if (key === 'lyricDisplay') {
      void this.pickLyricDisplay();
    } else if (key === 'switchSource') {
      void this.showSourceSwitchMenu();
    } else if (key === 'volume') {
      this.volumeDraft = settingsService.get().volume;
      this.showVolumeSheet = true;
    } else if (key === 'queue') {
      this.queueItems = playerService.getPlayList();
      this.queueIndex = playerService.getCurrentIndex();
      this.showQueueSheet = true;
    }
  }

  /** 倍速选择（菜单模块负责选项与折叠） */
  private async pickSpeed(): Promise<void> {
    const rate = await showSpeedMenu(settingsService.get().playRate);
    if (rate === null) {
      return;
    }
    try {
      await playerService.setPlaybackRate(rate);
      this.showToast(speedToast(rate));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setPlaybackRate failed: %{public}s', (err as Error).message);
    }
  }

  /** 歌词偏移：打开滑杆面板（拖动即时生效，替代原来 7 档、会被折叠的动作菜单） */
  private openLyricOffsetSheet(): void {
    this.lyricOffsetDraft = settingsService.get().lyricOffset;
    this.showLyricOffsetSheet = true;
  }

  /** 面板拖动回调：写设置 + 刷新草稿（歌词下一帧即按新偏移定位） */
  private applyLyricOffset(value: number): void {
    this.lyricOffsetDraft = value;
    void settingsService.update({ lyricOffset: value });
    // 拖滑杆时立刻按新偏移重算当前句，不必等下一个进度回调
    playerService.refreshLyricIndex();
  }

  /** 歌词显示设置（翻译 / 罗马音 / 字号 / 对齐 / 进度） */
  private async pickLyricDisplay(): Promise<void> {
    const outcome = await applyLyricDisplayChoice();
    if (!outcome) {
      return;
    }
    if (outcome.romaChanged) {
      this.rebuildRomaLines();
    }
    // 逐字开关可能刚被改掉：立即按当前位置重算高亮，不用等下一次进度回调
    this.syncWordHighlight();
    this.showToast(outcome.toast);
  }

  /** 不喜欢：按粒度写入屏蔽规则（播放时自动跳过） */
  /** 不喜欢（歌曲/歌手/歌名三种粒度） */
  private async pickDislike(): Promise<void> {
    await addToDislikeList(playerService.getCurrentMusicInfo(), this.toast());
  }

  private applyVolume(value: number): void {
    const next = Math.max(0, Math.min(100, Math.round(value)));
    this.volumeDraft = next;
    void settingsService.update({ volume: next });
    playerService.setVolume(next / 100).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'setVolume failed: %{public}s', err.message);
    });
  }

  /** 静音：记住当前音量后归零，再点恢复 */
  private toggleMute(): void {
    if (this.volumeDraft > 0) {
      this.lastVolumeBeforeMute = this.volumeDraft;
      this.applyVolume(0);
      this.showToast(t('volume_muted'));
    } else {
      this.applyVolume(this.lastVolumeBeforeMute > 0 ? this.lastVolumeBeforeMute : 60);
      this.showToast(t('volume_unmuted'));
    }
  }

  /** 播放队列：点任意一首直接切歌（对应安卓 mini 条长按 jumpListPosition 的意图） */
  private async playFromQueue(index: number): Promise<void> {
    this.showQueueSheet = false;
    try {
      await playerService.playSelectedFromPlayList(index);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'playFromQueue failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_play_failed'));
    }
  }


  /** 按当前设置重建罗马音行（关闭时不计算，省 CPU） */
  private rebuildRomaLines(): void {
    if (!settingsService.get().showLyricRoma || this.lyricLines.length === 0) {
      this.romaLines = [];
      return;
    }
    const lines: string[] = [];
    for (let i = 0; i < this.lyricLines.length; i++) {
      lines.push(toRoma(this.lyricLines[i]));
    }
    this.romaLines = lines;
  }


  /** 歌词偏移：正值让歌词更早出现，负值延后 */

  /** 保存当前歌词到本地文件 */
  /** 保存歌词 / 保存封面：动作实现在 PlaySongActions */
  private async saveLyricToFile(): Promise<void> {
    await saveLyricToFile(playerService.getCurrentMusicInfo(), this.lyricRawText, this.toast());
  }

  private async saveCoverToFile(): Promise<void> {
    await saveCoverToFile(playerService.getCurrentMusicInfo(), this.toast());
  }

  private viewComments(): void {
    const currentMusicInfo = playerService.getCurrentMusicInfo();
    if (!currentMusicInfo || !currentMusicInfo.name) {
      this.showToast(t('player_no_song'));
      return;
    }
    hilog.info(DOMAIN, TAG, 'open comments: %{public}s', currentMusicInfo.name);
    const params: NavigationParams = {
      musicId: currentMusicInfo.id || currentMusicInfo.songmid,
      musicName: currentMusicInfo.name,
      musicSinger: currentMusicInfo.singer,
      musicAlbum: currentMusicInfo.album ?? currentMusicInfo.albumName,
      musicPic: currentMusicInfo.pic ?? currentMusicInfo.img ?? undefined,
      musicSource: currentMusicInfo.source,
      commentType: 'hot',
    };
    navigationService.navigateTo(RouteName.COMMENT, params);
  }

  private getPlayModeText(): string {
    return playModeText(this.playMode);
  }

  /** 动态背景：封面高斯模糊垫底 + 上下渐变过渡到页面底色 */
  @Builder
  DynamicBackdrop() {
    // 「深色模式隐藏背景」开启时，深色主题下退回纯色
    if (this.dynamicBg && !(this.hideBgDark && this.theme === 'dark') && this.canRenderCover(this.pic)) {
      Image(this.pic)
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .blur(64)
        .opacity(this.theme === 'dark' ? 0.35 : 0.5)
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 180,
          colors: [
            [this.theme === 'dark' ? '#CC000000' : '#B3FFFFFF', 0.0],
            [this.theme === 'dark' ? '#F2000000' : '#F2FFFFFF', 0.55],
            [DesignTokens.pageBg(this.theme), 1.0],
          ],
        })
    }
  }

  /** 主体：顶栏 + 「封面/歌词」滑动区 + 控制区 */
  @Builder
  PlayerStage() {
    Column() {
      PlayDetailTopBar({
        musicName: this.musicName,
        singer: this.singer,
        fontShadow: this.fontShadow,
        currentTab: this.currentTab,
        // 宽屏封面与歌词同屏，不再需要切换控件
        showTabSwitch: !Breakpoints.isWide(this.breakpoint),
        onMore: (): void => this.showMoreActions(),
        onSelectTab: (tab: number): void => {
          if (tab === 0) {
            this.switchToCoverTab();
          } else {
            this.switchToLyricTab();
          }
        },
      })

      if (Breakpoints.isWide(this.breakpoint)) {
        this.WideStage()
      } else {
        this.NarrowStage()
      }

      this.ControlsBar()
    }
    .width('100%')
    .height('100%')
    // 下滑关闭：只让内容跟随手指，动态背景保持不动（与系统 Sheet 的下拉观感一致）
    .translate({ y: this.dismissDragY })
  }

  /** 大屏（平板横屏 / PC）：左封面右歌词双栏，与主流播放器的大屏形态一致 */
  @Builder
  WideStage() {
    Row() {
      Column() {
        this.AlbumArtArea()
      }
      .layoutWeight(1)
      .height('100%')

      Column() {
        this.LyricSection()
      }
      .layoutWeight(1)
      .height('100%')
      .padding({ left: 8, right: 8 })
    }
    .width('100%')
    .layoutWeight(1)
  }

  /** 手机竖屏：封面与歌词用 Swiper 左右翻页（点封面也能翻） */
  @Builder
  NarrowStage() {
    Swiper(this.swiperController) {
      this.AlbumArtArea()
      // 滑动切换的视觉反馈：非当前页轻微缩小淡出（@Builder 不能链式修饰，包一层容器）
      Column() {
        this.LyricSection()
      }
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .height('100%')
      .scale({ x: this.currentTab === 1 ? 1 : 0.94, y: this.currentTab === 1 ? 1 : 0.94 })
      .opacity(this.currentTab === 1 ? 1 : 0.7)
      .animation({ duration: DesignTokens.motionNormal(), curve: Curve.EaseOut })
    }
    .index(this.currentTab)
    .width('100%')
    .layoutWeight(1)
    .duration(DesignTokens.motionSlow())
    .curve(Curve.EaseOut)
    .indicator(false)
    .loop(false)
    // 翻页改由「点封面 / 顶上切换 / 歌词页右滑」驱动：
    // 横向滑动让给封面切歌（与华为音乐、Spotify 的封面手势一致）
    .disableSwipe(true)
    .onChange((newIndex: number) => {
      this.currentTab = newIndex;
      this.onTabChanged(newIndex);
    })
  }

  /** 控制区：大屏上限宽居中，否则进度条与三个按钮会被拉到整屏宽，显得松散 */
  @Builder
  ControlsBar() {
    Row() {
      Column() {
        this.PlayerControls()
      }
      .width('100%')
      .constraintSize({
        maxWidth: Breakpoints.isWide(this.breakpoint) ? PLAY_CONTROLS_MAX_WIDTH_VP : '100%',
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  /** 歌词区（含进度条）：宽屏常驻显示，窄屏放在 Swiper 第二页 */
  @Builder
  LyricSection() {
    Column() {
      LyricPane({
        lyricLines: this.lyricLines,
        secondaryLyricLines: this.secondaryLyricLines,
        romaLines: this.romaLines,
        wordLyricLines: this.wordLyricLines,
        playedWordCount: this.playedWordCount,
        currentLyricIndex: this.currentLyricIndex,
        showLyricProgress: this.showLyricProgress,
        progress: this.displayProgress(),
        isSeeking: this.isSeeking,
        previewProgress: this.previewProgress,
        currentTime: this.currentTime,
        previewTime: this.previewTimeText(),
        totalTime: this.totalTime,
        onSeekChange: (value: number, mode: SliderChangeMode): void => {
          this.handleSeekChange(value, mode);
        },
        onLineTap: (index: number): void => {
          this.seekToLyricLine(index);
        },
        onLineLongPress: (index: number): void => {
          void this.copyLyricLine(index);
        },
      })
    }
    .width('100%')
    .height('100%')
    // 窄屏歌词页右滑回封面（与「点封面看歌词」形成一来一回的闭环）
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 30 })
        .onActionEnd((event: GestureEvent) => {
          if (!Breakpoints.isWide(this.breakpoint) && event.offsetX > SWIPE_TRACK_THRESHOLD_VP) {
            this.switchToCoverTab();
          }
        })
    )
  }

  /** 长按歌词行：复制这一句（有译文时一并复制，方便分享与歌词纠错反馈） */
  private async copyLyricLine(index: number): Promise<void> {
    if (index < 0 || index >= this.lyricLines.length) {
      return;
    }
    const parts: string[] = [this.lyricLines[index]];
    if (this.showLyricTranslation && index < this.secondaryLyricLines.length
      && this.secondaryLyricLines[index].length > 0) {
      parts.push(this.secondaryLyricLines[index]);
    }
    hapticService.light();
    const ok: boolean = await copyText(parts.join('\n'));
    appToast(ok ? t('toast_lyric_copied') : t('toast_copy_failed'));
  }

  /**
   * 点击歌词行跳到该句。
   *
   * 显示用的行与时间轴是一一对应的（PlayMediaAssets 里 lines 由 timeline.map 得到），
   * 因此下标可直接取时间；seek 时要减掉歌词偏移 —— 偏移是「显示提前/延后」用的，
   * 若不减，用户点名的那句会和实际播放位置差一个偏移量。
   */
  private seekToLyricLine(index: number): void {
    if (index < 0 || index >= this.lyricTimeline.length) {
      return;
    }
    if (!this.allowProgressBarSeek) {
      this.showToast(t('toast_seek_disabled'));
      return;
    }
    const offset = settingsService.get().lyricOffset;
    const target = Math.max(0, this.lyricTimeline[index].time - offset);
    hapticService.light();
    playerService.seekTo(target).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'seekToLyricLine failed: %{public}s', err.message);
    });
    hilog.info(DOMAIN, TAG, 'seek to lyric line %{public}d at %{public}d s', index, target);
  }

  /** 切到某一页时按需补拉封面/歌词（避免首次进入空白） */
  private onTabChanged(newIndex: number): void {
    const currentMusicInfo = playerService.getCurrentMusicInfo();
    if (newIndex === 0) {
      if (!this.canRenderCover(this.pic)) {
        void this.ensureCoverReady(currentMusicInfo, false);
      }
      return;
    }
    // 歌词页：没有歌词时补拉一次（失败/无歌词时不会反复请求，见 PlayMediaAssets）
    const hasLyric = this.lyricTimeline.length > 0 ||
      (this.lyricLines.length > 0 && this.lyricLines[0] !== t('player_no_lyric'));
    if (!hasLyric) {
      void this.ensureLyricReady(currentMusicInfo, false);
    }
  }

  /** 五个底部面板：都只在打开时挂载（未挂载的面板点了不会有反应） */
  @Builder
  PlaySheets() {
    if (this.showMoreActionsDialog) {
      MoreActionsSheet({
        visible: $showMoreActionsDialog,
        // 标题用当前歌曲，用户才知道这些操作作用于哪首（此前误用了播放队列的文案）
        title: this.singer.length > 0 ? `${this.musicName} - ${this.singer}` : this.musicName,
        sections: this.actionSections(),
        onPick: (key: string): void => {
          this.onActionPicked(key);
        },
      })
    }

    if (this.showSourceDialog) {
      SourceSwitchSheet({
        visible: $showSourceDialog,
        candidates: this.sourceCandidates,
        loading: this.sourceCandidates.length === 0,
        onPick: (target: MusicInfo): void => {
          void this.switchToSource(target);
        },
      })
    }

    if (this.showVolumeSheet) {
      VolumeSheet({
        visible: $showVolumeSheet,
        volume: this.volumeDraft,
        onVolumeChange: (value: number): void => {
          this.applyVolume(value);
        },
        onToggleMute: (): void => {
          this.toggleMute();
        },
      })
    }

    if (this.showLyricOffsetSheet) {
      LyricOffsetSheet({
        visible: $showLyricOffsetSheet,
        offsetSeconds: this.lyricOffsetDraft,
        onOffsetChange: (value: number): void => {
          this.applyLyricOffset(value);
        },
      })
    }

    if (this.showQueueSheet) {
      QueueSheet({
        visible: $showQueueSheet,
        queue: this.queueItems,
        currentIndex: this.queueIndex,
        onPick: (index: number): void => {
          void this.playFromQueue(index);
        },
        onMove: (from: number, to: number): void => {
          this.reorderQueue(from, to);
        },
        onRemove: (index: number): void => {
          this.removeFromQueue(index);
        },
      })
    }
  }

  build() {
    Stack() {
      this.DynamicBackdrop()
      this.PlayerStage()
      // 面板统一由组件承载（底部面板 + 分组卡片）
      this.PlaySheets()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /** 音量面板：滑杆 + 静音（对齐安卓版播放页设置里的音量项） */

  /** 播放队列面板：展示当前队列并高亮正在播放的曲目，点击即切歌 */
  /** 队列拖动排序：更新当前面板数据（播放本身不中断） */
  private reorderQueue(from: number, to: number): void {
    if (!playerService.moveInQueue(from, to)) {
      return;
    }
    hapticService.light();
    this.queueItems = playerService.getPlayList();
    this.queueIndex = playerService.getCurrentIndex();
  }

  /** 队列移除：播放中的那首被移除也不打断播放 */
  private removeFromQueue(index: number): void {
    if (!playerService.removeFromQueue(index)) {
      return;
    }
    hapticService.light();
    this.queueItems = playerService.getPlayList();
    this.queueIndex = playerService.getCurrentIndex();
    appToast(t('play_queue_remove'));
  }




  /** 封面：组件负责展示与手势，失败重试/降级仍由页面处理 */
  @Builder
  AlbumArt() {
    AlbumCover({
      cover: this.pic,
      active: this.currentTab === 0,
      animationEnabled: settingsService.get().showAnimation,
      onLoadError: (): void => {
        this.handleCoverLoadError();
      },
      onLongPress: (): void => {
        this.showCoverQuickMenu();
      },
      onTap: (): void => {
        // 窄屏：点封面直接翻到歌词（QQ 音乐等主流播放器的习惯）；
        // 宽屏封面与歌词同屏，点封面不做任何跳转
        if (!Breakpoints.isWide(this.breakpoint) && this.currentTab === 0) {
          this.switchToLyricTab();
        }
      },
    })
  }

  /**
   * 封面区外层容器：承担「下滑关闭播放页」手势。
   * 手势只挂在封面这一片区域（歌词区是纵向滚动容器，挂全局会把滚动吃掉），
   * 拖动时整页跟随手指下移，超过阈值返回上一页，否则回弹。
   */
  @Builder
  AlbumArtArea() {
    Column() {
      this.AlbumArt()
    }
    .width('100%')
    .height('100%')
    .gesture(
      GestureGroup(GestureMode.Parallel,
        // 下滑关闭播放页
        PanGesture({ direction: PanDirection.Down, distance: 10 })
          .onActionUpdate((event: GestureEvent) => {
            this.dismissDragY = Math.max(0, event.offsetY);
          })
          .onActionEnd(() => {
            this.finishDismissDrag();
          })
          .onActionCancel(() => {
            this.dismissDragY = 0;
          }),
        // 左右滑动切歌（主流音乐 App 的封面手势）
        PanGesture({ direction: PanDirection.Horizontal, distance: 20 })
          .onActionEnd((event: GestureEvent) => {
            this.finishTrackSwipe(event.offsetX);
          })
      )
    )
  }

  /**
   * 封面左右滑动切歌：向左滑（offsetX 为负）下一首，向右滑上一首。
   * 位移不足阈值时什么都不做，避免与「点封面看歌词」「下滑关闭」互相误触。
   */
  private finishTrackSwipe(offsetX: number): void {
    if (Math.abs(offsetX) < SWIPE_TRACK_THRESHOLD_VP) {
      return;
    }
    hapticService.selection();
    if (offsetX < 0) {
      void this.playNext();
    } else {
      void this.playPrev();
    }
  }

  /** 下滑关闭：过阈值则返回上一页，否则复位（两种情况都清掉位移，避免页面卡在半路） */
  private finishDismissDrag(): void {
    const shouldDismiss: boolean = this.dismissDragY > DISMISS_DRAG_THRESHOLD_VP;
    this.dismissDragY = 0;
    if (shouldDismiss) {
      hapticService.light();
      navigationService.back();
    }
  }

  /** 封面加载失败：先尝试降级 URL，再重试一次，最后退回占位图 */
  private handleCoverLoadError(): void {
    const downgradedUrl = this.downgradeCoverUrl(this.pic);
    if (downgradedUrl.length > 0 && downgradedUrl !== this.pic) {
      this.pic = downgradedUrl;
      return;
    }
    // 每首歌只因为「图片本身加载失败」重拉一次，避免 error → 重拉 → error 的循环
    if (!this.coverErrorReloaded) {
      this.coverErrorReloaded = true;
      void this.ensureCoverReady(playerService.getCurrentMusicInfo(), true);
      return;
    }
    // 二次失败后回退到占位图，避免页面出现大片空白区域
    this.pic = '';
  }

  /** 长按封面的快捷操作（ActionMenu 最多 6 项，含取消） */
  private async showCoverQuickMenu(): Promise<void> {
    const info = playerService.getCurrentMusicInfo();
    const isLoved = info.id ? isInLoveList(info.id) : false;
    // 统一走 DialogService（取消项由系统菜单提供，不再手写）
    const ix = await appActionMenu(info.name || t('player_title'), [
      isLoved ? t('player_unlove') : t('player_love'),
      t('player_download'),
      t('player_share'),
      t('media_save_cover'),
      t('player_comment'),
    ]);
    if (ix === 0) {
      void this.toggleLoveCurrent();
    } else if (ix === 1) {
      void this.downloadCurrent();
    } else if (ix === 2) {
      void this.shareCurrent();
    } else if (ix === 3) {
      void this.saveCoverToFile();
    } else if (ix === 4) {
      this.viewComments();
    }
  }

  /** 收藏 / 下载 / 分享：命令式动作在 PlaySongActions */
  private async toggleLoveCurrent(): Promise<void> {
    await toggleLoveSong(playerService.getCurrentMusicInfo(), this.toast());
  }

  private async downloadCurrent(): Promise<void> {
    await downloadSong(playerService.getCurrentMusicInfo(), this.toast());
  }

  private async shareCurrent(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    await shareSong(playerService.getCurrentMusicInfo(), context, this.toast());
  }

  @Builder
  PlayerControls() {
    PlayerControls({
      isPlaying: this.isPlaying,
      currentTime: this.currentTime,
      totalTime: this.totalTime,
      progress: this.displayProgress(),
      isSeeking: this.isSeeking,
      previewProgress: this.previewProgress,
      previewTime: this.previewTimeText(),
      playModeText: this.getPlayModeText(),
      addToListText: t('player_add_to_list'),
      commentText: t('player_comment'),
      onSeekChange: (value: number, mode: SliderChangeMode): void => {
        this.handleSeekChange(value, mode);
      },
      onPrev: (): void => {
        void this.playPrev();
      },
      onTogglePlay: (): void => {
        void this.togglePlay();
      },
      onNext: (): void => {
        void this.playNext();
      },
      onAddToList: (): void => {
        void this.addToPlaylist();
      },
      onToggleMode: (): void => {
        this.togglePlayMode();
      },
      onComment: (): void => {
        this.viewComments();
      },
    })
  }

  /**
   * 手动换源：候选来自 PlaySongActions.fetchSourceCandidates（跨源搜索 + 相似度排序，
   * 每个源只留最靠前的一条），这里只负责打开面板。
   */
  private async showSourceSwitchMenu(): Promise<void> {
    const current = playerService.getCurrentMusicInfo();
    if (!current || !current.name) {
      this.showToast(t('player_no_song'));
      return;
    }
    this.showToast(t('switch_source_searching'));
    const picked = await fetchSourceCandidates(current);
    if (picked.length === 0) {
      this.showToast(t('switch_source_empty'));
      return;
    }
    this.sourceCandidates = picked;
    this.showSourceDialog = true;
  }

  /** 切到指定源的匹配结果并播放 */
  private async switchToSource(target: MusicInfo): Promise<void> {
    await switchToSource(target, this.toast());
  }

  /** 不喜欢：按 歌曲 / 歌手 / 歌名 三种粒度加入屏蔽（播放时自动跳过） */

}
