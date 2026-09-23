import { t, tf, sourceLabel } from '../service/LocalizationService';
import { showAppToast, TOAST_DURATION_SHORT } from '../utils/Toast';
// 排行榜详情页 - 显示榜单信息和歌曲列表
// 支持分组展示前几条歌曲作为预览

import { hilog } from '@kit.PerformanceAnalysisKit';
import { PlayerBar } from '../components/player/PlayerBar';
import { getLeaderboardDetailReliable } from '../core/leaderboard';
import { playerService, SongInfo } from '../service/PlayerService';
import { getMusicUrl, download } from '../core/music/MusicFeatureEntry';
import type { MusicInfo } from '../types/MusicTypes';
import { navigationService, NavigationParams } from '../service/NavigationService';
import { playKeyOfIds } from '../service/PlayerService';
import { DesignTokens } from '../theme/DesignTokens';
import { NavBar } from '../components/ui/NavBar';
import { StateView } from '../components/ui/StateView';
import { Breakpoints } from '../theme/Breakpoints';
import { LazyDataSource } from '../utils/LazyDataSource';
import { BoardDetailHeader } from './Board/BoardDetailHeader';
import { scrollerOffsetY } from '../utils/ScrollTools';
import { parameterizedPageScrollKey, ScrollMemoryHandle } from '../service/ScrollMemoryService';
import { ListRow } from '../components/ui/ListRow';
import { showSongItemMenu } from './SonglistDetail/SonglistMenus';
import { batchAddToDefaultList } from './SonglistDetail/SonglistActions';
import { songRowToQueueItem } from '../core/list/SongMappers';
import { addRowToDefaultList, addRowToDislike, openInBrowser, shareSongRow, sourceDetailUrl } from './SonglistDetail/SonglistRowActions';
import { emitSearchRequest } from '../service/EventBus';
import { appActionMenu } from '../service/DialogService';
import type { SongItem } from './SonglistDetail/SonglistTypes';
import type { common } from '@kit.AbilityKit';

interface BoardDetailParams {
  boardId: string;
  boardName: string;
  boardSource: string;
}


@Component
export struct BoardDetailPage {
  @StorageProp('theme') theme: string = 'light';
  /** 正在播放的那首的全局 key（源|songmid），列表高亮据此计算 */
  @StorageProp('playingSongKey') playingSongKey: string = '';
  /** 一多：窗口宽度（vp），大屏内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;

  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State boardName: string = t('tab_leaderboard');
  @State boardId: string = '';
  @State boardSource: string = 'kw';
  /** 榜单说明（来源提供才有） */
  @State boardDesc: string = '';
  @State songList: SongItem[] = [];
  /** LazyForEach 数据源：长列表只创建可视区的行 */
  private songListSource: LazyDataSource<SongItem> = new LazyDataSource<SongItem>();
  @State isLoading: boolean = true;
  @State totalCount: number = 0;
  @State headerCompact: boolean = false;
  /** 加载失败（与「空榜单」区分，失败态给重试入口） */
  @State hasError: boolean = false;
  /** 设置 → 列表 → 记住列表滚动位置 */
  @StorageProp('rememberScrollPosition') rememberScrollPosition: boolean = true;

  // 标记是否已加载数据（用于区分首次加载和参数更新）
  private hasLoadedData: boolean = false;
  private songListScroller: Scroller = new Scroller();
  /** 滚动位置记忆（按榜单 id 区分；恢复时机与定时器在把手内部） */
  private scrollMemory: ScrollMemoryHandle = new ScrollMemoryHandle('', this.songListScroller);
  private scrollMemoryRestored: boolean = false;

  private getSongListOffsetY(): number {
    return scrollerOffsetY(this.songListScroller);
  }

  private getBoardCover(): string {
    for (let i = 0; i < this.songList.length; i++) {
      const pic = (this.songList[i].pic ?? '').trim();
      if (pic.length > 0) {
        return pic;
      }
    }
    return '';
  }

  aboutToAppear() {
    hilog.info(0x0001, 'BoardDetail', 'BoardDetailPage aboutToAppear');
    // 从 NavigationService 取参（onReady 可能晚于或未触发，此处必须发起加载，否则会一直 isLoading）
    if (!this.hasLoadedData) {
      const params = navigationService.getCurrentParams() as NavigationParams;
      if (params && params.boardId) {
        this.boardId = params.boardId as string;
        this.boardName = (params.boardName as string) || t('tab_leaderboard');
        this.boardSource = (params.boardSource as string) || 'kw';
        hilog.info(0x0001, 'BoardDetail', 'Loaded params from service - id: %{public}s', this.boardId);
        this.hasLoadedData = true;
        void this.loadBoardDetail();
      }
    }
  }

