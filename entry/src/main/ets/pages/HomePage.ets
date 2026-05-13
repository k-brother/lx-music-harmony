// 首页 - 对应 src/screens/Home/Vertical/index.tsx
// 顶部音乐源 Tab；全局搜歌仅在「歌单」Tab 内容区上方（与排行榜页内搜索条样式一致）

import hilog from '@ohos.hilog';
import { searchMusic, getHotSearch, HotSearchItem, Source } from '../core/search/search';

// 导入播放器栏组件
import { PlayerBar } from '../components/player/PlayerBar';
import { stateEvent } from '../event/StateEvent';
import { SongListView } from './Home/SongListView';
import { LeaderboardView } from './Home/LeaderboardView';
import { MylistView } from './Home/MylistView';
import { navigationService, RouteName } from '../service/NavigationService';
import { DownloadPage } from './DownloadPage';
import { setDownloadContext, getMusicUrl } from '../core/music/MusicFeatureEntry';
import { common } from '@kit.AbilityKit';
import type { MusicSource, MusicInfo } from '../types/MusicTypes';
import { formatPlayTime } from '../utils/CommonUtils';
import { playerService, SongInfo } from '../service/PlayerService';
import { DesignTokens } from '../theme/DesignTokens';
import { SearchStripActions } from '../components/common/SearchStrip';

// 音乐信息类型
export interface MusicInfoType {
  name: string | null;
  singer: string | null;
  pic: string | null;
}

// 音乐源选项
interface SourceOption {
  id: string;
  name: string;
}

// 搜索结果项
interface SearchResultItem {
  id: string;
  songmid?: string;
  name: string;
  singer: string;
  album: string;
  pic: string;
  duration: number;
  source: string;
  albumId?: string;
  hash?: string;
  strMediaMid?: string;
  songId?: number;
  copyrightId?: string;
}

// 搜索状态枚举
enum SearchViewState {
  HIDDEN = 'hidden',      // 未展开
  INPUT = 'input',        // 搜索输入中（显示热搜+搜索历史）
  RESULT = 'result',      // 搜索结果显示
}

@Component
export struct HomePage {
  @StorageProp('theme') theme: string = 'light';
  @State currentTab: number = 0;
  @State isPlay: boolean = false;
  @State musicName: string = '';
  @State singer: string = '';
  @State pic: string = '';

  // 搜索状态
  @State searchViewState: string = SearchViewState.HIDDEN;
  @State searchText: string = '';
  @State searchResults: SearchResultItem[] = [];
  @State hotSearchList: HotSearchItem[] = [];
  @State isSearching: boolean = false;

  // 当前音乐源
  @State currentSource: string = 'kw';

  /** 顶部音乐源切换时递增，确保歌单/排行榜子组件重建并重新请求（@Prop 单独更新在部分机型上可能不触发 aboutToAppear） */
  @State sourceContentEpoch: number = 0;

  // 事件监听器引用（用于 aboutToDisappear 时取消订阅）
  private onPlayStateChanged: ((data: string) => void) | null = null;
  private onPlayerMusicInfoChanged: ((data: string) => void) | null = null;

  // 搜索请求版本控制，防止竞态
  private searchEpoch: number = 0;
  private searchResultsEpoch: number = 0;
  private hotSearchEpoch: number = 0;
  /** 记录上一次成功展示结果的关键词，避免同词重复请求抖动把结果清空 */
  private lastResolvedSearchQuery: string = '';
  private sourceSwitchLocked: boolean = false;

  /** 歌单顶栏下搜索条：与 SearchStrip 共享回调 */
  private globalSearchStripActions: SearchStripActions = new SearchStripActions();

  // 音乐源选项
  private sourceOptions: SourceOption[] = [
    { id: 'kw', name: '酷我' },
    { id: 'tx', name: 'QQ' },
    { id: 'wy', name: '网易' },
    { id: 'kg', name: '酷狗' },
    { id: 'mg', name: '咪咕' },
  ];

  // 订阅播放器状态
  aboutToAppear() {
    this.onPlayStateChanged = (isPlayStr: string) => {
      this.isPlay = isPlayStr === 'true';
    };
    this.onPlayerMusicInfoChanged = (musicInfoStr: string) => {
      const musicInfo: MusicInfoType = JSON.parse(musicInfoStr);
      this.musicName = musicInfo.name || '';
      this.singer = musicInfo.singer || '';
      this.pic = musicInfo.pic || '';
    };
    stateEvent.on('playStateChanged', this.onPlayStateChanged);
    stateEvent.on('playerMusicInfoChanged', this.onPlayerMusicInfoChanged);

    this.globalSearchStripActions.onMagnifierClick = (): void => {
      this.openSearch();
    };
    this.globalSearchStripActions.onSubmit = (): void => {
      void this.submitGlobalSearchFromStrip();
    };
    this.globalSearchStripActions.onTextChange = (_t: string): void => {};

    // 设置下载上下文
    this.setDownloadContext();
  }

