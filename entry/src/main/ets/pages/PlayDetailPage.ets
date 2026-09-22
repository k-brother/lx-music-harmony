import hilog from '@ohos.hilog';
import { showAppToast, TOAST_DURATION_DEFAULT } from '../utils/Toast';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { playerService, MusicInfo, ProgressInfo, SongInfo } from '../service/PlayerService';
import { navigationService } from '../service/NavigationService';
import { LyricView } from '../components/common/LyricView';
import { RouteName, NavigationParams } from '../service/NavigationService';
import {
  getUserList,
  LIST_IDS,
  addMusicToList,
  toggleLoveList,
  isInLoveList,
  MusicItem
} from '../service/ListService';
import { getLyricInfo, getPicPath, download, getOtherSource, getMusicUrl } from '../core/music/MusicFeatureEntry';
import { parseLrc, getCurrentLyricIndex, LyricLine } from '../core/music/MusicParsingUtils';
import { convertChinese } from '../core/lyric/ChineseConvert';
import { DesignTokens } from '../theme/DesignTokens';
import { NavBackButton } from '../components/common/NavBackButton';
import { t, tf, sourceLabel } from '../service/LocalizationService';
import { settingsService, type PlayMode } from '../service/SettingsService';
import { DesktopLyricManager } from '../components/common/DesktopLyric';
import { sleepTimerService } from '../service/SleepTimerService';
import type { SleepTimerState } from '../service/SleepTimerService';
import { formatPlayTime } from '../utils/CommonUtils';
import { mediaSaveService, type SaveResult } from '../service/MediaSaveService';
import { dislikeList } from '../core/dislike/DislikeList';
import { AlbumCover } from './PlayDetail/AlbumCover';
import { MoreActionsSheet, type PlayActionRow } from './PlayDetail/MoreActionsSheet';
import { VolumeSheet } from './PlayDetail/VolumeSheet';
import { QueueSheet } from './PlayDetail/QueueSheet';
import { SourceSwitchSheet } from './PlayDetail/SourceSwitchSheet';
import { SegmentedBar } from '../components/ui/SegmentedBar';
import {
  showSpeedMenu,
  showLyricOffsetMenu,
  showLyricDisplayMenu,
  showDislikeMenu,
  speedToast,
} from './PlayDetail/PlayDetailMenus';
import { toRoma } from '../utils/RomaConverter';
import { hapticService } from '../service/HapticService';
import { appToast } from '../service/DialogService';
import { buildShareText, getMusicDetailPageUrl } from '../core/music/MusicDetailUrl';
import { shareText } from '../service/ShareService';

const DOMAIN: number = 0x0001;
const TAG: string = 'PlayDetailPage';

