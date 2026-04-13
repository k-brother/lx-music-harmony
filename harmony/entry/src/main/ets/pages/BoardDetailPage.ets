// 排行榜详情页 - 显示榜单信息和歌曲列表
// 支持分组展示前几条歌曲作为预览

import hilog from '@ohos.hilog';
import { PlayerBar } from '../components/player/PlayerBar';
import { getLeaderboardDetail } from '../core/leaderboard';
import type { BoardMusicItem, BoardSource } from '../store/leaderboard/LeaderboardStoreState';
import { playerService, SongInfo } from '../service/PlayerService';
import { getMusicUrl } from '../core/music/MusicFeatureEntry';
import type { MusicInfo } from '../types/MusicTypes';
import { navigationService, NavigationParams } from '../service/NavigationService';

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
  @State boardName: string = '排行榜';
  @State boardId: string = '';
  @State boardSource: string = 'kw';
  @State songList: BoardSongItem[] = [];
  @State isLoading: boolean = true;
  @State totalCount: number = 0;

  // 标记是否已加载数据（用于区分首次加载和参数更新）
  private hasLoadedData: boolean = false;

  aboutToAppear() {
    hilog.info(0x0001, 'BoardDetail', 'BoardDetailPage aboutToAppear');
    // 从 NavigationService 取参（onReady 可能晚于或未触发，此处必须发起加载，否则会一直 isLoading）
    if (!this.hasLoadedData) {
      const params = navigationService.getCurrentParams() as NavigationParams;
      if (params && params.boardId) {
        this.boardId = params.boardId as string;
        this.boardName = (params.boardName as string) || '排行榜';
        this.boardSource = (params.boardSource as string) || 'kw';
        hilog.info(0x0001, 'BoardDetail', 'Loaded params from service - id: %{public}s', this.boardId);
        this.hasLoadedData = true;
        void this.loadBoardDetail();
      }
    }
  }

  onBackPressed(): boolean {
    navigationService.back();
    return true;
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
        this.boardName = (p.boardName as string) || '排行榜';
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
        this.boardName = navParams.boardName || '排行榜';
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

      const result = await getLeaderboardDetail(source, bangId, 1);
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
        this.totalCount = result.total || items.length;
        hilog.info(0x0001, 'BoardDetail', 'Loaded %{public}d songs', items.length);
      }
    } catch (err) {
      hilog.error(0x0001, 'BoardDetail', 'Failed to load: %{public}s', JSON.stringify(err));
      this.songList = [];
    } finally {
      this.isLoading = false;
    }
  }

  // 播放歌曲
  async playSong(index: number): Promise<void> {
    const song = this.songList[index];
    if (!song) return;
    hilog.info(0x0001, 'BoardDetail', 'Playing song: %{public}s, source: %{public}s, id: %{public}s', song.name, song.source, song.id);

    // 更新 UI 播放状态
    for (let i = 0; i < this.songList.length; i++) {
      this.songList[i].isPlaying = (i === index);
    }
    this.songList = this.songList;

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
        quality: '128k',
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
      await playerService.setSource(songInfo, url, song.duration);
      hilog.info(0x0001, 'BoardDetail', 'Source set, starting playback...');
      await playerService.play();
      hilog.info(0x0001, 'BoardDetail', 'Playback started successfully');
    } catch (error) {
      hilog.error(0x0001, 'BoardDetail', 'Play song failed: %{public}s', JSON.stringify(error));
    }
  }

  // 播放全部
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

  build() {
    Column() {
      // 状态栏
      Row()
        .width('100%')
        .height(24)
        .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')

      // 顶部导航栏
      Row() {
        Image($r('sys.symbol.chevron_left'))
          .width(24)
          .height(24)
          .fillColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .onClick(() => {
            navigationService.back();
          })

        Text(this.boardName)
          .fontSize(16)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Blank()

        Text(`共 ${this.totalCount} 首`)
          .fontSize(12)
          .fontColor('#999999')
          .margin({ right: 16 })
      }
      .width('100%')
      .height(44)
      .padding({ left: 12 })

      if (this.isLoading) {
        // 加载中
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
          Text('加载中...')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.songList.length === 0) {
        // 空状态
        Column() {
          Text('暂无歌曲数据')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 歌曲列表
        this.SongList()
      }

      // 播放器栏
      PlayerBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme === 'dark' ? '#121212' : '#FFFFFF')
  }

  @Builder
  SongList() {
    Column() {
      // 播放全部按钮
      Row() {
        Image($r('sys.symbol.play_fill'))
          .width(18)
          .height(18)
          .fillColor('#FFFFFF')
        Text('播放全部')
          .fontSize(14)
          .fontColor('#FFFFFF')
          .margin({ left: 6 })
      }
      .padding({ left: 20, right: 20, top: 8, bottom: 8 })
      .backgroundColor('#E63946')
      .borderRadius(20)
      .margin({ left: 16, top: 12, bottom: 12 })
      .onClick(() => {
        this.playAll();
      })

      // 歌曲列表
      List() {
        ForEach(this.songList, (song: BoardSongItem) => {
          ListItem() {
            Row() {
              // 序号
              Text(song.index.toString())
                .fontSize(12)
                .fontColor(song.isPlaying ? '#E63946' : '#999999')
                .width(32)
                .textAlign(TextAlign.Center)

              // 歌曲信息
              Column() {
                Text(song.name)
                  .fontSize(15)
                  .fontColor(song.isPlaying ? '#E63946' : (this.theme === 'dark' ? '#FFFFFF' : '#333333'))
                  .maxLines(1)
                Text(song.singer)
                  .fontSize(12)
                  .fontColor('#999999')
                  .maxLines(1)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              // 播放中图标
              if (song.isPlaying) {
                Image($r('sys.symbol.play'))
                  .width(20)
                  .height(20)
                  .fillColor('#E63946')
              }

              // 更多按钮
              Image($r('sys.symbol.ellipsis_circle'))
                .width(20)
                .height(20)
                .fillColor('#999999')
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 12, bottom: 12 })
          }
          .onClick(() => {
            const idx = this.songList.indexOf(song);
            if (idx >= 0) {
              this.playSong(idx);
            }
          })
        })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
      .divider({ strokeWidth: 0.5, color: '#F0F0F0', startMargin: 40 })
    }
    .width('100%')
    .height('100%')
  }
}