  // 设置下载上下文
  setDownloadContext() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      setDownloadContext(context);
      hilog.info(0x0001, 'HomePage', 'Download context set successfully');
    } catch (err) {
      hilog.error(0x0001, 'HomePage', 'Failed to set download context: %{public}s', JSON.stringify(err));
    }
  }

  aboutToDisappear() {
    if (this.onPlayStateChanged) {
      stateEvent.off('playStateChanged', this.onPlayStateChanged);
      this.onPlayStateChanged = null;
    }
    if (this.onPlayerMusicInfoChanged) {
      stateEvent.off('playerMusicInfoChanged', this.onPlayerMusicInfoChanged);
      this.onPlayerMusicInfoChanged = null;
    }
  }

  // 打开搜索界面
  openSearch(): void {
    this.searchViewState = SearchViewState.INPUT;
    this.loadHotSearch();
  }

  // 关闭搜索界面
  closeSearch(): void {
    this.searchViewState = SearchViewState.HIDDEN;
    this.searchText = '';
    this.searchResults = [];
  }

  // 加载热搜
  async loadHotSearch(): Promise<void> {
    const currentEpoch = ++this.hotSearchEpoch;
    try {
      const hotData = await getHotSearch(this.currentSource);
      // 检查版本是否过期（用户可能已切换到其他源）
      if (currentEpoch !== this.hotSearchEpoch) {
        return;
      }
      const items: HotSearchItem[] = [];
      for (let idx = 0; idx < hotData.length; idx++) {
        const item: HotSearchItem = hotData[idx];
        const newItem: HotSearchItem = {
          index: idx + 1,
          title: item.title,
          source: item.source,
          url: item.url,
          hot: item.hot ?? 0,
        };
        items.push(newItem);
      }
      this.hotSearchList = items;
    } catch (e) {
      hilog.warn(0x0001, 'HomePage', 'loadHotSearch failed: %{public}s', (e as Error)?.message);
      if (currentEpoch !== this.hotSearchEpoch) {
        return;
      }
      this.hotSearchList = [];
    }
  }

  // 执行搜索
  async doSearch(): Promise<void> {
    const query = this.searchText.trim();
    if (!query) return;
    const currentEpoch = ++this.searchEpoch;
    const previousResults = this.searchResults.slice();
    this.isSearching = true;
    try {
      // 使用统一搜索入口（core/search），避免首页与其他页面走不同链路。
      let results = await searchMusic(query, 1, this.currentSource as Source);
      // 当前源无结果时，回退全源聚合
      if (results.length === 0 && this.currentSource !== 'all') {
        results = await searchMusic(query, 1, 'all');
      }
      hilog.info(0x0001, 'HomePage', 'doSearch query=%{public}s source=%{public}s count=%{public}d',
        query, this.currentSource, results.length);
      // 检查版本是否过期（用户可能已发起新搜索）
      if (currentEpoch !== this.searchEpoch) {
        return;
      }
      const items: SearchResultItem[] = [];
      for (let i = 0; i < results.length; i++) {
        const r = results[i];
        const item: SearchResultItem = {
          id: r.id,
          songmid: r.songmid,
          name: r.name,
          singer: r.singer,
          album: r.album,
          pic: r.pic || '',
          duration: r.duration,
          source: r.source,
          albumId: r.albumId,
          hash: r.hash,
          strMediaMid: r.strMediaMid,
          songId: r.songId,
          copyrightId: r.copyrightId,
        };
        items.push(item);
      }
      // 同关键词重复请求若返回空，保留已有结果，避免点击歌曲后因偶发重复搜索导致“瞬间空列表”
      if (items.length === 0 && previousResults.length > 0 && query === this.lastResolvedSearchQuery) {
        hilog.warn(0x0001, 'HomePage', 'doSearch keep previous results for query: %{public}s', query);
        this.searchResults = previousResults;
      } else {
        this.searchResults = items;
        this.lastResolvedSearchQuery = query;
      }
      this.searchResultsEpoch = currentEpoch;
      this.searchViewState = SearchViewState.RESULT;
    } catch (err) {
      hilog.error(0x0001, 'HomePage', 'Search failed: %{public}s', JSON.stringify(err));
      if (currentEpoch === this.searchEpoch) {
        // 同关键词异常时保留已有结果，避免误显示“未找到相关结果”
        if (previousResults.length > 0 && query === this.lastResolvedSearchQuery) {
          this.searchResults = previousResults;
        } else {
          this.searchResults = [];
        }
      }
    } finally {
      if (currentEpoch === this.searchEpoch) {
        this.isSearching = false;
      }
    }
  }

  // 点击热搜项：填入搜索框并搜索，不自动播放（用户自行选择结果播放）
  onHotSearchClick(keyword: string): void {
    this.searchText = keyword;
    void this.doSearch();
  }

  /** 歌单主页：与排行榜页内搜索条一致的圆角灰底 + 放大镜 + 输入（提交即打开结果浮层） */
  async submitGlobalSearchFromStrip(): Promise<void> {
    const q = this.searchText.trim();
    if (q.length === 0) {
      this.openSearch();
      return;
    }
    this.searchViewState = SearchViewState.RESULT;
    await this.doSearch();
  }

  // 顶部栏：大标题层次 + 源切换（歌单/排行榜）与系统导航栏气质对齐
  @Builder
  TopBar() {
    Column() {
      Row() {
        if (this.currentTab === 0 || this.currentTab === 1) {
          Row() {
            ForEach(this.sourceOptions, (source: SourceOption) => {
              Text(source.name)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .fontSize(16)
                .fontColor(this.currentSource === source.id ? DesignTokens.accent() : DesignTokens.labelSecondary(this.theme))
                .fontWeight(this.currentSource === source.id ? FontWeight.Medium : FontWeight.Normal)
                .padding({ top: 8, bottom: 8 })
                .onClick(() => {
                  if (this.currentSource === source.id || this.sourceSwitchLocked) {
                    return;
                  }
                  this.sourceSwitchLocked = true;
                  this.sourceContentEpoch++;
                  this.currentSource = source.id;
                  setTimeout((): void => {
                    this.sourceSwitchLocked = false;
                  }, 180);
                  if (this.searchViewState === SearchViewState.INPUT) {
                    void this.loadHotSearch();
                  }
                })
            })
          }
          .layoutWeight(1)
          .padding({ left: DesignTokens.spaceGutter() - 4, right: DesignTokens.spaceGutter() - 4 })
          .alignItems(VerticalAlign.Center)
        } else if (this.currentTab === 2) {
          Column() {
            Text('下载')
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .letterSpacing(-0.5)
            Text('传输与缓存')
              .fontSize(13)
              .fontColor(DesignTokens.labelSecondary(this.theme))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .padding({ left: DesignTokens.spaceGutter() })
          .justifyContent(FlexAlign.Center)
        } else {
          Row() {
            Text('我的')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(DesignTokens.labelPrimary(this.theme))
            .layoutWeight(1)
              .padding({ left: DesignTokens.spaceGutter() })

            Text('设置')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(DesignTokens.accent())
              .padding({ left: 8, right: 4, top: 6, bottom: 6 })
            .margin({ right: DesignTokens.spaceGutter() })
            .onClick(() => {
              navigationService.navigateTo(RouteName.SETTINGS);
            })
          }
          .width('100%')
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 52 })
      .alignItems(VerticalAlign.Center)
      .padding({ top: 2, bottom: 6 })
    }
    .width('100%')
    .backgroundColor(DesignTokens.chromeBar(this.theme))
    .border({ width: { bottom: 0.33 }, color: DesignTokens.hairlineSeparator(this.theme) })
  }

  // 搜索面板（覆盖在内容区上方）
  @Builder
  SearchOverlay() {
    if (this.searchViewState !== SearchViewState.HIDDEN) {
      Column() {
        Row() {
          Row() {
            Image($r('sys.symbol.magnifyingglass'))
              .width(17)
              .height(17)
              .fillColor(DesignTokens.labelSecondary(this.theme))
              .margin({ left: 10, right: 6 })
            TextInput({ placeholder: '搜索歌曲、歌手、专辑', text: this.searchText })
              .layoutWeight(1)
              .height(DesignTokens.heightSearchField())
              .backgroundColor('rgba(0,0,0,0)')
              .fontSize(16)
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .placeholderColor(DesignTokens.labelTertiary(this.theme))
              .padding({ right: 10 })
              .onChange((text: string) => {
                this.searchText = text;
              })
              .onSubmit(() => {
                void this.submitGlobalSearchFromStrip();
              })
          }
          .layoutWeight(1)
          .height(DesignTokens.heightSearchField())
          .backgroundColor(DesignTokens.mutedFill(this.theme))
          .borderRadius(DesignTokens.radiusSearch())
          .border({ width: 0.5, color: DesignTokens.searchFieldBorder(this.theme) })
          .alignItems(VerticalAlign.Center)

          Text('取消')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.accent())
            .padding({ left: 12, right: 4, top: 8, bottom: 8 })
            .margin({ left: 4 })
            .onClick(() => {
              this.closeSearch();
            })
        }
        .width('100%')
        .padding({ left: DesignTokens.spaceGutter(), right: DesignTokens.spaceGutter() - 8, top: 10, bottom: 6 })
        .alignItems(VerticalAlign.Center)

        // 搜索内容
        if (this.searchViewState === SearchViewState.INPUT) {
          this.SearchInputContent()
        } else if (this.searchViewState === SearchViewState.RESULT) {
          this.SearchResultContent()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(DesignTokens.pageBg(this.theme))
    }
  }

  // 搜索输入界面（热搜+历史）
  @Builder
  SearchInputContent() {
    Column() {
      // 热搜标题（小号大写感：次级标签样式）
      Row() {
        Text('热门搜索')
          .fontSize(13)
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding({ left: DesignTokens.spaceGutter(), top: 8, bottom: 6 })

      // 热搜列表
      List() {
        ForEach(this.hotSearchList, (item: HotSearchItem) => {
          ListItem() {
            Row() {
              Text((item.index).toString())
                .fontSize(15)
                .fontColor(item.index <= 3 ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme))
                .fontWeight(item.index <= 3 ? FontWeight.Medium : FontWeight.Normal)
                .width(28)

              Text(item.title)
                .fontSize(16)
                .fontColor(DesignTokens.labelPrimary(this.theme))
                .layoutWeight(1)

              Image($r('sys.symbol.chevron_right'))
                .width(14)
                .height(14)
                .fillColor(DesignTokens.labelTertiary(this.theme))
            }
            .width('100%')
            .padding({
              left: DesignTokens.spaceGutter(),
              right: DesignTokens.spaceGutter(),
              top: 12,
              bottom: 12,
            })
            .border({ width: { bottom: 0.33 }, color: DesignTokens.hairlineSeparator(this.theme) })
            .onClick(() => {
              this.onHotSearchClick(item.title);
            })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(DesignTokens.pageBg(this.theme))
    }
    .width('100%')
    .layoutWeight(1)
  }

  // 搜索结果界面
  @Builder
  SearchResultContent() {
    Column() {
      if (this.isSearching) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(DesignTokens.accent())
          Text('搜索中…')
            .fontSize(15)
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.searchResults.length === 0) {
        Column() {
          Text('未找到相关结果')
            .fontSize(15)
            .fontColor(DesignTokens.labelSecondary(this.theme))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.searchResults, (item: SearchResultItem) => {
            ListItem() {
              Row() {
                Column() {
                  Text(item.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(DesignTokens.labelPrimary(this.theme))
                    .maxLines(1)
                  Text(item.singer + ' · ' + item.album)
                    .fontSize(14)
                    .fontColor(DesignTokens.labelSecondary(this.theme))
                    .maxLines(1)
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text(this.getSourceName(item.source))
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(DesignTokens.accent())
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(DesignTokens.accentSoft(this.theme))
                  .borderRadius(DesignTokens.radiusSearch())
              }
              .width('100%')
              .padding({
                left: DesignTokens.spaceGutter(),
                right: DesignTokens.spaceGutter(),
                top: 12,
                bottom: 12,
              })
              .border({ width: { bottom: 0.33 }, color: DesignTokens.hairlineSeparator(this.theme) })
            }
            .onClick(() => {
              void this.playSearchResult(item);
            })
          })
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(DesignTokens.pageBg(this.theme))
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  getSourceName(sourceId: string): string {
    if (sourceId === 'kw') return '酷我';
    if (sourceId === 'tx') return 'QQ';
    if (sourceId === 'wy') return '网易';
    if (sourceId === 'kg') return '酷狗';
    if (sourceId === 'mg') return '咪咕';
    return sourceId;
  }

  /** 搜索overlay内：点击搜索结果行播放 */
  async playSearchResult(item: SearchResultItem): Promise<void> {
    try {
      const src = item.source as MusicSource;
      const musicInfo: MusicInfo = {
        id: item.id,
        name: item.name,
        singer: item.singer,
        source: src,
        songmid: item.songmid || item.id,
        strMediaMid: src === 'tx' ? (item.strMediaMid || item.songmid || item.id) : item.strMediaMid,
        hash: item.hash,
        songId: item.songId,
        albumId: item.albumId,
        copyrightId: item.copyrightId,
        albumName: item.album,
        album: item.album,
        interval: item.duration > 0 ? formatPlayTime(item.duration) : null,
        img: item.pic && item.pic.length > 0 ? item.pic : null,
        pic: item.pic && item.pic.length > 0 ? item.pic : undefined,
        lrc: null,
        types: [],
        _types: new Map(),
        typeUrl: new Map(),
        otherSource: null,
      };
      const url: string | null = await getMusicUrl({
        musicInfo,
        quality: '128k',
        isRefresh: false,
        onToggleSource: null,
        allowToggleSource: true,
      });
      if (!url || url.length === 0) {
        hilog.warn(0x0001, 'HomePage', 'playSearchResult: no url for %{public}s', item.name);
        return;
      }
      const durSec = item.duration > 0 ? item.duration : 0;
      const songInfo: SongInfo = {
        id: item.id,
        songmid: item.songmid || item.id,
        url: url,
        title: item.name,
        artist: item.singer,
        album: item.album,
        artwork: item.pic || null,
        duration: durSec,
        source: item.source,
        hash: item.hash,
        strMediaMid: item.strMediaMid,
        songId: item.songId,
        albumId: item.albumId,
        copyrightId: item.copyrightId,
      };
      await playerService.setSource(songInfo, url, durSec);
      await playerService.play();
      // 不关闭搜索浮层，用户可在结果列表中自由切换歌曲
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0x0001, 'HomePage', 'playSearchResult failed: %{public}s', msg);
    }
  }

  @Builder
  MainTabItem(index: number, icon: Resource, label: string) {
    Column() {
      Image(icon)
        .width(DesignTokens.iconMd())
        .height(DesignTokens.iconMd())
        .fillColor(this.currentTab === index ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme))
      Text(label)
        .fontSize(14)
        .fontColor(this.currentTab === index ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme))
        .fontWeight(this.currentTab === index ? FontWeight.Medium : FontWeight.Normal)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.currentTab = index;
    })
  }

  // 底部 TabBar：紧凑型，保留安全区底色
  @Builder
  BottomTabBar() {
    Column() {
      Row() {
        this.MainTabItem(0, $r('sys.symbol.music_note_list'), '歌单')
        this.MainTabItem(1, $r('sys.symbol.list_number'), '排行榜')
        this.MainTabItem(2, $r('sys.symbol.arrow_down_circle'), '下载')
        this.MainTabItem(3, $r('sys.symbol.person'), '我的')
      }
      .width('100%')
      .height(44)
      .padding({ top: 4, bottom: 4 })
      .border({ width: { top: 0.33 }, color: DesignTokens.hairlineSeparator(this.theme) })

      Blank()
        .width('100%')
        .height(6)
    }
    .width('100%')
    .backgroundColor(DesignTokens.tabBarBg(this.theme))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  // 内容区域
  @Builder
  ContentArea() {
    if (this.currentTab === 0) {
      SongListView({
        sourceId: this.currentSource,
        reCreateKey: this.sourceContentEpoch,
        searchText: $searchText,
        searchStripActions: this.globalSearchStripActions,
      })
    } else if (this.currentTab === 1) {
      LeaderboardView({ sourceId: this.currentSource, reCreateKey: this.sourceContentEpoch })
    } else if (this.currentTab === 2) {
      DownloadPage()
    } else if (this.currentTab === 3) {
      // 我的页面
      MylistView()
    }
  }

  build() {
    Stack() {
      // 主界面
      Column() {
        // 下载页使用自身头部，避免与 Home 顶栏重复
        if (this.currentTab !== 2) {
          this.TopBar()
        }

        // 歌单 Tab：搜索条已放入 SongListView 内垂直 Scroll 顶部，随列表上滑滚出、回顶再现

        // 内容区
        Column() {
          this.ContentArea()
        }
        .width('100%')
        .layoutWeight(1)

        // 播放器栏
        PlayerBar()

        // 底部TabBar
        this.BottomTabBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(DesignTokens.pageBg(this.theme))

      // 搜索面板覆盖层
      this.SearchOverlay()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