  // NavDestination onReady callback - 正确获取参数
  onReady(params: Record<string, object | string | number | boolean | undefined>): void {
    hilog.info(0x0001, 'BoardDetail', 'BoardDetailPage onReady with params: %{public}s', JSON.stringify(params));
    
    // 从 onReady 参数中获取数据
    if (params && typeof params === 'object') {
      const p = params as NavigationParams;
      if (p.boardId) {
        const nextId = p.boardId as string;
        const needLoad = !this.hasLoadedData || this.boardId !== nextId;
        this.boardId = nextId;
        this.boardName = (p.boardName as string) || t('tab_leaderboard');
        this.boardSource = (p.boardSource as string) || 'kw';
        this.boardDesc = (p.boardDesc as string) || '';
        hilog.info(0x0001, 'BoardDetail', 'Loaded from onReady - id: %{public}s, name: %{public}s', this.boardId, this.boardName);
        this.hasLoadedData = true;
        if (needLoad) {
          void this.loadBoardDetail();
        }
        return;
      }
    }
    
    // 如果 onReady 没有参数，尝试从 NavigationService 获取
    if (!this.hasLoadedData) {
      const navParams = navigationService.getCurrentParams() as NavigationParams;
      if (navParams && navParams.boardId) {
        this.boardId = navParams.boardId;
        this.boardName = navParams.boardName || t('tab_leaderboard');
        this.boardSource = navParams.boardSource || 'kw';
        this.boardDesc = navParams.boardDesc || '';
        hilog.info(0x0001, 'BoardDetail', 'Loaded from service - id: %{public}s', this.boardId);
        this.loadBoardDetail();
        this.hasLoadedData = true;
        return;
      }
    }
    
    // 如果仍然没有参数但有之前加载的数据，继续使用
    if (this.boardId) {
      this.loadBoardDetail();
    } else {
      hilog.warn(0x0001, 'BoardDetail', 'No boardId found in params');
      this.isLoading = false;
    }
  }

  async loadBoardDetail() {
    this.isLoading = true;
    this.hasError = false;
    // 榜单 id 只能在加载时确定：先把记忆 key 绑到这张榜单（换榜单不会串位置）
    this.scrollMemory.setKey(parameterizedPageScrollKey('board', this.boardId));
    hilog.info(0x0001, 'BoardDetail', 'Loading detail for source: %{public}s, id: %{public}s', this.boardSource, this.boardId);

    try {
      // boardId 规范为 source__bangid；以 boardId 内嵌源为准请求（避免顶部源与列表项不一致时用错 SDK）
      const raw = this.boardId;
      const delim = raw.indexOf('__');
      let source = this.boardSource;
      let bangId = raw;
      if (delim >= 0) {
        source = raw.substring(0, delim);
        bangId = raw.substring(delim + 2);
        if (source !== this.boardSource) {
          hilog.warn(0x0001, 'BoardDetail', 'boardId source %{public}s != boardSource %{public}s, using boardId', source, this.boardSource);
        }
      }

      // 与排行榜 Tab 共用同一套「超时 + 空包重试」，避免个别源偶发空列表直接白屏
      const result = await getLeaderboardDetailReliable(source, bangId, 1);
      if (result && result.list) {
        const items: SongItem[] = [];
        for (let i = 0; i < result.list.length; i++) {
          const item = result.list[i];
          items.push({
            id: item.id,
            name: item.name || '',
            singer: item.singer || '',
            album: item.album || '',
            duration: item.duration || 0,
            pic: item.pic || '',
            source: item.source || source,
            isPlaying: false,
          });
        }
        this.songList = items;
        this.songListSource.reload(this.songList);
        this.totalCount = result.total || items.length;
        this.hasError = false;
        // 数据进列表后：首次进入落回上次位置（下拉/重试不再重复恢复）
        this.scrollMemory.markLoaded();
        if (!this.scrollMemoryRestored) {
          this.scrollMemoryRestored = true;
          this.scrollMemory.restore(this.rememberScrollPosition);
        }
        hilog.info(0x0001, 'BoardDetail', 'Loaded %{public}d songs', items.length);
      }
    } catch (err) {
      hilog.error(0x0001, 'BoardDetail', 'Failed to load: %{public}s', JSON.stringify(err));
      this.songList = [];
      this.songListSource.reload(this.songList);
      // 失败态与空态分开：失败给重试入口，用户不必退回上一页再进来
      this.hasError = true;
    } finally {
      this.isLoading = false;
    }
  }

