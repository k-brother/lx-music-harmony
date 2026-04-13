// 播放详情页 - 对应 src/screens/PlayDetail/Vertical/index.tsx
// 包含封面图片、歌词和播放控制

// 导入播放器服务
import hilog from '@ohos.hilog';
import { playerService, MusicInfo, ProgressInfo } from '../service/PlayerService';
import { navigationService, RouteName, NavigationParams } from '../service/NavigationService';
import { getUserList, LIST_IDS, addMusicToList, MusicItem } from '../service/ListService';
import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { LyricView } from '../components/common/LyricView';

const DOMAIN: number = 0x0001;
const TAG: string = 'PlayDetailPage';

interface PlaylistOptionRow {
  id: string;
  name: string;
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
  @State lyricLines: string[] = ['请在歌单或排行榜中选择歌曲播放'];
  @State currentLyricIndex: number = -1;
  @State isDarkTheme: boolean = false;
  @State playMode: string = 'listLoop'; // 播放模式: listLoop, singleLoop, random, sequential
  @State showDesktopLyric: boolean = false;
  @State timeoutExitEnabled: boolean = false;

  private unsubscribePlayState: (() => void) | null = null;
  private unsubscribeMusicInfo: (() => void) | null = null;
  private unsubscribeProgress: (() => void) | null = null;

  aboutToAppear() {
    // 设置主题
    this.isDarkTheme = this.theme === 'dark';
    
    // 获取当前播放器状态
    const currentMusicInfo = playerService.getCurrentMusicInfo();
    if (currentMusicInfo && currentMusicInfo.name) {
      this.musicName = currentMusicInfo.name;
      this.singer = currentMusicInfo.singer;
      this.album = currentMusicInfo.album ?? '';
      // 确保 pic 不为空字符串
      const picUrl = currentMusicInfo.pic ?? currentMusicInfo.img ?? '';
      this.pic = picUrl && picUrl.trim().length > 0 ? picUrl : '';
    } else {
      this.lyricLines = ['当前没有正在播放的歌曲'];
    }

    // 获取当前播放进度
    const progressData = playerService.getProgress();
    this.progress = progressData.progress;
    this.currentTime = progressData.nowPlayTimeStr;
    this.totalTime = progressData.maxPlayTimeStr;

    // 获取当前播放状态
    const isPlay = playerService.isPlaying();
    this.isPlaying = isPlay;

    // 加载播放设置
    this.loadPlaySettings();

    // 订阅播放器状态变化
    this.unsubscribePlayState = playerService.onPlayStateChange((isPlay: boolean) => {
      this.isPlaying = isPlay;
    });

    this.unsubscribeMusicInfo = playerService.onMusicInfoChange((info: MusicInfo) => {
      this.musicName = info.name;
      this.singer = info.singer;
      this.album = info.album ?? '';
      // 确保 pic 不为空字符串
      const picUrl = info.pic ?? info.img ?? '';
      this.pic = picUrl && picUrl.trim().length > 0 ? picUrl : '';
      hilog.info(DOMAIN, TAG, 'Music info updated, pic=%{public}s', this.pic.substring(0, 50));
    });

    this.unsubscribeProgress = playerService.onProgressInfoChange((prog: ProgressInfo) => {
      this.progress = prog.progress;
      this.currentTime = prog.nowPlayTimeStr;
      this.totalTime = prog.maxPlayTimeStr;
    });
  }

  aboutToDisappear() {
    if (this.unsubscribePlayState) this.unsubscribePlayState();
    if (this.unsubscribeMusicInfo) this.unsubscribeMusicInfo();
    if (this.unsubscribeProgress) this.unsubscribeProgress();
  }

  onBackPressed(): boolean {
    navigationService.back();
    return true;
  }

  // NavDestination onReady callback
  onReady(params: Record<string, object | string | number | boolean | undefined>): void {
    hilog.info(DOMAIN, TAG, 'PlayDetailPage onReady with params: %{public}s', JSON.stringify(params));
  }

