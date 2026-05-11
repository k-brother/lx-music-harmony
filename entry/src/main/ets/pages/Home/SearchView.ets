// Search 视图 - 对应 src/screens/Home/Views/Search/index.tsx
// 搜索功能视图（不含顶部搜索框和源切换，由 HomePage 提供）

import { MusicSource } from '../../core/music/MusicFeatureEntry';
import { SongInfo, playerService } from '../../service/PlayerService';
import { navigationService, RouteName } from '../../service/NavigationService';
import { getHotSearch as getHotSearchApi, searchMusic as searchMusicApi } from '../../core/search/search';
import type { HotSearchItem, MusicSearchResult } from '../../core/search/search';
import { getMusicUrl } from '../../core/music/MusicFeatureEntry';
import type { MusicInfo } from '../../types/MusicTypes';
import hilog from '@ohos.hilog';
import { PersistentStorage } from '@kit.ArkData';

const TAG = 'SearchView';
const DOMAIN = 0x0001;

@Component
export struct SearchView {
  // 从 HomePage 接收的属性
  @Prop sourceId: string = 'kw';
  @Prop searchText: string = '';

  @State isSearching: boolean = false;
  @State searchHistory: string[] = [];
  @State searchResults: MusicSearchResult[] = [];

  // 热搜数据（按音乐源分类）
  private hotSearchCache: Map<string, HotSearchItem[]> = new Map();
  @State currentHotSource: string = 'kw';
  @State hotSearchList: HotSearchItem[] = [];

  // 支持的音乐源
  private sources: string[] = ['kw', 'tx', 'wy', 'kg', 'mg'];

  @StorageProp('theme') theme: string = 'light';

  // 搜索词变化时触发搜索
  aboutToAppear() {
    this.loadSearchHistory();
    this.loadHotSearchForAllSources();
    this.hotSearchList = this.hotSearchCache.get(this.currentHotSource) || [];
  }

  loadSearchHistory(): void {
    try {
      const historyStr = PersistentStorage.getSync('search_history', '[]');
      this.searchHistory = JSON.parse(historyStr);
      hilog.info(DOMAIN, TAG, 'Loaded search history: %{public}d items', this.searchHistory.length);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load search history: %{public}s', JSON.stringify(error));
      this.searchHistory = [];
    }
  }