  // 播放歌曲
  /**
   * 播放榜单中的某一首
   * @param index 下标
   * @param forceWholeList 「播放全部」时强制整列表入队，不受「点击列表项」设置影响
   */
  async playSong(index: number): Promise<void> {
    const song = this.songList[index];
    if (!song) return;
    hilog.info(0x0001, 'BoardDetail', 'Playing song: %{public}s, source: %{public}s, id: %{public}s', song.name, song.source, song.id);


    try {
      const musicInfo: MusicInfo = {
        id: song.id,
        name: song.name,
        singer: song.singer,
        source: song.source as 'kw' | 'kg' | 'tx' | 'wy' | 'mg',
        songmid: song.id,
        interval: this.formatPlayTime(song.duration),
        img: song.pic || null,
        lrc: null,
        albumName: song.album,
        album: song.album,
        types: [],
        _types: new Map(),
        typeUrl: new Map(),
        otherSource: null,
      };

      hilog.info(0x0001, 'BoardDetail', 'Getting music URL...');
      const url: string | null = await getMusicUrl({
        musicInfo: musicInfo,
        isRefresh: false,
        onToggleSource: null,
        allowToggleSource: true,
      });

      hilog.info(0x0001, 'BoardDetail', 'Got URL: %{public}s', url ? url.substring(0, 50) : 'null');
      if (!url || url.length === 0) {
        hilog.error(0x0001, 'BoardDetail', 'Failed to get music URL');
        return;
      }

      const songInfo: SongInfo = {
        id: song.id,
        url: url,
        title: song.name,
        artist: song.singer,
        album: song.album,
        artwork: song.pic || null,
        duration: song.duration,
        source: song.source,
      };

      hilog.info(0x0001, 'BoardDetail', 'Setting player source...');
      hilog.info(0x0001, 'BoardDetail', 'Source set, starting playback...');

      // 队列 = 整个榜单（安卓点击榜单行同样是整列表入队，next/prev 可连续播放）
      playerService.setPlayList(this.buildQueue(), index);
      await playerService.playFromSelection(songInfo, url, song.duration);
      hilog.info(0x0001, 'BoardDetail', 'Playback started successfully');
    } catch (error) {
      hilog.error(0x0001, 'BoardDetail', 'Play song failed: %{public}s', JSON.stringify(error));
    }
  }

  /** 榜单整列表转换为播放队列（url 留空，由播放器按索引取链） */
  private buildQueue(): SongInfo[] {
    const queue: SongInfo[] = [];
    for (let i = 0; i < this.songList.length; i++) {
      const s = this.songList[i];
      queue.push({
        id: s.id,
        url: '',
        title: s.name,
        artist: s.singer,
        album: s.album,
        artwork: s.pic || null,
        duration: s.duration,
        source: s.source,
      });
    }
    return queue;
  }

  // 播放全部：始终按整个榜单入队（从第一首开始）
  async playAll(): Promise<void> {
    if (this.songList.length === 0) return;
    hilog.info(0x0001, 'BoardDetail', 'Play all songs from index 0');
    await this.playSong(0);
  }

