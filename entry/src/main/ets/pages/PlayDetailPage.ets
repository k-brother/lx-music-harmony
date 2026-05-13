import hilog from '@ohos.hilog';
import { BusinessError } from '@kit.BasicServicesKit';
import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { playerService, MusicInfo, ProgressInfo } from '../service/PlayerService';
import { navigationService } from '../service/NavigationService';
import { LyricView } from '../components/common/LyricView';
import { RouteName, NavigationParams } from '../service/NavigationService';
import { getUserList, LIST_IDS, addMusicToList, MusicItem } from '../service/ListService';
import { getLyricInfo, getPicPath } from '../core/music/MusicFeatureEntry';
import { parseLrc, getCurrentLyricIndex, LyricLine } from '../core/music/MusicParsingUtils';
import { DesignTokens } from '../theme/DesignTokens';
import { NavBackButton } from '../components/common/NavBackButton';

const DOMAIN: number = 0x0001;
const TAG: string = 'PlayDetailPage';

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
  @State currentTab: number = 0; // 0: 封面, 1: 歌词
  @State isPlaying: boolean = false;
  @State musicName: string = '';
  @State singer: string = '';
  @State album: string = '';
  @State pic: string = '';
  @State progress: number = 0;
  @State currentTime: string = '00:00';
  @State totalTime: string = '00:00';
  @State lyricLines: string[] = ['加载歌词中...'];
  @State secondaryLyricLines: string[] = [];
  @State currentLyricIndex: number = -1;
  @State playMode: string = 'listLoop';
  @State showDesktopLyric: boolean = false;
  @State timeoutExitEnabled: boolean = false;
  @State timeoutExitLabel: string = '定时退出';
  @State showMoreActionsDialog: boolean = false;
  @State pressedMoreActionIndex: number = -1;

  private unsubscribePlayState: (() => void) | null = null;
  private unsubscribeMusicInfo: (() => void) | null = null;
  private unsubscribeProgress: (() => void) | null = null;
  private alive: boolean = false;
  private timeoutExitTimer: number = -1;
  private pageSessionId: string = '';
  private lyricTimeline: LyricLine[] = [];
  private lyricLoadSeq: number = 0;
  private picLoadSeq: number = 0;
  private coverRetryTimer: number = -1;
  private lyricRetryTimer: number = -1;
  private coverRetryCount: number = 0;
  private lyricRetryCount: number = 0;
  private lyricSongKey: string = '';
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
        this.currentLyricIndex = getCurrentLyricIndex(this.lyricTimeline, prog.nowPlayTime);
      }
    });
  }

  aboutToDisappear() {
    hilog.info(DOMAIN, TAG, 'aboutToDisappear session=%{public}s', this.pageSessionId);
    this.alive = false;
    if (this.unsubscribePlayState) this.unsubscribePlayState();
    if (this.unsubscribeMusicInfo) this.unsubscribeMusicInfo();
    if (this.unsubscribeProgress) this.unsubscribeProgress();
    if (this.timeoutExitTimer !== -1) {
      clearTimeout(this.timeoutExitTimer);
      this.timeoutExitTimer = -1;
    }
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
      (this.lyricLines.length > 0 && this.lyricLines[0] !== '暂无歌词');
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
      this.musicName = '未播放';
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
        this.lyricLines = ['暂无歌词'];
      }
      return;
    }
    const targetKey = this.buildMusicKey(info);
    const hasUsableLyric = this.lyricTimeline.length > 0 ||
      (this.lyricLines.length > 0 && this.lyricLines[0] !== '加载歌词中...');
    // 已有可用歌词时，后台刷新不抢占 UI，避免切 tab 期间出现“空白/失败占位”闪烁。
    if ((force || this.lyricTimeline.length === 0) && !hasUsableLyric) {
      this.lyricLines = ['加载歌词中...'];
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
      const primaryLines = parseLrc(lyricInfo.lyric || '');
      const secondaryLines = parseLrc(lyricInfo.tlyric || '');
      if (primaryLines.length === 0) {
        this.lyricTimeline = [];
        this.lyricLines = ['纯音乐，请欣赏'];
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
        this.lyricLines = ['歌词加载失败'];
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

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message, duration: 2000 });
    } catch (_e) {
      hilog.info(DOMAIN, TAG, '%{public}s', message);
    }
  }

  private showConfirmDialog(title: string, message: string): Promise<boolean> {
    return new Promise((resolve: (value: boolean) => void) => {
      this.getUIContext().getPromptAction().showDialog({
        title,
        message,
        buttons: [
          { text: '取消', color: DesignTokens.labelSecondary(this.theme) },
          { text: '确认', color: DesignTokens.accent() },
        ],
      }, (err: BusinessError, data: ActionMenuResult) => {
        if (err) {
          resolve(false);
          return;
        }
        resolve(data.index === 1);
      });
    });
  }

  private async loadPlaySettings(): Promise<void> {
    try {
      // 从 PlayerService 读取播放模式（已在 init 时从偏好设置加载）
      const currentMode = playerService.getPlayMode();
      this.playMode = currentMode;

      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'music_settings');
      this.showDesktopLyric = await pref.get('showDesktopLyric', false) as boolean;
      this.timeoutExitEnabled = await pref.get('timeoutExit', false) as boolean;
      this.timeoutExitLabel = this.timeoutExitEnabled ? '已启用' : '定时退出';
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'loadPlaySettings failed: %{public}s', JSON.stringify(err));
    }
  }

  private async savePlaySettings(): Promise<void> {
    try {
      // 同步播放模式到 PlayerService
      playerService.setPlayMode(this.playMode as 'listLoop' | 'singleLoop' | 'random' | 'sequential');

      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'music_settings');
      await pref.put('playMode', this.playMode);
      await pref.put('showDesktopLyric', this.showDesktopLyric);
      await pref.put('timeoutExit', this.timeoutExitEnabled);
      await pref.flush();
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
    this.showToast(`播放模式: ${this.getPlayModeText()}`);
  }

  private toggleDesktopLyric(): void {
    this.showDesktopLyric = !this.showDesktopLyric;
    void this.savePlaySettings();
    this.showToast(this.showDesktopLyric ? '已开启桌面歌词' : '已关闭桌面歌词');
  }

  private async toggleTimeoutExit(): Promise<void> {
    const primary = this.theme === 'dark' ? '#F5F5F7' : '#1D1D1F';
    const tertiary = '#8E8E93';
    this.getUIContext().getPromptAction().showActionMenu({
      title: '定时退出',
      buttons: [
        { text: '15分钟后停止播放', color: primary },
        { text: '30分钟后停止播放', color: primary },
        { text: '60分钟后停止播放', color: primary },
        { text: '关闭定时退出', color: primary },
        { text: '取消', color: tertiary },
      ],
    }, (err: BusinessError, data: ActionMenuResult) => {
      if (err) return;
      const ix = data.index;
      if (ix < 0 || ix > 3) return;
      if (this.timeoutExitTimer !== -1) {
        clearTimeout(this.timeoutExitTimer);
        this.timeoutExitTimer = -1;
      }
      if (ix === 3) {
        this.timeoutExitEnabled = false;
        this.timeoutExitLabel = '定时退出';
        void this.savePlaySettings();
        this.showToast('已关闭定时退出');
        return;
      }
      const mins = ix === 0 ? 15 : (ix === 1 ? 30 : 60);
      this.timeoutExitEnabled = true;
      this.timeoutExitLabel = `${mins}分钟后退出`;
      void this.savePlaySettings();
      this.timeoutExitTimer = setTimeout(() => {
        void playerService.pause();
        this.timeoutExitEnabled = false;
        this.timeoutExitLabel = '定时退出';
        this.showToast('已暂停播放（定时退出）');
      }, mins * 60 * 1000);
      this.showToast(`将在 ${mins} 分钟后暂停播放`);
    });
  }

  private async addToPlaylist(): Promise<void> {
    const currentMusicInfo = playerService.getCurrentMusicInfo();
    if (!currentMusicInfo || !currentMusicInfo.name) {
      this.showToast('当前没有正在播放的歌曲');
      return;
    }
    const options: PlaylistOptionRow[] = [];
    options.push({ id: LIST_IDS.DEFAULT, name: '默认列表' });
    options.push({ id: LIST_IDS.LOVE, name: '我喜欢' });
    const userLists = getUserList();
    for (let i = 0; i < userLists.length; i++) {
      options.push({ id: userLists[i].id, name: userLists[i].name });
    }
    const maxCount = Math.min(5, options.length);
    if (maxCount <= 0) {
      this.showToast('暂无可用歌单');
      return;
    }
    const primary = this.theme === 'dark' ? '#F5F5F7' : '#1D1D1F';
    const tertiary = '#8E8E93';
    const display = options.slice(0, maxCount);
    const opt0 = maxCount > 0 ? display[0].name : '未命名歌单';
    const opt1 = maxCount > 1 ? display[1].name : '未命名歌单';
    const opt2 = maxCount > 2 ? display[2].name : '未命名歌单';
    const opt3 = maxCount > 3 ? display[3].name : '未命名歌单';
    const opt4 = maxCount > 4 ? display[4].name : '未命名歌单';
    this.getUIContext().getPromptAction().showActionMenu({
      title: '添加到歌单',
      buttons: [
        { text: opt0, color: primary },
        { text: opt1, color: primary },
        { text: opt2, color: primary },
        { text: opt3, color: primary },
        { text: opt4, color: primary },
        { text: '取消', color: tertiary },
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
        this.showToast(`已添加到「${target.name}」`);
      } catch (e) {
        this.showToast('添加到歌单失败');
      }
    });
  }

  private showMoreActions(): void {
    this.pressedMoreActionIndex = -1;
    this.showMoreActionsDialog = true;
  }

  private onMoreActionSelected(index: number): void {
    this.pressedMoreActionIndex = -1;
    this.showMoreActionsDialog = false;
    void this.executeMoreAction(index);
  }

  private async executeMoreAction(index: number): Promise<void> {
    const labels = [
      '添加到歌单',
      '查看评论',
      this.currentTab === 0 ? '切换到歌词' : '切换到封面',
      this.showDesktopLyric ? '关闭桌面歌词' : '开启桌面歌词',
      '设置定时退出',
    ];
    const actionLabel = labels[index] ?? '执行此操作';
    const confirmed = await this.showConfirmDialog('确认操作', `是否确认${actionLabel}？`);
    if (!confirmed) {
      return;
    }

    const ix = index;
    if (ix === 0) {
      void this.addToPlaylist();
      return;
    }
    if (ix === 1) {
      this.viewComments();
      return;
    }
    if (ix === 2) {
      const toLyric = this.currentTab === 0;
      if (toLyric) {
        this.switchToLyricTab();
      } else {
        this.switchToCoverTab();
      }
      return;
    }
    if (ix === 3) {
      this.toggleDesktopLyric();
      return;
    }
    if (ix === 4) {
      void this.toggleTimeoutExit();
    }
  }

  private viewComments(): void {
    const currentMusicInfo = playerService.getCurrentMusicInfo();
    if (!currentMusicInfo || !currentMusicInfo.name) {
      this.showToast('当前没有正在播放的歌曲');
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
      case 'listLoop': return '列表循环';
      case 'singleLoop': return '单曲循环';
      case 'random': return '随机播放';
      case 'sequential': return '顺序播放';
      default: return '列表循环';
    }
  }

  build() {
    Stack() {
      Column() {
        this.NavigationBar()
        this.TabSwitchBar()

        Swiper(this.swiperController) {
          this.AlbumArt()
          LyricView({
            lyricLines: this.lyricLines,
            secondaryLyricLines: this.secondaryLyricLines,
            currentLyricIndex: this.currentLyricIndex,
          })
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
              (this.lyricLines.length > 0 && this.lyricLines[0] !== '暂无歌词');
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

      if (this.showMoreActionsDialog) {
        this.MoreActionsDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private MoreActionsDialog() {
    Stack() {
      Column({ space: 6 }) {
        Row() {
          Text('更多操作')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.labelPrimary(this.theme))
          Blank()
          Stack() {
            Circle({ width: 28, height: 28 })
              .fill(DesignTokens.mutedFill(this.theme))
            Text('×')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(DesignTokens.labelSecondary(this.theme))
          }
          .onClick(() => {
            this.pressedMoreActionIndex = -1;
            this.showMoreActionsDialog = false;
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 4 })

        this.buildMoreActionRow(0, 5, $r('app.media.ic_pd_playlist'), '添加到歌单', () => this.onMoreActionSelected(0))
        this.buildMoreActionRow(1, 5, $r('app.media.ic_pd_comment'), '查看评论', () => this.onMoreActionSelected(1))
        this.buildMoreActionRow(2, 5, $r('app.media.ic_pd_lyric'), this.currentTab === 0 ? '切换到歌词' : '切换到封面', () => this.onMoreActionSelected(2))
        this.buildMoreActionRow(3, 5, $r('app.media.ic_pd_lyric'), this.showDesktopLyric ? '关闭桌面歌词' : '开启桌面歌词', () => this.onMoreActionSelected(3))
        this.buildMoreActionRow(4, 5, $r('app.media.ic_pd_timer'), '定时退出', () => this.onMoreActionSelected(4))
      }
      .width('84%')
      .padding({ left: 18, right: 18, top: 16, bottom: 14 })
      .backgroundColor(DesignTokens.card(this.theme))
      .borderRadius(22)
      .border({ width: 0.33, color: DesignTokens.cardBorder(this.theme) })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.24)')
    .alignContent(Alignment.Center)
    .onClick(() => {
      this.pressedMoreActionIndex = -1;
      this.showMoreActionsDialog = false;
    })
  }

  @Builder
  private buildMoreActionRow(index: number, total: number, icon: Resource, label: string, onClick: () => void) {
    Column() {
      Row() {
        Row({ space: 8 }) {
          Stack() {
            Circle({ width: 24, height: 24 })
              .fill(DesignTokens.mutedFill(this.theme))
            Image(icon)
              .width(13)
              .height(13)
              .fillColor(
                this.pressedMoreActionIndex === index
                  ? DesignTokens.labelPrimary(this.theme)
                  : DesignTokens.labelSecondary(this.theme)
              )
          }
          Text(label)
            .fontSize(15)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width(176)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height(48)
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .borderRadius(12)
      .backgroundColor(this.pressedMoreActionIndex === index ? DesignTokens.mutedFill(this.theme) : Color.Transparent)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pressedMoreActionIndex = index;
          return;
        }
        this.pressedMoreActionIndex = -1;
      })
      .onClick(onClick)

      if (index < total - 1) {
        Divider()
          .strokeWidth(0.5)
          .color(DesignTokens.cardBorder(this.theme))
          .margin({ left: 6, right: 6 })
      }
    }
    .width('100%')
  }

  @Builder
  NavigationBar() {
    Row() {
      NavBackButton()

      Column() {
        Text(this.musicName || '未播放')
          .fontSize(DesignTokens.fontTitle())
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
        if (this.singer && this.singer.trim().length > 0) {
          Text(this.singer)
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .maxLines(1)
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
      Text('封面')
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .fontSize(DesignTokens.fontBody())
        .fontWeight(this.currentTab === 0 ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentTab === 0 ? DesignTokens.labelPrimary(this.theme) : DesignTokens.labelSecondary(this.theme))
        .padding({ top: 6, bottom: 6 })
        .backgroundColor(this.currentTab === 0 ? DesignTokens.segmentedThumb(this.theme) : Color.Transparent)
        .borderRadius(DesignTokens.radiusSearch())
        .onClick(() => {
          this.switchToCoverTab();
        })
      Text('歌词')
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .fontSize(DesignTokens.fontBody())
        .fontWeight(this.currentTab === 1 ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentTab === 1 ? DesignTokens.labelPrimary(this.theme) : DesignTokens.labelSecondary(this.theme))
        .padding({ top: 6, bottom: 6 })
        .backgroundColor(this.currentTab === 1 ? DesignTokens.segmentedThumb(this.theme) : Color.Transparent)
        .borderRadius(DesignTokens.radiusSearch())
        .onClick(() => {
          this.switchToLyricTab();
        })
    }
    .width(176)
    .padding(2)
    .backgroundColor(DesignTokens.segmentedTrack(this.theme))
    .borderRadius(DesignTokens.radiusSearch())
    .margin({ top: 8, bottom: 10 })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  AlbumArt() {
    Column() {
      if (this.canRenderCover(this.pic)) {
        Image(this.pic)
          .width('82%')
          .aspectRatio(1)
          .borderRadius(20)
          .objectFit(ImageFit.Cover)
          .onError(() => {
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
            // 二次失败后回退到占位图，避免页面出现大片空白区域。
            this.pic = '';
          })
      } else {
        Image($r('app.media.ic_player_cover_placeholder'))
        .width('82%')
        .aspectRatio(1)
        .borderRadius(20)
        .objectFit(ImageFit.Cover)
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
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
          value: this.progress * 100,
          min: 0,
          max: 100,
          style: SliderStyle.OutSet,
        })
          .width('calc(100% - 88vp)')
          .height(24)
          .blockColor(DesignTokens.accent())
          .trackColor(DesignTokens.mutedFill(this.theme))
          .selectedColor(DesignTokens.accent())
          .onChange((value: number) => {
            void this.seekTo(value / 100);
          })
        Text(this.totalTime)
          .fontSize(DesignTokens.fontMicro())
          .fontColor(DesignTokens.labelTertiary(this.theme))
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
              .fillColor('#FFFFFF')
          } else {
            Image($r('app.media.ic_pd_play'))
              .width(20)
              .height(20)
              .fillColor('#FFFFFF')
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
        this.buildMenuButton($r('app.media.ic_pd_playlist'), '添加到歌单', () => void this.addToPlaylist())
        this.buildMenuButton($r('app.media.ic_pd_loop'), this.getPlayModeText(), () => this.togglePlayMode())
        this.buildMenuButton($r('app.media.ic_pd_comment'), '评论', () => this.viewComments())
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
}