  // 为所有音乐源加载热搜
  async loadHotSearchForAllSources(): Promise<void> {
    for (const source of this.sources) {
      try {
        const hotSearch = await getHotSearchApi(source);
        if (hotSearch && hotSearch.length > 0) {
          this.hotSearchCache.set(source, hotSearch);
        } else {
          // 使用默认热搜
          this.hotSearchCache.set(source, this.getDefaultHotSearch(source));
        }
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'Failed to load hot search for %{public}s: %{public}s', source, JSON.stringify(error));
        this.hotSearchCache.set(source, this.getDefaultHotSearch(source));
      }
    }
    this.hotSearchList = this.hotSearchCache.get(this.currentHotSource) || [];
  }

  // 加载指定源的热搜
  async loadHotSearch(source: string): Promise<void> {
    try {
      const hotSearch = await getHotSearchApi(source);
      if (hotSearch && hotSearch.length > 0) {
        this.hotSearchCache.set(source, hotSearch);
      } else {
        this.hotSearchCache.set(source, this.getDefaultHotSearch(source));
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load hot search for %{public}s', source);
      this.hotSearchCache.set(source, this.getDefaultHotSearch(source));
    }
    this.hotSearchList = this.hotSearchCache.get(this.currentHotSource) || [];
  }

  // 默认热搜数据（降级方案）
  getDefaultHotSearch(source: string): HotSearchItem[] {
    hilog.warn(DOMAIN, TAG, 'Using default hot search for source: %{public}s', source);
    return [
      { index: 1, title: '周杰伦', source: source as MusicSource, url: '', hot: 1000000 },
      { index: 2, title: '林俊杰', source: source as MusicSource, url: '', hot: 800000 },
      { index: 3, title: '邓紫棋', source: source as MusicSource, url: '', hot: 700000 },
      { index: 4, title: '薛之谦', source: source as MusicSource, url: '', hot: 600000 },
      { index: 5, title: '陈奕迅', source: source as MusicSource, url: '', hot: 500000 },
    ];
  }

  async handleSearch(text: string): Promise<void> {
    if (!text || text.trim() === '') return;

    this.isSearching = true;

    // 保存搜索历史
    if (!this.searchHistory.includes(text)) {
      this.searchHistory.unshift(text);
      if (this.searchHistory.length > 50) {
        this.searchHistory.pop();
      }
      this.saveSearchHistory();
    }

    try {
      const source: 'kw' | 'kg' | 'tx' | 'wy' | 'mg' | 'all' = this.sourceId as 'kw' | 'kg' | 'tx' | 'wy' | 'mg' | 'all';
      const results: MusicSearchResult[] = await searchMusicApi(text, 1, source);
      this.searchResults = results;
      hilog.info(DOMAIN, TAG, 'Search completed: %{public}s results found', results.length.toString());
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Search failed: %{public}s', JSON.stringify(error));
      this.searchResults = [];
    }

    this.isSearching = false;
  }

  private saveSearchHistory(): void {
    try {
      const historyStr = JSON.stringify(this.searchHistory);
      PersistentStorage.setSync('search_history', historyStr);
      hilog.info(DOMAIN, TAG, 'Saved search history: %{public}d items', this.searchHistory.length);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to save search history: %{public}s', JSON.stringify(error));
    }
  }

  clearHistory(): void {
    this.searchHistory = [];
    try {
      PersistentStorage.setSync('search_history', '[]');
      hilog.info(DOMAIN, TAG, 'Cleared search history');
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to clear search history: %{public}s', JSON.stringify(error));
    }
  }

  // 播放歌曲
  async playSong(song: MusicSearchResult): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, 'Playing song: %{public}s by %{public}s', song.name, song.singer);

      const musicInfo: MusicInfo = {
        id: song.id,
        name: song.name,
        singer: song.singer,
        source: song.source as 'kw' | 'kg' | 'tx' | 'wy' | 'mg',
        songmid: song.songmid || song.id,
        hash: song.hash,
        strMediaMid: song.strMediaMid,
        songId: song.songId,
        albumId: song.albumId,
        copyrightId: song.copyrightId,
        interval: this.formatDurationToInterval(song.duration),
        img: song.pic && song.pic.length > 0 ? song.pic : null,
        pic: song.pic && song.pic.length > 0 ? song.pic : undefined,
        lrc: null,
        albumName: song.album,
        album: song.album,
        types: [],
        _types: new Map(),
        typeUrl: new Map(),
        otherSource: null,
      };

      hilog.info(DOMAIN, TAG, 'Getting music URL for: %{public}s', song.name);
      const url = await getMusicUrl({
        musicInfo,
        quality: null,
        isRefresh: false,
        onToggleSource: null,
        allowToggleSource: true,
      });

      hilog.info(DOMAIN, TAG, 'Got URL: %{public}s', url ? url.substring(0, 50) : 'null');
      if (!url || url.length === 0) {
        hilog.error(DOMAIN, TAG, 'Failed to get music URL');
        return;
      }

      const songInfo: SongInfo = {
        id: song.id,
        songmid: song.songmid || song.id,
        url: url,
        title: song.name,
        artist: song.singer,
        album: song.album ?? '',
        artwork: song.pic && song.pic.length > 0 ? song.pic : null,
        duration: song.duration,
        source: song.source,
        hash: song.hash,
        strMediaMid: song.strMediaMid,
        songId: song.songId,
        albumId: song.albumId,
        copyrightId: song.copyrightId,
      };

      hilog.info(DOMAIN, TAG, 'Setting player source...');
      await playerService.setSource(songInfo, url, song.duration);
      hilog.info(DOMAIN, TAG, 'Source set, starting playback...');
      await playerService.play();
      hilog.info(DOMAIN, TAG, 'Playback started, navigating to detail...');
      navigationService.navigateTo(RouteName.PLAY_DETAIL);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to play song: %{public}s', JSON.stringify(error));
    }
  }

  // 将秒数转换为 00:00 格式
  formatDurationToInterval(seconds: number): string {
    const minutes = Math.floor(seconds / 60);
    const secs = seconds % 60;
    return `${minutes.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }

  build() {
    Column() {
      // 内容区
      if (this.isSearching) {
        this.LoadingView()
      } else if (this.searchResults.length > 0) {
        this.SearchResults()
      } else {
        this.SearchHistoryAndHot()
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  LoadingView() {
    Column() {
      LoadingProgress()
        .width(32)
        .height(32)
        .margin({ top: 40 })
      Text('搜索中...')
        .fontSize(14)
        .fontColor('#999999')
        .margin({ top: 12 })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  SearchHistory() {
    if (this.searchHistory.length > 0) {
      Column() {
        Row() {
          Text('搜索历史')
            .fontSize(14)
            .fontColor('#666666')
          Blank()
          Text('清空')
            .fontSize(12)
            .fontColor('#999999')
            .onClick(() => {
              this.clearHistory();
            })
        }
        .padding({ left: 12, right: 12, top: 12, bottom: 8 })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.searchHistory, (word: string) => {
            Text(word)
              .fontSize(13)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor('#F0F0F0')
              .borderRadius(4)
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.handleSearch(word);
              })
          })
        }
        .padding({ left: 12, right: 12 })
      }
    }
  }

  @Builder
  HotSearchList() {
    Column() {
      // 音乐源切换 Tab
      Row() {
        ForEach(this.sources, (source: string) => {
          Text(this.getSourceName(source))
            .fontSize(this.currentHotSource === source ? 14 : 12)
            .fontColor(this.currentHotSource === source ? '#E63946' : '#999999')
            .fontWeight(this.currentHotSource === source ? FontWeight.Bold : FontWeight.Normal)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .onClick(() => {
              this.currentHotSource = source;
              this.hotSearchList = this.hotSearchCache.get(source) || [];
            })
        })
      }
      .width('100%')
      .padding({ left: 12 })
      .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FAFAFA')

      // 热搜列表
      List() {
        ForEach(this.hotSearchList, (item: HotSearchItem, index: number) => {
          ListItem() {
            Row() {
              Text((index + 1).toString())
                .fontSize(12)
                .fontColor(this.isHotTop(index) ? '#E63946' : '#999999')
                .width(24)
              Text(item.title)
                .fontSize(14)
                .fontColor('#333333')
                .layoutWeight(1)
              if (item.hot) {
                Text(this.formatHotCount(item.hot))
                  .fontSize(10)
                  .fontColor('#999999')
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .onClick(() => {
              this.handleSearch(item.title);
            })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
    }
  }

  @Builder
  SearchHistoryAndHot() {
    Column() {
      this.SearchHistory()
      this.HotSearchList()
    }
    .width('100%')
    .layoutWeight(1)
  }

  @Builder
  SearchResults() {
    List() {
      ForEach(this.searchResults, (song: MusicSearchResult) => {
        ListItem() {
          Row() {
            // 歌曲封面
            if (song.pic) {
              Image(song.pic)
                .width(40)
                .height(40)
                .borderRadius(4)
                .margin({ right: 12 })
            } else {
              Column()
                .width(40)
                .height(40)
                .backgroundColor('#E0E0E0')
                .borderRadius(4)
                .margin({ right: 12 })
            }

            Column() {
              Text(song.name)
                .fontSize(15)
                .fontColor('#333333')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(song.singer)
                .fontSize(12)
                .fontColor('#999999')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .padding({ right: 8 })

            Text(this.formatDuration(song.duration))
              .fontSize(12)
              .fontColor('#999999')
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 12, bottom: 12 })
          .onClick(() => {
            hilog.info(DOMAIN, TAG, 'Clicked song: %{public}s', song.name);
            this.playSong(song);
          })
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .divider({ strokeWidth: 0.5, color: '#F0F0F0' })
  }

  getSourceName(source: string): string {
    switch (source) {
      case 'kw':
        return '酷我';
      case 'tx':
        return 'QQ';
      case 'mg':
        return '咪咕';
      case 'wy':
        return '网易';
      case 'kg':
        return '酷狗';
      default:
        return source;
    }
  }

  isHotTop(index: number): boolean {
    return index < 3;
  }

  formatHotCount(hot: number): string {
    if (hot >= 1000000) {
      return (hot / 1000000).toFixed(1) + '万';
    } else if (hot >= 1000) {
      return (hot / 1000).toFixed(1) + 'k';
    }
    return hot.toString();
  }

  formatDuration(duration: number): string {
    const minutes = Math.floor(duration / 60);
    const seconds = Math.floor(duration % 60);
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  }
}