  // 格式化播放时间
  formatPlayTime(seconds: number): string {
    if (isNaN(seconds) || seconds < 0) return '00:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }

  private showToast(message: string): void {
    showAppToast(this.getUIContext(), message, TOAST_DURATION_SHORT);
  }

  private buildMusicInfoForDownload(song: SongItem): MusicInfo {
    return {
      id: song.id,
      name: song.name,
      singer: song.singer,
      source: song.source as 'kw' | 'kg' | 'tx' | 'wy' | 'mg',
      songmid: song.id,
      interval: this.formatPlayTime(song.duration),
      img: song.pic || null,
      lrc: null,
      album: song.album,
      albumName: song.album,
      types: [],
      _types: new Map(),
      typeUrl: new Map(),
      otherSource: null,
    };
  }

  private async downloadSong(song: SongItem): Promise<void> {
    try {
      // 与歌单详情页一致，统一走下载服务（下载页可见、可暂停/恢复）
      const taskId: string = await download.startDownload({
        musicInfo: this.buildMusicInfoForDownload(song),
      });
      hilog.info(0x0001, 'BoardDetail', 'Download started: %{public}s, taskId: %{public}s', song.name, taskId);
      this.showToast(`${t('download_title')}: ${song.name}`);
    } catch (err) {
      hilog.error(0x0001, 'BoardDetail', 'downloadSong failed: %{public}s', JSON.stringify(err));
      this.showToast(t('media_save_fail'));
    }
  }

  /** 行尾 ⋯ 菜单按钮（与歌单详情同一套观感） */
  @Builder
  SongRowTrailing(song: SongItem) {
    Stack() {
      Circle({ width: 30, height: 30 })
        .fill(DesignTokens.mutedFill(this.theme))
      Image($r('app.media.ic_pd_more'))
        .width(14)
        .height(14)
        .fillColor(DesignTokens.labelSecondary(this.theme))
    }
    .width(DesignTokens.touchTarget())
    .height(DesignTokens.touchTarget())
    .accessibilityText(t('a11y_more'))
    .onClick(() => {
      void this.openSongMenu(song);
    })
  }

  /**
   * 单曲菜单：动作集合与歌单详情完全一致（下一首播放/添加到列表/下载/分享/不喜欢/
   * 来源详情/查看歌手/查看专辑），榜单是只读的，所以没有「调整位置/移动到列表」。
   */
  private async openSongMenu(song: SongItem): Promise<void> {
    await showSongItemMenu(song, {
      onPlayLater: (target: SongItem): void => {
        playerService.insertNext(songRowToQueueItem(target));
        this.showToast(tf('toast_play_later_added', [target.name]));
      },
      onAddToList: (target: SongItem): void => {
        void this.addToPlaylist(target);
      },
      onDownload: (target: SongItem): void => {
        void this.downloadSong(target);
      },
      onShare: (target: SongItem): void => {
        void this.shareSong(target);
      },
      onDislike: (target: SongItem): void => {
        void this.showDislikeMenu(target);
      },
      onSourceDetail: (target: SongItem): void => {
        const url: string = sourceDetailUrl(target);
        if (!openInBrowser(this.hostContext(), url)) {
          this.showToast(t('toast_operation_failed'));
        }
      },
      onViewArtist: (target: SongItem): void => {
        this.viewByKeyword(target.singer);
      },
      onViewAlbum: (target: SongItem): void => {
        this.viewByKeyword(target.album);
      },
    }, { canEditPosition: false, canMoveToList: false });
  }

  /** 收藏到默认列表（与歌单详情同一入口） */
  private async addToPlaylist(song: SongItem): Promise<void> {
    const error = await addRowToDefaultList(song);
    this.showToast(error.length === 0
      ? tf('toast_added_to_default', [song.name])
      : t('toast_add_to_list_failed') + ': ' + error);
  }

  /** 分享（按「设置 → 分享方式」走系统分享，失败回退剪贴板） */
  private async shareSong(song: SongItem): Promise<void> {
    const result = await shareSongRow(this.hostContext(), song, sourceLabel(song.source));
    if (result === 'clipboard') {
      this.showToast(t('toast_share_copy'));
    } else if (result === 'failed') {
      this.showToast(t('toast_operation_failed'));
    }
  }

  /** 不喜欢：歌曲 / 歌手 / 歌名三种粒度（与歌单详情、播放页同一套规则） */
  private async showDislikeMenu(song: SongItem): Promise<void> {
    const picked = await appActionMenu(t('dislike_title'), [
      t('dislike_song'),
      t('dislike_singer'),
      t('dislike_name'),
    ]);
    if (picked < 0) {
      return;
    }
    try {
      const count = await addRowToDislike(song, picked);
      this.showToast(tf('dislike_added', [count.toString()]));
    } catch (err) {
      hilog.warn(0x0001, 'BoardDetail', 'addDislike failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_operation_failed'));
    }
  }

  /** 按关键词回首页搜索（查看歌手 / 查看专辑） */
  private viewByKeyword(keyword: string): void {
    if (!keyword || keyword.length === 0) {
      this.showToast(t('toast_operation_failed'));
      return;
    }
    emitSearchRequest(keyword);
    navigationService.back();
  }

