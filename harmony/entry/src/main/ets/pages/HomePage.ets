// 首页 - 对应 src/screens/Home/Vertical/index.tsx
// 包含 顶部音乐源Tab + 搜索框、底部TabBar 和 PlayerBar

import hilog from '@ohos.hilog';
import { searchMusic, getHotSearch, HotSearchItem, MusicSearchResult, Source } from '../core/search/search';

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
  name: string;
  singer: string;
  album: string;
  pic: string;
  duration: number;
  source: string;
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

  // 搜索请求版本控制，防止竞态
  private searchEpoch: number = 0;
  private searchResultsEpoch: number = 0;
  private hotSearchEpoch: number = 0;

  // 底部 Tab 列表
  private bottomTabs: string[] = ['歌单', '排行榜', '下载', '我的'];

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
    stateEvent.on('playStateChanged', (isPlayStr: string) => {
      this.isPlay = isPlayStr === 'true';
    });
    stateEvent.on('playerMusicInfoChanged', (musicInfoStr: string) => {
      const musicInfo: MusicInfoType = JSON.parse(musicInfoStr);
      this.musicName = musicInfo.name || '';
      this.singer = musicInfo.singer || '';
      this.pic = musicInfo.pic || '';
    });

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
    // 取消订阅
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
    } catch {
      if (currentEpoch !== this.hotSearchEpoch) {
        return;
      }
      this.hotSearchList = [];
    }
  }

  // 执行搜索
  async doSearch(): Promise<void> {
    if (!this.searchText.trim()) return;
    const currentEpoch = ++this.searchEpoch;
    this.isSearching = true;
    try {
      const results = await searchMusic(this.searchText, 1, this.currentSource as Source);
      // 检查版本是否过期（用户可能已发起新搜索）
      if (currentEpoch !== this.searchEpoch) {
        return;
      }
      const items: SearchResultItem[] = [];
      for (let i = 0; i < results.length; i++) {
        const r: MusicSearchResult = results[i];
        const item: SearchResultItem = {
          id: r.id,
          name: r.name,
          singer: r.singer,
          album: r.album,
          pic: r.pic || '',
          duration: r.duration,
          source: r.source,
        };
        items.push(item);
      }
      this.searchResults = items;
      this.searchResultsEpoch = currentEpoch;
      this.searchViewState = SearchViewState.RESULT;
    } catch (err) {
      hilog.error(0x0001, 'HomePage', 'Search failed: %{public}s', JSON.stringify(err));
      if (currentEpoch === this.searchEpoch) {
        this.searchResults = [];
      }
    } finally {
      if (currentEpoch === this.searchEpoch) {
        this.isSearching = false;
      }
    }
  }

  // 点击热搜项：先出结果，若有则直接播第一条（与「点词即听」预期一致）
  onHotSearchClick(keyword: string): void {
    void this.runHotSearchAndMaybePlay(keyword);
  }

  async runHotSearchAndMaybePlay(keyword: string): Promise<void> {
    this.searchText = keyword;
    await this.doSearch();
    // doSearch() 内部已处理 epoch 校验，成功返回时 searchResultsEpoch 与 searchEpoch 同步
    if (this.searchEpoch === this.searchResultsEpoch && this.searchResults.length > 0) {
      await this.playSearchResult(this.searchResults[0]);
    }
  }

  // 顶部音乐源TabBar + 搜索框
  @Builder
  TopBar() {
    Column() {
      // 音乐源 Tab + 搜索框（同一行）
      Row() {
        // Tab 横向滚动区（只在歌单/排行榜显示）
        if (this.currentTab === 0 || this.currentTab === 1) {
          Scroll() {
            Row() {
              ForEach(this.sourceOptions, (source: SourceOption) => {
                Text(source.name)
                  .fontSize(this.currentSource === source.id ? 20 : 17)
                  .fontColor(this.currentSource === source.id ? '#E63946' : (this.theme === 'dark' ? '#CCCCCC' : '#666666'))
                  .fontWeight(this.currentSource === source.id ? FontWeight.Bold : FontWeight.Normal)
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .margin({ right: 6 })
                  .onClick(() => {
                    if (this.currentSource !== source.id) {
                      this.sourceContentEpoch++;
                    }
                    this.currentSource = source.id;
                    if (this.searchViewState === SearchViewState.INPUT) {
                      void this.loadHotSearch();
                    }
                  })
              })
            }
            .padding({ left: 4 })
            .alignItems(VerticalAlign.Center)
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .align(Alignment.Start)
        } else {
          // 我的页面：标题
          Text('我的')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
            .margin({ left: 12 })
        }

        // 搜索框（仅在歌单/排行榜显示）
        if (this.currentTab === 0 || this.currentTab === 1) {
          TextInput({ placeholder: '🔍 搜索', text: this.searchText })
            .width('25%')
            .height(32)
            .flexShrink(0)
            .constraintSize({ minWidth: 50, maxWidth: 90 })
            .backgroundColor(this.theme === 'dark' ? '#2C2C2C' : '#F5F5F5')
            .borderRadius(16)
            .fontSize(10)
            .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
            .placeholderColor('#999999')
            .margin({ right: 8 })
            .textAlign(TextAlign.Start)
            .caretColor('#E63946')
            .onClick(() => { this.openSearch(); })
            .onChange((text: string) => { this.searchText = text; })
        }

      // "我的"页面：搜索框居中 + 右侧设置按钮
      if (this.currentTab === 3) {
        Blank()
          .layoutWeight(1)

        TextInput({ placeholder: '搜索歌曲、歌手、专辑', text: this.searchText })
          .width('40%')
          .height(36)
          .backgroundColor(this.theme === 'dark' ? '#2C2C2C' : '#F0F0F0')
          .borderRadius(18)
          .padding({ left: 16, right: 16 })
          .fontSize(14)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .onChange((value: string) => {
            this.searchText = value;
          })

        Blank()
          .layoutWeight(1)

        // 设置按钮
        Image($r('sys.symbol.gearshape'))
          .width(26)
          .height(26)
          .fillColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .margin({ right: 12 })
          .onClick(() => {
            navigationService.navigateTo(RouteName.SETTINGS);
          })
      }
      }
      .width('100%')
      .height(48)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 8, right: 4 })
    }
    .width('100%')
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
  }

  // 搜索面板（覆盖在内容区上方）
  @Builder
  SearchOverlay() {
    if (this.searchViewState !== SearchViewState.HIDDEN) {
      Column() {
        // 搜索输入栏
        Row() {
          TextInput({ placeholder: '搜索歌曲、歌手、专辑', text: this.searchText })
            .layoutWeight(1)
            .height(36)
            .backgroundColor(this.theme === 'dark' ? '#2C2C2C' : '#F0F0F0')
            .borderRadius(18)
            .padding({ left: 14, right: 14 })
            .fontSize(14)
            .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
            .placeholderColor('#999999')
            .onChange((text: string) => {
              this.searchText = text;
            })
            .onSubmit(() => {
              this.doSearch();
            })

          // 取消按钮
          Text('取消')
            .fontSize(14)
            .fontColor('#E63946')
            .padding({ left: 12, right: 4 })
            .onClick(() => {
              this.closeSearch();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')

        // 搜索内容
        if (this.searchViewState === SearchViewState.INPUT) {
          this.SearchInputContent()
        } else if (this.searchViewState === SearchViewState.RESULT) {
          this.SearchResultContent()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
    }
  }

  // 搜索输入界面（热搜+历史）
  @Builder
  SearchInputContent() {
    Column() {
      // 热搜标题
      Row() {
        Text('热门搜索')
          .fontSize(15)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding({ left: 16, top: 16, bottom: 8 })

      // 热搜列表
      List() {
        ForEach(this.hotSearchList, (item: HotSearchItem) => {
          ListItem() {
            Row() {
              Text((item.index).toString())
                .fontSize(14)
                .fontColor(item.index <= 3 ? '#E63946' : '#999999')
                .fontWeight(item.index <= 3 ? FontWeight.Bold : FontWeight.Normal)
                .width(32)

              Text(item.title)
                .fontSize(14)
                .fontColor(this.theme === 'dark' ? '#CCCCCC' : '#666666')
                .layoutWeight(1)

              Image($r('sys.symbol.chevron_right'))
                .width(16)
                .height(16)
                .fillColor('#999999')
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .onClick(() => {
              this.onHotSearchClick(item.title);
            })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
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
          Text('搜索中...')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.searchResults.length === 0) {
        Column() {
          Text('未找到相关结果')
            .fontSize(14)
            .fontColor('#999999')
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
                    .fontSize(15)
                    .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
                    .maxLines(1)
                  Text(item.singer + ' - ' + item.album)
                    .fontSize(12)
                    .fontColor('#999999')
                    .maxLines(1)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text(this.getSourceName(item.source))
                  .fontSize(11)
                  .fontColor('#E63946')
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .backgroundColor('rgba(230, 57, 70, 0.1)')
                  .borderRadius(4)
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            }
            .onClick(() => {
              void this.playSearchResult(item);
            })
          })
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
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
        songmid: item.id,
        strMediaMid: src === 'tx' ? item.id : undefined,
        albumName: item.album,
        album: item.album,
        interval: item.duration > 0 ? formatPlayTime(item.duration) : null,
        img: item.pic && item.pic.length > 0 ? item.pic : null,
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
        url: url,
        title: item.name,
        artist: item.singer,
        album: item.album,
        artwork: item.pic || null,
        duration: durSec,
        source: item.source,
      };
      await playerService.setSource(songInfo, url, durSec);
      await playerService.play();
      this.closeSearch();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0x0001, 'HomePage', 'playSearchResult failed: %{public}s', msg);
    }
  }

  // 底部 TabBar
  @Builder
  BottomTabBar() {
    Row() {
      ForEach(this.bottomTabs, (tab: string, index: number) => {
        Column() {
          Text(tab)
            .fontSize(this.currentTab === index ? 14 : 12)
            .fontColor(this.currentTab === index ? '#E63946' : (this.theme === 'dark' ? '#AAAAAA' : '#999999'))
            .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
            .onClick(() => {
              this.currentTab = index;
            })
        }
        .layoutWeight(1)
        .height(50)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      })
    }
    .width('100%')
    .height(50)
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
    .border({ width: { top: 0.5 }, color: this.theme === 'dark' ? '#333333' : '#E0E0E0' })
  }

  // 内容区域
  @Builder
  ContentArea() {
    if (this.currentTab === 0) {
      SongListView({ sourceId: this.currentSource, reCreateKey: this.sourceContentEpoch })
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
        // 顶部音乐源TabBar（去掉状态栏间距）
        this.TopBar()

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
      .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')

      // 搜索面板覆盖层
      this.SearchOverlay()
    }
    .width('100%')
    .height('100%')
  }
}