/** 字体阴影（设置 → 外观 → 字体阴影） */
const PLAY_TEXT_SHADOW: ShadowOptions = { radius: 8, color: 'rgba(0,0,0,0.55)', offsetX: 0, offsetY: 0 };

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
  @StorageProp('showLyricProgress') showLyricProgress: boolean = false;
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
  private lastVolumeBeforeMute: number = 0;
  /** 播放队列面板 */
  @State showQueueSheet: boolean = false;
  @State queueItems: SongInfo[] = [];
  @State queueIndex: number = -1;
  @State pressedMoreActionIndex: number = -1;

  private unsubscribePlayState: (() => void) | null = null;
  private unsubscribeMusicInfo: (() => void) | null = null;
  private unsubscribeProgress: (() => void) | null = null;
  private unsubscribeSleepTimer: (() => void) | null = null;
  private alive: boolean = false;
  private pageSessionId: string = '';
  private lyricTimeline: LyricLine[] = [];
  private lyricLoadSeq: number = 0;
  private picLoadSeq: number = 0;
  private coverRetryTimer: number = -1;
  private lyricRetryTimer: number = -1;
  private coverRetryCount: number = 0;
  private lyricRetryCount: number = 0;
  private lyricSongKey: string = '';
  /** 最近一次加载到的原始歌词文本（用于同步给桌面歌词窗口） */
  private lyricRawText: string = '';
  private swiperController: SwiperController = new SwiperController();

  aboutToAppear() {
    this.alive = true;
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

    this.unsubscribePlayState = playerService.onPlayStateChange((isPlay: boolean) => {
      if (!this.alive) return;
      this.isPlaying = isPlay;
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
      if (this.lyricTimeline.length > 0) {
        this.currentLyricIndex = getCurrentLyricIndex(this.lyricTimeline, prog.nowPlayTime + settingsService.get().lyricOffset);
      }
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
    if (this.unsubscribePlayState) this.unsubscribePlayState();
    if (this.unsubscribeMusicInfo) this.unsubscribeMusicInfo();
    if (this.unsubscribeProgress) this.unsubscribeProgress();
    if (this.unsubscribeSleepTimer) this.unsubscribeSleepTimer();
    if (this.coverRetryTimer !== -1) {
      clearTimeout(this.coverRetryTimer);
      this.coverRetryTimer = -1;
    }
    if (this.lyricRetryTimer !== -1) {
      clearTimeout(this.lyricRetryTimer);
      this.lyricRetryTimer = -1;
    }
  }

  onBackPressed(): boolean {
    hilog.info(DOMAIN, TAG, 'onBackPressed session=%{public}s', this.pageSessionId);
    navigationService.back();
    return true;
  }

  onReady(params: Record<string, object | string | number | boolean | undefined>): void {
    hilog.info(DOMAIN, TAG, 'onReady session=%{public}s params=%{public}s', this.pageSessionId, JSON.stringify(params));
  }

  private normalizeCoverUrl(rawUrl: string): string {
    const url = (rawUrl ?? '').trim();
    if (!url) return '';
    if (url.startsWith('//')) return `http:${url}`;
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return '';
  }

  private canRenderCover(url: string): boolean {
    const value = (url ?? '').trim();
    if (value.length === 0) {
      return false;
    }
    if (value === 'null' || value === 'undefined') {
      return false;
    }
    return value.startsWith('http://') || value.startsWith('https://') || value.startsWith('//');
  }

  private downgradeCoverUrl(url: string): string {
    const value = (url ?? '').trim();
    if (!value.startsWith('https://')) {
      return '';
    }
    return `http://${value.substring(8)}`;
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

  private buildMusicKey(info: MusicInfo): string {
    return [
      info?.source ?? '',
      info?.id ?? '',
      info?.songmid ?? '',
      info?.name ?? '',
      info?.singer ?? '',
    ].join('|');
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

  private async ensureCoverReady(info: MusicInfo, force: boolean): Promise<void> {
    if (!this.alive || !info || !info.name) {
      return;
    }
    if (!force && this.pic.trim().length > 0 && this.canRenderCover(this.pic)) {
      return;
    }
    const seq = ++this.picLoadSeq;
    try {
      const picPath = await getPicPath({
        musicInfo: info,
        isRefresh: force,
      });
      if (!this.alive || seq !== this.picLoadSeq) {
        return;
      }
      // 优先用 getPicPath 结果，否则用已有的 pic，都没有则尝试 info 中的原始字段
      const raw = picPath || this.pic || info.pic || info.img || '';
      const normalized = this.normalizeCoverUrl(raw);
      if (normalized.length > 0) {
        this.pic = normalized;
        this.coverRetryCount = 0;
      } else {
        // 明确置空以触发默认封面显示，避免无效旧值残留导致空白。
        this.pic = '';
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'ensureCoverReady failed: %{public}s', JSON.stringify(err));
      if (this.coverRetryCount < 2 && this.alive) {
        this.coverRetryCount += 1;
        if (this.coverRetryTimer !== -1) {
          clearTimeout(this.coverRetryTimer);
        }
        this.coverRetryTimer = setTimeout(() => {
          const latest = playerService.getCurrentMusicInfo();
          void this.ensureCoverReady(latest, true);
        }, 600);
      }
    }
  }

  private async ensureLyricReady(info: MusicInfo, force: boolean): Promise<void> {
    if (!this.alive || !info || !info.name) {
      if (this.lyricLines.length === 0) {
        this.lyricLines = [t('player_no_lyric')];
      }
      return;
    }
    const targetKey = this.buildMusicKey(info);
    const hasUsableLyric = this.lyricTimeline.length > 0 ||
      (this.lyricLines.length > 0 && this.lyricLines[0] !== t('loading_lyric'));
    // 已有可用歌词时，后台刷新不抢占 UI，避免切 tab 期间出现“空白/失败占位”闪烁。
    if ((force || this.lyricTimeline.length === 0) && !hasUsableLyric) {
      this.lyricLines = [t('loading_lyric')];
      this.secondaryLyricLines = [];
      this.currentLyricIndex = -1;
    }
    const seq = ++this.lyricLoadSeq;
    try {
      const lyricInfo = await getLyricInfo({
        musicInfo: info,
        isRefresh: force,
      });
      if (!this.alive || seq !== this.lyricLoadSeq) {
        return;
      }
      // 歌词交给播放器统一维护：系统播控、桌面歌词、播放页共用同一份数据
      // setLyricData 内部按设置做简繁转换，这里读回转好的文本，保证主/译文一致
      playerService.setLyricData(lyricInfo.lyric || '');
      this.lyricRawText = playerService.getLyricText();
      const primaryLines = parseLrc(this.lyricRawText);
      const secondaryLines = parseLrc(convertChinese(lyricInfo.tlyric || '', settingsService.get().s2tMode));
      if (primaryLines.length === 0) {
        this.lyricTimeline = [];
        this.lyricLines = [t('pure_music')];
        this.secondaryLyricLines = [];
        this.currentLyricIndex = -1;
        return;
      }
      const secondaries: string[] = [];
      let sIdx = 0;
      for (let i = 0; i < primaryLines.length; i++) {
        const p = primaryLines[i];
        while (sIdx + 1 < secondaryLines.length && secondaryLines[sIdx + 1].time <= p.time) {
          sIdx += 1;
        }
        if (sIdx < secondaryLines.length && Math.abs(secondaryLines[sIdx].time - p.time) <= 0.35) {
          secondaries.push(secondaryLines[sIdx].text);
        } else {
          secondaries.push('');
        }
      }
      this.lyricTimeline = primaryLines;
      this.lyricLines = primaryLines.map((line: LyricLine) => line.text);
      this.rebuildRomaLines();
      this.secondaryLyricLines = secondaries;
      const now = playerService.getProgress().nowPlayTime;
      this.currentLyricIndex = getCurrentLyricIndex(this.lyricTimeline, now);
      this.lyricSongKey = targetKey;
      this.lyricRetryCount = 0;
    } catch (err) {
      if (!this.alive || seq !== this.lyricLoadSeq) {
        return;
      }
      const canKeepCurrentLyric = this.lyricSongKey === targetKey && this.lyricTimeline.length > 0;
      if (!canKeepCurrentLyric) {
        this.lyricTimeline = [];
        this.lyricLines = [t('lyric_load_failed')];
        this.secondaryLyricLines = [];
        this.currentLyricIndex = -1;
      }
      hilog.warn(DOMAIN, TAG, 'ensureLyricReady failed: %{public}s', JSON.stringify(err));
      if (this.lyricRetryCount < 2 && this.alive) {
        this.lyricRetryCount += 1;
        if (this.lyricRetryTimer !== -1) {
          clearTimeout(this.lyricRetryTimer);
        }
        this.lyricRetryTimer = setTimeout(() => {
          const latest = playerService.getCurrentMusicInfo();
          void this.ensureLyricReady(latest, true);
        }, 700);
      }
    }
  }

  private async togglePlay(): Promise<void> {
    if (this.isPlaying) {
      await playerService.pause();
    } else {
      await playerService.play();
    }
  }

  private async playPrev(): Promise<void> {
    await playerService.playPrev();
  }

  private async playNext(): Promise<void> {
    await playerService.playNext();
  }

  private async seekTo(progress: number): Promise<void> {
    const duration = playerService.getProgress().maxPlayTime;
    if (duration <= 0) return;
    await playerService.seekTo(duration * progress);
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

      await settingsService.update({
        playMode: this.playMode as PlayMode,
        showDesktopLyric: this.showDesktopLyric,
        sleepTimerEnabled: this.timeoutExitEnabled,
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'savePlaySettings failed: %{public}s', JSON.stringify(err));
    }
  }

  private togglePlayMode(): void {
    const modes = ['listLoop', 'singleLoop', 'random', 'sequential'];
    const idx = modes.indexOf(this.playMode);
    const nextIdx = idx >= 0 ? (idx + 1) % modes.length : 0;
    this.playMode = modes[nextIdx];
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
    const primary = DesignTokens.labelPrimary(this.theme);
    const tertiary = DesignTokens.labelTertiary(this.theme);
    this.getUIContext().getPromptAction().showActionMenu({
      title: t('sleep_timer_setting'),
      buttons: [
        { text: t('sleep_15min'), color: primary },
        { text: t('sleep_30min'), color: primary },
        { text: t('sleep_60min'), color: primary },
        { text: t('sleep_disable'), color: primary },
        { text: t('cancel'), color: tertiary },
      ],
    }, (err: BusinessError, data: ActionMenuResult) => {
      if (err) return;
      const ix = data.index;
      if (ix < 0 || ix > 3) return;
      if (ix === 3) {
        this.timeoutExitEnabled = false;
        this.timeoutExitLabel = t('sleep_timer_setting');
        sleepTimerService.stop();
        sleepTimerService.cancelPendingExit();
        this.showToast(t('toast_sleep_cancel'));
        return;
      }
      const mins = ix === 0 ? 15 : (ix === 1 ? 30 : 60);
      this.timeoutExitEnabled = true;
      this.timeoutExitLabel = `${mins} ${t('settings_sleep_minutes')}`;
      // 统一由 SleepTimerService 计时，保证与设置页状态一致
      sleepTimerService.start(mins);
      this.showToast(`${t('toast_sleep_set')} ${mins} ${t('toast_sleep_start')}`);
    });
  }

  private async addToPlaylist(): Promise<void> {
    const currentMusicInfo = playerService.getCurrentMusicInfo();
    if (!currentMusicInfo || !currentMusicInfo.name) {
      this.showToast(t('player_no_song'));
      return;
    }
    const options: PlaylistOptionRow[] = [];
    options.push({ id: LIST_IDS.DEFAULT, name: t('default_list_label') });
    options.push({ id: LIST_IDS.LOVE, name: t('love_title') });
    const userLists = getUserList();
    for (let i = 0; i < userLists.length; i++) {
      options.push({ id: userLists[i].id, name: userLists[i].name });
    }
    const maxCount = Math.min(5, options.length);
    if (maxCount <= 0) {
      this.showToast(t('no_playlist_available'));
      return;
    }
    const primary = DesignTokens.labelPrimary(this.theme);
    const tertiary = DesignTokens.labelTertiary(this.theme);
    const display = options.slice(0, maxCount);
    const opt0 = maxCount > 0 ? display[0].name : t('unnamed_list');
    const opt1 = maxCount > 1 ? display[1].name : t('unnamed_list');
    const opt2 = maxCount > 2 ? display[2].name : t('unnamed_list');
    const opt3 = maxCount > 3 ? display[3].name : t('unnamed_list');
    const opt4 = maxCount > 4 ? display[4].name : t('unnamed_list');
    this.getUIContext().getPromptAction().showActionMenu({
      title: t('player_add_to_list'),
      buttons: [
        { text: opt0, color: primary },
        { text: opt1, color: primary },
        { text: opt2, color: primary },
        { text: opt3, color: primary },
        { text: opt4, color: primary },
        { text: t('cancel'), color: tertiary },
      ],
    }, async (err: BusinessError, data: ActionMenuResult) => {
      if (err) return;
      const ix = data.index;
      if (ix < 0 || ix >= maxCount) return;
      const target = display[ix];
      try {
        const musicItem: MusicItem = {
          id: currentMusicInfo.id || currentMusicInfo.songmid || '',
          name: currentMusicInfo.name,
          singer: currentMusicInfo.singer,
          album: currentMusicInfo.album ?? currentMusicInfo.albumName ?? '',
          albumId: null,
          duration: 0,
          source: currentMusicInfo.source,
          pic: currentMusicInfo.pic || currentMusicInfo.img || '',
          lrc: null,
        };
        await addMusicToList(target.id, musicItem);
        this.showToast(tf('toast_added_quoted', [target.name]));
      } catch (e) {
        this.showToast(t('toast_add_list_fail'));
      }
    });
  }

  private showMoreActions(): void {
    this.showMoreActionsDialog = true;
  }

  /**
   * 「更多操作」的动作列表
   * 文案随状态变化（歌词页/封面页、桌面歌词开关、定时等待态），所以由页面构造后交给面板渲染。
   */
  private actionRows(): PlayActionRow[] {
    return [
      { key: 'addToList', icon: $r('app.media.ic_pd_playlist'), label: t('player_add_to_list') },
      { key: 'comment', icon: $r('app.media.ic_pd_comment'), label: t('player_comment') },
      {
        key: 'switchTab',
        icon: $r('app.media.ic_pd_lyric'),
        label: this.currentTab === 0 ? t('switch_to_lyric') : t('switch_to_cover'),
      },
      {
        key: 'desktopLyric',
        icon: $r('app.media.ic_pd_lyric'),
        label: this.showDesktopLyric ? t('close_desktop_lyric') : t('open_desktop_lyric'),
      },
      {
        key: 'sleepTimer',
        icon: $r('app.media.ic_pd_timer'),
        label: this.sleepWaitingTrackEnd ? t('sleep_cancel_wait') : t('sleep_timer_setting'),
      },
      { key: 'saveLyric', icon: $r('app.media.ic_pd_lyric'), label: t('media_save_lyric') },
      { key: 'saveCover', icon: $r('app.media.ic_pd_comment'), label: t('media_save_cover') },
      { key: 'speed', icon: $r('app.media.ic_pd_timer'), label: t('play_speed') },
      { key: 'lyricOffset', icon: $r('app.media.ic_pd_lyric'), label: t('lyric_offset') },
      { key: 'dislike', icon: $r('app.media.ic_pd_comment'), label: t('dislike_title') },
      { key: 'lyricDisplay', icon: $r('app.media.ic_pd_lyric'), label: t('lyric_display') },
      { key: 'switchSource', icon: $r('app.media.ic_pd_loop'), label: t('switch_source') },
      { key: 'volume', icon: $r('app.media.ic_pd_timer'), label: t('settings_volume') },
      { key: 'queue', icon: $r('app.media.ic_pd_playlist'), label: t('play_queue') },
    ];
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
        sleepTimerService.cancelPendingExit();
        this.sleepWaitingTrackEnd = false;
        this.showToast(t('toast_sleep_cancel'));
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
      void this.pickLyricOffset();
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

  /** 歌词偏移选择 */
  private async pickLyricOffset(): Promise<void> {
    const offset = await showLyricOffsetMenu(settingsService.get().lyricOffset);
    if (offset === null) {
      return;
    }
    await settingsService.update({ lyricOffset: offset });
    this.showToast(`${t('lyric_offset')}: ${offset > 0 ? '+' : ''}${offset}s`);
  }

  /** 歌词显示设置（翻译 / 罗马音 / 字号 / 对齐 / 进度） */
  private async pickLyricDisplay(): Promise<void> {
    const settings = settingsService.get();
    const action = await showLyricDisplayMenu({
      translation: settings.showLyricTranslation,
      roma: settings.showLyricRoma,
      fontSize: settings.lyricFontSize,
      alignLabel: this.alignLabel(settings.lyricAlign),
      progress: settings.showLyricProgress,
    });
    if (action === null) {
      return;
    }
    if (action === 'translation') {
      const next = !settings.showLyricTranslation;
      await settingsService.update({ showLyricTranslation: next });
      this.showToast(`${t('lyric_translation')}: ${next ? t('on') : t('off')}`);
    } else if (action === 'roma') {
      const next = !settings.showLyricRoma;
      await settingsService.update({ showLyricRoma: next });
      this.rebuildRomaLines();
      this.showToast(`${t('lyric_roma')}: ${next ? t('on') : t('off')}`);
    } else if (action === 'fontSize') {
      const sizes: number[] = [14, 16, 18, 20, 22, 24];
      const index = sizes.indexOf(settings.lyricFontSize);
      const nextSize = sizes[(index + 1) % sizes.length];
      await settingsService.update({ lyricFontSize: nextSize });
      this.showToast(`${t('lyric_font_size')}: ${nextSize}`);
    } else if (action === 'align') {
      const modes: string[] = ['center', 'left', 'right'];
      const index = modes.indexOf(settings.lyricAlign);
      const nextAlign = modes[(index + 1) % modes.length];
      await settingsService.update({ lyricAlign: nextAlign });
      this.showToast(`${t('lyric_align')}: ${this.alignLabel(nextAlign)}`);
    } else {
      const next = !settings.showLyricProgress;
      await settingsService.update({ showLyricProgress: next });
      this.showToast(`${t('lyric_progress')}: ${next ? t('on') : t('off')}`);
    }
  }

  /** 不喜欢：按粒度写入屏蔽规则（播放时自动跳过） */
  private async pickDislike(): Promise<void> {
    const info = playerService.getCurrentMusicInfo();
    if (!info.name) {
      this.showToast(t('player_no_song'));
      return;
    }
    const level = await showDislikeMenu();
    if (level === null) {
      return;
    }
    try {
      await dislikeList.load();
      if (level === 'song') {
        await dislikeList.add(info.name, info.singer);
      } else if (level === 'singer') {
        await dislikeList.add('', info.singer);
      } else {
        await dislikeList.add(info.name, '');
      }
      this.showToast(tf('dislike_added', [dislikeList.count().toString()]));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'pickDislike failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_operation_failed'));
    }
  }

  /** 音量调节（对齐安卓版播放页 SettingPopup → SettingVolume，含静音切换） */
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


  /** 对齐方式的中文/英文展示名 */
  private alignLabel(mode: string): string {
    if (mode === 'left') {
      return t('lyric_align_left');
    }
    if (mode === 'right') {
      return t('lyric_align_right');
    }
    return t('lyric_align_center');
  }



  /** 歌词偏移：正值让歌词更早出现，负值延后 */

  /** 保存当前歌词到本地文件 */
  private async saveLyricToFile(): Promise<void> {
    const info = playerService.getCurrentMusicInfo();
    if (!info || !info.name) {
      this.showToast(t('player_no_song'));
      return;
    }
    if (!this.lyricRawText) {
      this.showToast(t('media_lyric_empty'));
      return;
    }
    try {
      const result: SaveResult = await mediaSaveService.saveLyricToFile(info, this.lyricRawText);
      this.showToast(result.success ? t('media_save_success') : (result.error || t('media_save_fail')));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'saveLyricToFile failed: %{public}s', JSON.stringify(err));
      this.showToast(t('media_save_fail'));
    }
  }

  /** 保存当前封面到本地文件 */
  private async saveCoverToFile(): Promise<void> {
    const info = playerService.getCurrentMusicInfo();
    if (!info || !info.name) {
      this.showToast(t('player_no_song'));
      return;
    }
    const imageUrl = info.pic || info.img || '';
    if (!imageUrl) {
      this.showToast(t('media_url_empty'));
      return;
    }
    try {
      const result: SaveResult = await mediaSaveService.saveCoverToFile(info, imageUrl);
      this.showToast(result.success ? t('media_save_success') : (result.error || t('media_save_fail')));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'saveCoverToFile failed: %{public}s', JSON.stringify(err));
      this.showToast(t('media_save_fail'));
    }
  }

  private viewComments(): void {
    const currentMusicInfo = playerService.getCurrentMusicInfo();
    if (!currentMusicInfo || !currentMusicInfo.name) {
      this.showToast(t('player_no_song'));
      return;
    }
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
    switch (this.playMode) {
      case 'listLoop': return t('mode_list_loop');
      case 'singleLoop': return t('mode_single_loop');
      case 'random': return t('mode_random');
      case 'sequential': return t('mode_sequential');
      default: return t('mode_list_loop');
    }
  }

  build() {
    Stack() {
      // 动态背景：封面高斯模糊垫底（设置 → 外观 → 动态背景）
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

      Column() {
        this.NavigationBar()
        this.TabSwitchBar()

        Swiper(this.swiperController) {
          this.AlbumArt()
          // 滑动切换的视觉反馈：非当前页轻微缩小淡出（@Builder 不能链式修饰，包一层容器）
          Column() {
            LyricView({
              lyricLines: this.lyricLines,
              secondaryLyricLines: this.secondaryLyricLines,
              romaLines: this.romaLines,
              currentLyricIndex: this.currentLyricIndex,
            })

            // 歌词页播放进度（设置可开）：左下角浮层显示 当前/总时长
            if (this.showLyricProgress) {
              Row() {
                Text(this.currentTime)
                  .fontSize(DesignTokens.fontMicro())
                  .fontColor(DesignTokens.labelSecondary(this.theme))
                Text(' / ')
                  .fontSize(DesignTokens.fontMicro())
                  .fontColor(DesignTokens.labelTertiary(this.theme))
                Text(this.totalTime)
                  .fontSize(DesignTokens.fontMicro())
                  .fontColor(DesignTokens.labelTertiary(this.theme))
              }
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .backgroundColor(DesignTokens.mutedFill(this.theme))
              .borderRadius(12)
              .margin({ left: 16, bottom: 8 })
              .alignSelf(ItemAlign.Start)
            }
          }
          .justifyContent(FlexAlign.SpaceBetween)
          .width('100%')
          .height('100%')
          .scale({ x: this.currentTab === 1 ? 1 : 0.94, y: this.currentTab === 1 ? 1 : 0.94 })
          .opacity(this.currentTab === 1 ? 1 : 0.7)
          .animation({ duration: 260, curve: Curve.EaseOut })
        }
        .index(this.currentTab)
        .width('100%')
        .layoutWeight(1)
        .duration(300)
        .curve(Curve.EaseOut)
        .indicator(false)
        .loop(false)
        .onChange((newIndex: number) => {
          this.currentTab = newIndex;
          if (newIndex === 0) {
            if (!this.canRenderCover(this.pic)) {
              const currentMusicInfo = playerService.getCurrentMusicInfo();
              void this.ensureCoverReady(currentMusicInfo, false);
            }
          } else {
            const hasLyric = this.lyricTimeline.length > 0 ||
              (this.lyricLines.length > 0 && this.lyricLines[0] !== t('player_no_lyric'));
            if (!hasLyric) {
              const currentMusicInfo = playerService.getCurrentMusicInfo();
              void this.ensureLyricReady(currentMusicInfo, false);
            }
          }
        })

        this.PlayerControls()
      }
      .width('100%')
      .height('100%')

      // 四个面板统一由组件承载（底部面板 + 分组卡片）
      if (this.showMoreActionsDialog) {
        MoreActionsSheet({
          visible: $showMoreActionsDialog,
          // 标题用当前歌曲，用户才知道这些操作作用于哪首（此前误用了播放队列的文案）
          title: this.singer.length > 0 ? `${this.musicName} - ${this.singer}` : this.musicName,
          rows: this.actionRows(),
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




  @Builder
  NavigationBar() {
    Row() {
      NavBackButton()

      Column() {
        Text(this.musicName || t('not_playing'))
          .fontSize(DesignTokens.fontTitle())
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textShadow(this.fontShadow ? PLAY_TEXT_SHADOW : undefined)
        if (this.singer && this.singer.trim().length > 0) {
          Text(this.singer)
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .maxLines(1)
            .textShadow(this.fontShadow ? PLAY_TEXT_SHADOW : undefined)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Blank()

      Stack() {
        Circle({ width: 34, height: 34 })
          .fill(DesignTokens.mutedFill(this.theme))
        Image($r('app.media.ic_pd_more'))
          .width(16)
          .height(16)
          .fillColor(DesignTokens.labelSecondary(this.theme))
      }
      .responseRegion(DesignTokens.touchRegion(34))
      .onClick(() => {
        this.showMoreActions();
      })
    }
    .width('100%')
    .height(60)
    .padding({ left: 14, right: 14, top: 8, bottom: 6 })
    .backgroundColor(DesignTokens.chromeBar(this.theme))
  }

  @Builder
  TabSwitchBar() {
    Row() {
      SegmentedBar({
        options: [
          { id: 'cover', label: t('play_tab_cover') },
          { id: 'lyric', label: t('play_tab_lyric') },
        ],
        activeId: this.currentTab === 0 ? 'cover' : 'lyric',
        equalWidth: true,
        fontSize: DesignTokens.fontBody(),
        onSelect: (id: string): void => {
          if (id === 'cover') {
            this.switchToCoverTab();
          } else {
            this.switchToLyricTab();
          }
        },
      })
    }
    .width(176)
    .margin({ top: 8, bottom: 10 })
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
    })
  }

  /** 封面加载失败：先尝试降级 URL，再重试一次，最后退回占位图 */
  private handleCoverLoadError(): void {
    const downgradedUrl = this.downgradeCoverUrl(this.pic);
    if (downgradedUrl.length > 0 && downgradedUrl !== this.pic) {
      this.pic = downgradedUrl;
      return;
    }
    if (this.coverRetryCount < 1) {
      this.coverRetryCount += 1;
      const currentMusicInfo = playerService.getCurrentMusicInfo();
      void this.ensureCoverReady(currentMusicInfo, true);
      return;
    }
    // 二次失败后回退到占位图，避免页面出现大片空白区域
    this.pic = '';
  }

  /** 长按封面的快捷操作（ActionMenu 最多 6 项，含取消） */
  private showCoverQuickMenu(): void {
    const primary = DesignTokens.labelPrimary(this.theme);
    const info = playerService.getCurrentMusicInfo();
    const isLoved = info.id ? isInLoveList(info.id) : false;
    this.getUIContext().getPromptAction().showActionMenu({
      title: info.name || t('player_title'),
      buttons: [
        { text: isLoved ? t('player_unlove') : t('player_love'), color: primary },
        { text: t('player_download'), color: primary },
        { text: t('player_share'), color: primary },
        { text: t('media_save_cover'), color: primary },
        { text: t('player_comment'), color: primary },
        { text: t('cancel'), color: DesignTokens.labelTertiary(this.theme) },
      ],
    }, (err: BusinessError, data: ActionMenuResult) => {
      if (err) {
        return;
      }
      if (data.index === 0) {
        void this.toggleLoveCurrent();
      } else if (data.index === 1) {
        void this.downloadCurrent();
      } else if (data.index === 2) {
        void this.shareCurrent();
      } else if (data.index === 3) {
        void this.saveCoverToFile();
      } else if (data.index === 4) {
        this.viewComments();
      }
    });
  }

  /** 收藏 / 取消收藏当前歌曲 */
  private async toggleLoveCurrent(): Promise<void> {
    const info = playerService.getCurrentMusicInfo();
    if (!info.id || !info.name) {
      this.showToast(t('player_no_song'));
      return;
    }
    try {
      const loved = await toggleLoveList({
        id: info.id,
        name: info.name,
        singer: info.singer,
        album: info.album ?? info.albumName ?? '',
        albumId: info.albumId ?? null,
        duration: 0,
        source: info.source ?? '',
        pic: info.pic ?? info.img ?? '',
        lrc: null,
      });
      this.showToast(loved ? t('player_loved') : t('player_unloved_ok'));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'toggleLoveCurrent failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_operation_failed'));
    }
  }

  /** 下载当前歌曲（走统一下载服务，下载页可见） */
  private async downloadCurrent(): Promise<void> {
    const info = playerService.getCurrentMusicInfo();
    if (!info.id || !info.name) {
      this.showToast(t('player_no_song'));
      return;
    }
    try {
      const taskId = await download.startDownload({ musicInfo: info });
      hilog.info(DOMAIN, TAG, 'download started: %{public}s', taskId);
      this.showToast(tf('toast_download_start_song', [info.name]));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'downloadCurrent failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_download_failed_network'));
    }
  }

  /** 分享：按「设置 → 分享方式」走系统分享，失败自动回退剪贴板 */
  private async shareCurrent(): Promise<void> {
    const info = playerService.getCurrentMusicInfo();
    if (!info.name) {
      this.showToast(t('player_no_song'));
      return;
    }
    // 附上当前播放位置 + 平台详情页链接（与安卓版分享内容一致）
    const progress = playerService.getProgress();
    const extra = progress.nowPlayTime > 0 ? progress.nowPlayTimeStr : '';
    const withPosition = `[${sourceLabel(info.source ?? '')}] ${buildShareText(info, extra)}`;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await shareText(context, withPosition, info.name, getMusicDetailPageUrl(info));
      if (result === 'clipboard') {
        this.showToast(t('toast_share_copy'));
      } else if (result === 'failed') {
        this.showToast(t('toast_operation_failed'));
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'shareCurrent failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_operation_failed'));
    }
  }

  @Builder
  PlayerControls() {
    Column() {
      Row() {
        Text(this.currentTime)
          .fontSize(DesignTokens.fontMicro())
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .width(44)
          .textAlign(TextAlign.Center)
        Slider({
          // 拖动中显示手指位置（previewProgress），松手才真正 seek
          value: (this.isSeeking ? this.previewProgress : this.progress) * 100,
          min: 0,
          max: 100,
          style: SliderStyle.OutSet,
        })
          .width('calc(100% - 88vp)')
          .height(24)
          .blockColor(DesignTokens.accent())
          .trackColor(DesignTokens.mutedFill(this.theme))
          .selectedColor(DesignTokens.accent())
          .onChange((value: number, mode: SliderChangeMode) => {
            // 「允许拖动进度条」关闭时只做展示，避免误触跳转
            if (!this.allowProgressBarSeek) {
              // 只在手势开始/结束时提示一次，避免移动过程中刷屏
              if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.End) {
                this.showToast(t('toast_seek_disabled'));
              }
              return;
            }
            const ratio = Math.max(0, Math.min(1, value / 100));
            if (mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving) {
              // 拖动中只更新预览，不发 seek 请求（否则会疯狂打断播放）
              this.isSeeking = true;
              this.previewProgress = ratio;
              return;
            }
            // End / Click：提交一次真正的 seek
            this.isSeeking = false;
            void this.seekTo(ratio);
          })
        Text(this.isSeeking ? this.previewTimeText() : this.currentTime)
          .fontSize(DesignTokens.fontMicro())
          .fontColor(this.isSeeking ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme))
          .width(44)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ left: 14, right: 14 })

      Row({ space: 26 }) {
        Stack() {
          Circle({ width: DesignTokens.ctrlMd(), height: DesignTokens.ctrlMd() })
            .fill(DesignTokens.mutedFill(this.theme))
          Image($r('app.media.ic_pd_prev'))
            .width(DesignTokens.iconLg())
            .height(DesignTokens.iconLg())
            .fillColor(DesignTokens.labelPrimary(this.theme))
        }
        .onClick(() => void this.playPrev())
        Stack() {
          Circle({ width: DesignTokens.ctrlLg(), height: DesignTokens.ctrlLg() })
            .fill(DesignTokens.accent())
          if (this.isPlaying) {
            Image($r('app.media.ic_pd_pause'))
              .width(20)
              .height(20)
              .fillColor(DesignTokens.onAccent())
          } else {
            Image($r('app.media.ic_pd_play'))
              .width(20)
              .height(20)
              .fillColor(DesignTokens.onAccent())
              .margin({ left: 1 })
          }
        }
        .onClick(() => void this.togglePlay())
        Stack() {
          Circle({ width: DesignTokens.ctrlMd(), height: DesignTokens.ctrlMd() })
            .fill(DesignTokens.mutedFill(this.theme))
          Image($r('app.media.ic_pd_next'))
            .width(DesignTokens.iconLg())
            .height(DesignTokens.iconLg())
            .fillColor(DesignTokens.labelPrimary(this.theme))
        }
        .onClick(() => void this.playNext())
      }
      .width('100%')
      .height(92)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Row() {
        this.buildMenuButton($r('app.media.ic_pd_playlist'), t('player_add_to_list'), () => void this.addToPlaylist())
        this.buildMenuButton($r('app.media.ic_pd_loop'), this.getPlayModeText(), () => this.togglePlayMode())
        this.buildMenuButton($r('app.media.ic_pd_comment'), t('player_comment'), () => this.viewComments())
      }
      .width('100%')
      .height(78)
      .justifyContent(FlexAlign.SpaceAround)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 10, right: 10 })

      Blank()
        .width('100%')
        .height(12)
    }
    .width('100%')
    .padding({ bottom: 8 })
    .backgroundColor(DesignTokens.pageBg(this.theme))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private buildMenuButton(icon: Resource, label: string, onClick: () => void) {
    Column({ space: 5 }) {
      Stack() {
        Circle({ width: 30, height: 30 })
          .fill(DesignTokens.mutedFill(this.theme))
        Image(icon)
          .width(DesignTokens.iconSm())
          .height(DesignTokens.iconSm())
          .fillColor(DesignTokens.labelSecondary(this.theme))
      }
      Text(label)
        .fontSize(DesignTokens.fontMicro())
        .fontColor(DesignTokens.labelSecondary(this.theme))
        .maxLines(1)
        .textAlign(TextAlign.Center)
    }
    .width(68)
    .height(60)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(onClick)
  }
  /**
   * 手动换源：列出同一首歌在其它源的匹配结果，选中后切源重新取链播放。
   * 候选来自 ResolvePlayback.getOtherSource（跨源搜索 + 相似度排序）。
   */
  private async showSourceSwitchMenu(): Promise<void> {
    const current = playerService.getCurrentMusicInfo();
    if (!current || !current.name) {
      this.showToast(t('player_no_song'));
      return;
    }
    this.showToast(t('switch_source_searching'));
    let candidates: MusicInfo[] = [];
    try {
      candidates = await getOtherSource(current);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getOtherSource failed: %{public}s', JSON.stringify(err));
    }
    if (candidates.length === 0) {
      this.showToast(t('switch_source_empty'));
      return;
    }
    // 每个源只保留排序最靠前的一个（ActionMenu 最多 6 个按钮，含取消）
    const picked: MusicInfo[] = [];
    const usedSources: Set<string> = new Set();
    for (let i = 0; i < candidates.length && picked.length < 5; i++) {
      const item = candidates[i];
      const src = item.source ?? '';
      if (src.length === 0 || usedSources.has(src)) {
        continue;
      }
      usedSources.add(src);
      picked.push(item);
    }
    if (picked.length === 0) {
      this.showToast(t('switch_source_empty'));
      return;
    }

    // 候选项数量是动态的（ActionMenu 固定最多 6 项放不下），用自定义弹窗列表展示
    this.sourceCandidates = picked;
    this.showSourceDialog = true;
  }

  /** 切到指定源的匹配结果并播放 */
  private async switchToSource(target: MusicInfo): Promise<void> {
    try {
      const url = await getMusicUrl({ musicInfo: target, allowToggleSource: false });
      if (!url || url.length === 0) {
        this.showToast(t('switch_source_failed'));
        return;
      }
      const durationSec = target.interval ? this.parseIntervalSeconds(target.interval) : 0;
      const song: SongInfo = {
        id: target.id || target.songmid || '',
        songmid: target.songmid || target.id,
        url: url,
        title: target.name,
        artist: target.singer,
        album: target.album ?? target.albumName ?? '',
        artwork: target.pic ?? target.img ?? null,
        duration: durationSec,
        source: target.source,
        hash: target.hash,
        strMediaMid: target.strMediaMid,
        songId: target.songId,
        albumId: target.albumId,
        copyrightId: target.copyrightId,
      };
      playerService.setPlayList([song], 0);
      await playerService.playFromSelection(song, url, durationSec);
      this.showToast(`${t('switch_source')}: ${sourceLabel(target.source ?? '')}`);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'switchToSource failed: %{public}s', JSON.stringify(err));
      this.showToast(t('switch_source_failed'));
    }
  }

  /** "mm:ss" → 秒 */
  private parseIntervalSeconds(interval: string): number {
    const parts = interval.split(':');
    let seconds = 0;
    for (let i = 0; i < parts.length; i++) {
      const value = parseInt(parts[i], 10);
      if (!isNaN(value)) {
        seconds = seconds * 60 + value;
      }
    }
    return seconds;
  }

  /** 不喜欢：按 歌曲 / 歌手 / 歌名 三种粒度加入屏蔽（播放时自动跳过） */

}