  /** 宿主 Ability 上下文（分享 / 打开外链共用） */
  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 收藏整个榜单：加到「我的列表」（默认列表），位置遵循「设置 → 列表 → 添加位置」 */
  private async collectBoard(): Promise<void> {
    if (this.songList.length === 0) {
      this.showToast(t('list_empty'));
      return;
    }
    try {
      const added: number = await batchAddToDefaultList(this.songList, (message: string): void => {
        this.showToast(message);
      });
      this.showToast(tf('toast_added_to_default', [tf('count_songs', [added.toString()])]));
    } catch (err) {
      hilog.warn(0x0001, 'BoardDetail', 'collectBoard failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_add_to_list_failed'));
    }
  }

  /** 顶栏右侧：曲目总数 */
  @Builder
  NavTrailingCount() {
    Text(tf('count_songs', [this.totalCount.toString()]))
      .fontSize(DesignTokens.fontCaption())
      .fontColor(DesignTokens.labelSecondary(this.theme))
      .margin({ right: 4 })
  }

  build() {
    Column() {
      // 统一顶部栏；曲目数作为右侧动作区展示
      NavBar({
        title: this.boardName,
        trailing: (): void => {
          this.NavTrailingCount();
        },
      })

      if (this.isLoading) {
        // 加载/空态统一走 StateView（与其它列表页同一套）
        StateView({ state: 'loading' })
          .width('100%')
          .layoutWeight(1)
      } else if (this.hasError) {
        // 失败与「真的没有数据」必须分开：失败给明确文案 + 重试入口（此前都落进空态）
        StateView({
          state: 'error',
          message: t('load_failed_hint'),
          actionText: t('retry'),
          onAction: (): void => {
            void this.loadBoardDetail();
          },
        })
          .width('100%')
          .layoutWeight(1)
      } else if (this.songList.length === 0) {
        StateView({ state: 'empty', iconRes: $r('sys.symbol.music_note_list'), message: t('no_data') })
          .width('100%')
          .layoutWeight(1)
      } else {
        BoardDetailHeader({
          title: this.boardName,
          sourceLabel: sourceLabel(this.boardSource),
          description: this.boardDesc,
          cover: this.getBoardCover(),
          sourceTag: this.boardSource,
          songCount: this.totalCount,
          compact: this.headerCompact,
          onPlayAll: (): void => {
            void this.playAll();
          },
          onCollect: (): void => {
            void this.collectBoard();
          },
        })
        this.SongList()
      }

      // 播放器栏（组件内部处理底部沉浸）
      PlayerBar({ immersiveBottom: true })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  SongList() {
    List({ space: 8, scroller: this.songListScroller }) {
      // 行组件与歌单详情同款观感（序号 / 歌名 / 歌手 / 下载 / 播放高亮）
      LazyForEach(this.songListSource, (song: SongItem, index: number) => {
        ListItem() {
          // 与歌单详情完全同一套行：序号 / 歌名 / 歌手·专辑·音源 / 时长 / 行尾 ⋯ 菜单
          Column() {
            ListRow({
              index: index + 1,
              title: song.name,
              singer: song.singer,
              album: song.album,
              sourceId: song.source,
              durationSeconds: song.duration,
              active: playKeyOfIds(song.source, song.id, song.id) === this.playingSongKey,
              divider: index < this.songList.length - 1,
              onTap: (): void => {
                void this.playSong(index);
              },
              onLongPress: (): void => {
                void this.openSongMenu(song);
              },
              trailing: (): void => {
                this.SongRowTrailing(song);
              },
            })
          }
          .padding({ left: 12, right: 8 })
          .width('100%')
        }
      },
        // 高亮改由 @StorageProp('playingSongKey') 驱动，key 不再需要带播放态
        (song: SongItem, index: number): string => `${song.id}_${index}`)
    }
    .width('100%')
    .layoutWeight(1)
    // 大屏内容列居中（平板/PC 上歌曲行不拉满整屏）
    .cachedCount(6)
    .padding({
      left: 12 + Breakpoints.contentInset(this.windowWidthVp),
      right: 12 + Breakpoints.contentInset(this.windowWidthVp),
      bottom: 8,
    })
    .edgeEffect(EdgeEffect.None)
    .onDidScroll(() => {
      const y = this.getSongListOffsetY();
      if (y > 18 && !this.headerCompact) {
        this.headerCompact = true;
      } else if (y <= 4 && this.headerCompact) {
        this.headerCompact = false;
      }
    })
  }

  aboutToDisappear(): void {
    // 离开榜单时记住位置（关闭「记住滚动位置」时写入会被内部忽略）
    this.scrollMemory.save(this.rememberScrollPosition);
    this.scrollMemory.dispose();
  }
}
