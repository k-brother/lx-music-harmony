import { t , tf } from '../service/LocalizationService';
import { showAppToast, TOAST_DURATION_SHORT } from '../utils/Toast';
import { BoardSongRow } from './BoardDetail/BoardSongRow';
// 排行榜详情页 - 显示榜单信息和歌曲列表
// 支持分组展示前几条歌曲作为预览

import hilog from '@ohos.hilog';
import { PlayerBar } from '../components/player/PlayerBar';
import { getLeaderboardDetailReliable } from '../core/leaderboard';
import { playerService, SongInfo } from '../service/PlayerService';
import { getMusicUrl, download } from '../core/music/MusicFeatureEntry';
import type { MusicInfo } from '../types/MusicTypes';
import { navigationService, NavigationParams } from '../service/NavigationService';
import { DesignTokens } from '../theme/DesignTokens';
import { NavBar } from '../components/ui/NavBar';
import { StateView } from '../components/ui/StateView';
import { Breakpoints } from '../theme/Breakpoints';
import { LazyDataSource } from '../utils/LazyDataSource';
import { BoardDetailHeader } from './Board/BoardDetailHeader';
import { scrollerOffsetY } from '../utils/ScrollTools';

interface BoardDetailParams {
  boardId: string;
  boardName: string;
  boardSource: string;
}

// 榜单歌曲项
interface BoardSongItem {
  id: string;
  name: string;
  singer: string;
  album: string;
  duration: number;
  pic: string;
  source: string;
  index: number;
  isPlaying: boolean;
}

@Component
export struct BoardDetailPage {
  @StorageProp('theme') theme: string = 'light';
  /** 一多：窗口宽度（vp），大屏内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;

  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State boardName: string = t('tab_leaderboard');
  @State boardId: string = '';
  @State boardSource: string = 'kw';
  @State songList: BoardSongItem[] = [];
  /** LazyForEach 数据源：长列表只创建可视区的行 */
  private songListSource: LazyDataSource<BoardSongItem> = new LazyDataSource<BoardSongItem>();
  @State isLoading: boolean = true;
  @State totalCount: number = 0;
  @State headerCompact: boolean = false;

  // 标记是否已加载数据（用于区分首次加载和参数更新）
  private hasLoadedData: boolean = false;
  private songListScroller: Scroller = new Scroller();

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
        const items: BoardSongItem[] = [];
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
            index: i + 1,
            isPlaying: false,
          });
        }
        this.songList = items;
        this.songListSource.reload(this.songList);
        this.totalCount = result.total || items.length;
        hilog.info(0x0001, 'BoardDetail', 'Loaded %{public}d songs', items.length);
      }
    } catch (err) {
      hilog.error(0x0001, 'BoardDetail', 'Failed to load: %{public}s', JSON.stringify(err));
      this.songList = [];
      this.songListSource.reload(this.songList);
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

    // 更新 UI 播放状态
    for (let i = 0; i < this.songList.length; i++) {
      this.songList[i].isPlaying = (i === index);
    }
    this.songListSource.reload(this.songList);

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

  private buildMusicInfoForDownload(song: BoardSongItem): MusicInfo {
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

  private async downloadSong(song: BoardSongItem): Promise<void> {
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
      } else if (this.songList.length === 0) {
        StateView({ state: 'empty', iconRes: $r('sys.symbol.music_note_list'), message: t('no_data') })
          .width('100%')
          .layoutWeight(1)
      } else {
        BoardDetailHeader({
          cover: this.getBoardCover(),
          sourceTag: this.boardSource,
          songCount: this.totalCount,
          compact: this.headerCompact,
          onPlayAll: (): void => {
            void this.playAll();
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
      LazyForEach(this.songListSource, (song: BoardSongItem, index: number) => {
        ListItem() {
          BoardSongRow({
            index: index + 1,
            title: song.name,
            singer: song.singer,
            active: song.isPlaying,
            divider: index < this.songList.length - 1,
            onTap: (): void => {
              this.playSong(index);
            },
            onDownload: (): void => {
              void this.downloadSong(song);
            },
          })
        }
      },
        // key 带上播放态：状态变化时确保行重建（否则高亮可能不刷新）
        (song: BoardSongItem, index: number): string => `${song.id}_${index}_${song.isPlaying}`)
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
}