  async loadPlaySettings() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'music_settings');
      
      this.playMode = await pref.get('playMode', 'listLoop') as string;
      this.showDesktopLyric = await pref.get('showDesktopLyric', false) as boolean;
      this.timeoutExitEnabled = await pref.get('timeoutExit', false) as boolean;
      
      hilog.info(DOMAIN, TAG, 'Play settings loaded');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to load play settings: %{public}s', JSON.stringify(err));
    }
  }

  async savePlaySettings() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'music_settings');
      
      await pref.put('playMode', this.playMode);
      await pref.put('showDesktopLyric', this.showDesktopLyric);
      await pref.put('timeoutExit', this.timeoutExitEnabled);
      
      await pref.flush();
      hilog.info(DOMAIN, TAG, 'Play settings saved');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save play settings: %{public}s', JSON.stringify(err));
    }
  }

  // 切换播放模式
  togglePlayMode(): void {
    const modes = ['listLoop', 'singleLoop', 'random', 'sequential'];
    const currentIndex = modes.indexOf(this.playMode);
    const nextIndex = (currentIndex + 1) % modes.length;
    this.playMode = modes[nextIndex];
    this.savePlaySettings();
    
    // 这里可以调用播放器服务设置播放模式
    hilog.info(DOMAIN, TAG, 'Play mode changed to: %{public}s', this.playMode);
  }

  // 切换桌面歌词显示
  toggleDesktopLyric(): void {
    this.showDesktopLyric = !this.showDesktopLyric;
    this.savePlaySettings();
    hilog.info(DOMAIN, TAG, 'Desktop lyric: %{public}s', this.showDesktopLyric ? 'enabled' : 'disabled');
  }

  // 切换定时退出
  toggleTimeoutExit(): void {
    this.timeoutExitEnabled = !this.timeoutExitEnabled;
    this.savePlaySettings();
    hilog.info(DOMAIN, TAG, 'Timeout exit: %{public}s', this.timeoutExitEnabled ? 'enabled' : 'disabled');
  }

  // 添加到歌单
  async addToPlaylist(): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, 'Add to playlist clicked');
      
      // 获取当前播放的歌曲信息
      const currentMusicInfo = playerService.getCurrentMusicInfo();
      if (!currentMusicInfo || !currentMusicInfo.name) {
        this.showToast('当前没有正在播放的歌曲');
        return;
      }
      
      // 显示歌单选择对话框
      const selectedListId = await this.showPlaylistSelector();
      if (!selectedListId) {
        this.showToast('已取消添加');
        return;
      }
      
      // 添加到选中的歌单
      await this.addMusicToSelectedList(currentMusicInfo, selectedListId);
      
      this.showToast(`已添加到歌单: ${currentMusicInfo.name}`);
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to add to playlist: %{public}s', errorMsg);
      this.showToast('添加到歌单失败: ' + errorMsg);
    }
  }

  // 显示歌单选择器
  private async showPlaylistSelector(): Promise<string | null> {
    try {
      const playlistOptions: PlaylistOptionRow[] = [];
      playlistOptions.push({ id: LIST_IDS.DEFAULT, name: '默认列表' });
      playlistOptions.push({ id: LIST_IDS.LOVE, name: '我喜欢' });
      const userLists = getUserList();
      for (let i = 0; i < userLists.length; i++) {
        const list = userLists[i];
        playlistOptions.push({ id: list.id, name: list.name });
      }
      
      // 在实际应用中，这里应该显示一个选择对话框
      // 暂时选择第一个歌单作为示例
      if (playlistOptions.length > 0) {
        hilog.info(DOMAIN, TAG, 'Selected playlist: %{public}s', playlistOptions[0].name);
        return playlistOptions[0].id;
      }
      
      return null;
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to show playlist selector: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  // 添加音乐到选中的歌单
  private async addMusicToSelectedList(musicInfo: MusicInfo, listId: string): Promise<void> {
    try {
      const cover = musicInfo.pic ?? musicInfo.img ?? '';
      const musicItem: MusicItem = {
        id: musicInfo.id || '',
        name: musicInfo.name,
        singer: musicInfo.singer,
        album: musicInfo.album ?? '',
        albumId: null,
        duration: 0,
        source: musicInfo.source,
        pic: cover,
        lrc: null
      };
      
      await addMusicToList(listId, musicItem);
      
      hilog.info(DOMAIN, TAG, 'Added music to playlist %{public}s: %{public}s', listId, musicInfo.name);
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to add music to playlist: %{public}s', JSON.stringify(err));
      const msg = err instanceof Error ? err.message : JSON.stringify(err);
      throw new Error(msg);
    }
  }

  // 显示提示
  private showToast(message: string): void {
    // 在实际应用中，这里应该显示一个Toast提示
    // 暂时使用日志输出
    hilog.info(DOMAIN, TAG, 'Toast: %{public}s', message);
  }

  // 查看评论
  async viewComments(): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, 'View comments clicked');
      
      // 获取当前播放的歌曲信息
      const currentMusicInfo = playerService.getCurrentMusicInfo();
      if (!currentMusicInfo || !currentMusicInfo.name) {
        this.showToast('当前没有正在播放的歌曲');
        return;
      }
      
      // 检查是否有评论页面
      const hasCommentPage = await this.checkCommentPageAvailable();
      if (!hasCommentPage) {
        this.showToast('评论功能暂不可用');
        return;
      }
      
      // 跳转到评论页面
      await this.navigateToCommentPage(currentMusicInfo);
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to view comments: %{public}s', errorMsg);
      this.showToast('查看评论失败: ' + errorMsg);
    }
  }

  // 检查评论页面是否可用
  private async checkCommentPageAvailable(): Promise<boolean> {
    try {
      // 在实际应用中，这里应该检查评论页面是否已实现
      // 暂时返回true（假设评论页面可用）
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to check comment page availability: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  // 跳转到评论页面
  private async navigateToCommentPage(musicInfo: MusicInfo): Promise<void> {
    try {
      const rawPic = musicInfo.pic ?? musicInfo.img;
      let musicPic: string | undefined = undefined;
      if (rawPic !== null && rawPic !== undefined && rawPic.length > 0) {
        musicPic = rawPic;
      }
      const params: NavigationParams = {
        musicId: musicInfo.id,
        musicName: musicInfo.name,
        musicSinger: musicInfo.singer,
        musicAlbum: musicInfo.album ?? undefined,
        musicPic: musicPic,
        musicSource: musicInfo.source || 'kw',
        commentType: 'hot'
      };
      
      hilog.info(DOMAIN, TAG, 'Navigating to comment page with params: %{public}s', JSON.stringify(params));
      
      this.showToast(`正在跳转到评论: ${musicInfo.name}`);
      
      navigationService.navigateTo(RouteName.COMMENT, params);
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to navigate to comment page: %{public}s', JSON.stringify(err));
      const msg = err instanceof Error ? err.message : JSON.stringify(err);
      throw new Error(msg);
    }
  }

  // 播放/暂停
  async togglePlay(): Promise<void> {
    if (this.isPlaying) {
      await playerService.pause();
    } else {
      await playerService.play();
    }
  }

  // 上一曲
  async playPrev(): Promise<void> {
    await playerService.playPrev();
  }

  // 下一曲
  async playNext(): Promise<void> {
    await playerService.playNext();
  }

  // 跳转播放
  async seekTo(progress: number) {
    const progressData = playerService.getProgress();
    const duration = progressData.maxPlayTime;
    await playerService.seekTo(duration * progress);
  }

  build() {
    Column() {
      // 状态栏
      Row()
        .width('100%')
        .height(24)
        .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')

      // 顶部导航栏
      this.NavigationBar()

      // Tab 切换指示器
      Row() {
        Row()
          .width(40)
          .height(2)
          .backgroundColor(this.currentTab === 0 ? '#E63946' : '#E0E0E0')
          .borderRadius(1)
          .onClick(() => {
            this.currentTab = 0;
          })
        Row()
          .width(40)
          .height(2)
          .backgroundColor(this.currentTab === 1 ? '#E63946' : '#E0E0E0')
          .borderRadius(1)
          .margin({ left: 40 })
          .onClick(() => {
            this.currentTab = 1;
          })
      }
      .margin({ top: 8 })
      .justifyContent(FlexAlign.Center)

      // 内容区（支持左右滑动切换）
      Stack() {
        if (this.currentTab === 0) {
          this.AlbumArt()
        } else {
          LyricView({
            lyricLines: this.lyricLines,
            currentLyricIndex: this.currentLyricIndex
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          PanGesture({ direction: PanDirection.Horizontal, distance: 50 })
            .onActionEnd((event: GestureEvent) => {
              if (event.offsetX < 0) {
                // 左滑 -> 切换到歌词
                this.currentTab = 1;
                hilog.info(DOMAIN, TAG, 'Swiped left, switch to lyric');
              } else if (event.offsetX > 0) {
                // 右滑 -> 切换到封面
                this.currentTab = 0;
                hilog.info(DOMAIN, TAG, 'Swiped right, switch to cover');
              }
            })
        )
      )

      // 播放控制区
      this.PlayerControls()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme === 'dark' ? '#121212' : '#FFFFFF')
  }

  @Builder
  NavigationBar() {
    Row() {
      // 返回按钮
      Image($r('sys.symbol.chevron_left'))
        .width(24)
        .height(24)
        .fillColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
        .onClick(() => {
          navigationService.back();
        })

      Blank()

      // 歌曲信息
      Column() {
        Text(this.musicName || '未播放')
          .fontSize(16)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
        Text(this.singer || '-')
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(1)
      }

      Blank()

      // 更多按钮
      Image($r('sys.symbol.ellipsis_circle'))
        .width(24)
        .height(24)
        .fillColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  AlbumArt() {
    Column() {
      // 封面图片
      if (this.pic && this.pic.trim().length > 0) {
        Image(this.pic)
          .width('80%')
          .aspectRatio(1)
          .borderRadius(12)
          .objectFit(ImageFit.Cover)
          .onError(() => {
            hilog.warn(DOMAIN, TAG, 'Failed to load album art: %{public}s', this.pic);
            this.pic = '';
          })
      } else {
        Column() {
          Text('🎵')
            .fontSize(80)
            .fontColor(this.theme === 'dark' ? '#666666' : '#999999')
        }
        .width('80%')
        .aspectRatio(1)
        .backgroundColor(this.theme === 'dark' ? '#2C2C2C' : '#E8E8E8')
        .borderRadius(12)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .layoutWeight(1)
  }

  @Builder
  PlayerControls() {
    Column() {
      // 进度条
      Row() {
        Text(this.currentTime)
          .fontSize(10)
          .fontColor('#999999')
          .width(40)
          .textAlign(TextAlign.Center)

        Slider({
          value: this.progress * 100,
          min: 0,
          max: 100,
          style: SliderStyle.OutSet
        })
          .width('calc(100% - 80vp)')
          .height(24)
          .blockColor('#E63946')
          .trackColor('#E0E0E0')
          .selectedColor('#E63946')
          .onChange((value: number) => {
            this.seekTo(value / 100);
          })

        Text(this.totalTime)
          .fontSize(10)
          .fontColor('#999999')
          .width(40)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })

      // 播放按钮
      Row() {
        Blank()
        // 上一曲
        Image($r('sys.symbol.backward_end_fill'))
          .width(48)
          .height(48)
          .fillColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .onClick(() => {
            this.playPrev();
          })

        // 播放/暂停
        Image(this.isPlaying ? $r('sys.symbol.pause') : $r('sys.symbol.play'))
          .width(64)
          .height(64)
          .fillColor('#E63946')
          .onClick(() => {
            this.togglePlay();
          })

        // 下一曲
        Image($r('sys.symbol.forward_end_fill'))
          .width(48)
          .height(48)
          .fillColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .onClick(() => {
            this.playNext();
          })
        Blank()
      }
      .width('100%')
      .height(80)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      // 更多控制按钮
      Row() {
        // 桌面歌词按钮
        this.buildControlButton(
          this.getDesktopLyricIcon(),
          '桌面歌词',
          () => this.toggleDesktopLyric()
        )

        // 添加到歌单按钮
        this.buildControlButton(
          $r('sys.symbol.plus'),
          '添加到歌单',
          () => this.addToPlaylist()
        )

        // 播放模式按钮
        this.buildControlButton(
          this.getPlayModeIcon(),
          this.getPlayModeText(),
          () => this.togglePlayMode()
        )

        // 评论按钮
        this.buildControlButton(
          $r('sys.symbol.message'),
          '评论',
          () => this.viewComments()
        )

        // 定时退出按钮
        this.buildControlButton(
          $r('sys.symbol.clock'),
          '定时退出',
          () => this.toggleTimeoutExit()
        )
      }
      .width('100%')
      .height(60)
      .justifyContent(FlexAlign.SpaceAround)
      .alignItems(VerticalAlign.Center)
      .padding({ top: 10 })
    }
    .width('100%')
    .padding({ bottom: 20 })
  }

  @Builder
  buildControlButton(icon: Resource, label: string, onClick: () => void) {
    Column() {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
        .onClick(onClick)
      Text(label)
        .fontSize(10)
        .fontColor(this.theme === 'dark' ? '#AAAAAA' : '#666666')
        .margin({ top: 4 })
    }
    .width(60)
    .height(60)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private getPlayModeIcon(): Resource {
    switch (this.playMode) {
      case 'listLoop': return $r('sys.symbol.repeat');
      case 'singleLoop': return $r('sys.symbol.repeat_1');
      case 'random': return $r('sys.symbol.shuffle');
      case 'sequential': return $r('sys.symbol.arrow_right');
      default: return $r('sys.symbol.repeat');
    }
  }

  private getDesktopLyricIcon(): Resource {
    return $r('sys.symbol.textformat');
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
}


