// 首页 - 对应 src/screens/Home/Vertical/index.tsx
// 顶部音乐源 Tab；全局搜歌仅在「歌单」Tab 内容区上方（与排行榜页内搜索条样式一致）

import hilog from '@ohos.hilog';
import { SourceTabBar } from './Home/Home/SourceTabBar';
import { HomeBottomTabBar, type HomeTabItem } from './Home/Home/HomeBottomTabBar';
import { SearchMusicResultList, SearchSonglistResultList } from './Home/Home/SearchResultLists';
import { SearchInputContent } from './Home/Home/SearchInputContent';
import { promoteHistoryWord, runSongSearch, runSonglistSearch } from './Home/Home/SearchRunner';
import type { SearchResultItem } from './Home/Home/SearchResultTypes';
import { StateView } from '../components/ui/StateView';
import { getHotSearch, getTipListInfo, HotSearchItem, Source } from '../core/search/search';

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
import { Breakpoints } from '../theme/Breakpoints';
import { requestFocusSafe } from '../utils/FocusTools';
import { t, sourceLabel } from '../service/LocalizationService';
import { settingsService } from '../service/SettingsService';
import {
  addHistoryWord,
  clearHistoryList,
  getSearchHistory,
  type SonglistSearchResult,
} from '../core/search/search';
import { type NavigationParams } from '../service/NavigationService';
import { on, EventTypes } from '../service/EventBus';

/** 搜索输入框的焦点键（供 FocusController 定位，浮层出现时自动聚焦） */
const SEARCH_INPUT_KEY: string = 'homeSearchInput';

// 音乐信息类型
export interface MusicInfoType {
  name: string | null;
  singer: string | null;
  pic: string | null;
}

// 音乐源选项
interface BottomTabItem {
  idx: number;
  icon: Resource;
  label: string;
}

interface SourceOption {
  id: string;
  name: string;
}

// 搜索结果项
// 搜索状态枚举
enum SearchViewState {
  HIDDEN = 'hidden',      // 未展开
  INPUT = 'input',        // 搜索输入中（显示热搜+搜索历史）
  RESULT = 'result',      // 搜索结果显示
}

@Component
export struct HomePage {
  @StorageProp('theme') theme: string = 'light';
  /** 一多：断点（宽屏走左侧导航） */
  @StorageProp('breakpoint') breakpoint: string = 'sm';
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
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
  /** 搜索类型：单曲 / 歌单 */
  @State searchType: string = 'music';
  @State songlistResults: SonglistSearchResult[] = [];
  @State searchHistory: string[] = [];
  /** 搜索联想词（输入即出，对应安卓版 TipList） */
  @State searchTips: string[] = [];
  @State showHotSearchSetting: boolean = true;
  /** 是否显示搜索历史（设置 → 搜索设置） */
  @State showSearchHistorySetting: boolean = false;

  // 当前音乐源（默认值来自「设置 -> 搜索设置 -> 默认搜索源」）
  @State currentSource: string = 'kw';

  /** 顶部音乐源切换时递增，确保歌单/排行榜子组件重建并重新请求（@Prop 单独更新在部分机型上可能不触发 aboutToAppear） */
  @State sourceContentEpoch: number = 0;

  // 事件监听器引用（用于 aboutToDisappear 时取消订阅）
  private onPlayStateChanged: ((data: string) => void) | null = null;
  private onPlayerMusicInfoChanged: ((data: string) => void) | null = null;
  private desktopLyricUnsub: (() => void) | null = null;
  private settingsUnsub: (() => void) | null = null;
  private searchRequestUnsub: (() => void) | null = null;

  // 搜索请求版本控制，防止竞态
  private searchEpoch: number = 0;
  private searchResultsEpoch: number = 0;
  private hotSearchEpoch: number = 0;
  /** 记录上一次成功展示结果的关键词，避免同词重复请求抖动把结果清空 */
  private lastResolvedSearchQuery: string = '';
  /** 联想词请求版本与防抖定时器：丢弃过期响应，避免逐字符打请求 */
  private tipEpoch: number = 0;
  private tipTimer: number = -1;
  private sourceSwitchLocked: boolean = false;

  /** 歌单顶栏下搜索条：与 SearchStrip 共享回调 */
  private globalSearchStripActions: SearchStripActions = new SearchStripActions();

  // 音乐源选项（getter 保证每次调用重新执行 t()）
  private getSourceOptions(): SourceOption[] {
    // 名称统一走 sourceLabel：跟随「设置 → 源名显示」（别名/原名）
    return [
      { id: 'kw', name: sourceLabel('kw') },
      { id: 'tx', name: sourceLabel('tx') },
      { id: 'wy', name: sourceLabel('wy') },
      { id: 'kg', name: sourceLabel('kg') },
      { id: 'mg', name: sourceLabel('mg') },
    ];
  }

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

    // 应用搜索相关设置（默认搜索源/热搜开关）
    this.applySearchSettings();
    void this.loadSearchHistory();
    // 设置是异步加载的，加载完成后同步一次（避免首帧读到默认值）
    this.settingsUnsub = on(EventTypes.SETTING_CHANGED, (): void => {
      this.applySearchSettings();
    });
    // 其他页面（如歌单详情「查看歌手/专辑」）请求首页发起搜索
    this.searchRequestUnsub = on(EventTypes.SEARCH_REQUEST, (data?: Object): void => {
      this.applyExternalSearchRequest(data);
    });
  }

  /** 外部搜索请求：切到搜索页并用关键词发起一次搜索 */
  private applyExternalSearchRequest(data?: Object): void {
    if (!data) {
      return;
    }
    const keyword = (data as Record<string, Object>)['keyword'];
    if (typeof keyword !== 'string' || keyword.trim().length === 0) {
      return;
    }
    this.searchType = 'music';
    this.searchText = keyword.trim();
    this.openSearch();
    this.searchViewState = SearchViewState.RESULT;
    void this.doSearch();
  }

  /** 读取搜索设置：默认搜索源与热搜开关 */
  private applySearchSettings(): void {
    const settings = settingsService.get();
    const savedSource = settings.searchSource;
    if (savedSource === 'kw' || savedSource === 'kg' || savedSource === 'tx'
      || savedSource === 'wy' || savedSource === 'mg') {
      this.currentSource = savedSource;
    }
    this.showHotSearchSetting = settings.showHotSearch;
    this.showSearchHistorySetting = settings.showSearchHistory;
  }

  private async loadSearchHistory(): Promise<void> {
    try {
      this.searchHistory = await getSearchHistory();
    } catch (err) {
      hilog.warn(0x0001, 'HomePage', 'loadSearchHistory failed: %{public}s', JSON.stringify(err));
    }
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
    if (this.desktopLyricUnsub) {
      this.desktopLyricUnsub();
      this.desktopLyricUnsub = null;
    }
    if (this.settingsUnsub) {
      this.settingsUnsub();
      this.settingsUnsub = null;
    }
    if (this.searchRequestUnsub) {
      this.searchRequestUnsub();
      this.searchRequestUnsub = null;
    }
    this.clearSearchTips();
  }

  // 打开搜索界面
  openSearch(): void {
    this.searchViewState = SearchViewState.INPUT;
    this.applySearchSettings();
    void this.loadSearchHistory();
    if (this.showHotSearchSetting) {
      this.loadHotSearch();
    } else {
      this.hotSearchList = [];
    }
  }

  // 关闭搜索界面
  closeSearch(): void {
    this.searchViewState = SearchViewState.HIDDEN;
    this.searchText = '';
    this.searchResults = [];
    this.clearSearchTips();
  }

  /** 取消待发的联想词请求并清空列表 */
  private clearSearchTips(): void {
    this.tipEpoch++;
    if (this.tipTimer !== -1) {
      clearTimeout(this.tipTimer);
      this.tipTimer = -1;
    }
    this.searchTips = [];
  }

  /**
   * 输入防抖：停止输入 260ms 后再请求联想词
   * 输入被清空时立即收起联想列表
   */
  private scheduleSearchTips(keyword: string): void {
    if (this.tipTimer !== -1) {
      clearTimeout(this.tipTimer);
      this.tipTimer = -1;
    }
    const trimmed = keyword.trim();
    if (trimmed.length === 0) {
      this.clearSearchTips();
      return;
    }
    const epoch = ++this.tipEpoch;
    this.tipTimer = setTimeout(() => {
      this.tipTimer = -1;
      void this.loadSearchTips(trimmed, epoch);
    }, 260);
  }

  /** 拉取联想词（源不支持时静默返回空，不影响搜索） */
  private async loadSearchTips(keyword: string, epoch: number): Promise<void> {
    try {
      const tips = await getTipListInfo(keyword, this.currentSource);
      if (epoch !== this.tipEpoch || this.searchViewState !== SearchViewState.INPUT) {
        return;
      }
      this.searchTips = tips;
    } catch (err) {
      if (epoch === this.tipEpoch) {
        this.searchTips = [];
      }
      hilog.warn(0x0001, 'HomePage', 'loadSearchTips failed: %{public}s', (err as Error)?.message);
    }
  }

  /** 点击联想词：立即用该词发起搜索 */
  private onSearchTipClick(tip: string): void {
    this.searchText = tip;
    this.clearSearchTips();
    void this.submitGlobalSearchFromStrip();
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
    if (!query) {
      return;
    }
    // 歌单搜索走独立分支（单曲搜索结果与歌单结果结构不同）
    if (this.searchType === 'songlist') {
      await this.doSearchSonglist(query);
      return;
    }
    // 记录搜索历史（条数上限由设置决定）
    addHistoryWord(query).then((): void => {
      this.searchHistory = promoteHistoryWord(
        this.searchHistory, query, settingsService.get().searchHistoryCount);
    }).catch((err: Error): void => {
      hilog.warn(0x0001, 'HomePage', 'addHistoryWord failed: %{public}s', err.message);
    });

    const currentEpoch = ++this.searchEpoch;
    const previousResults = this.searchResults.slice();
    this.isSearching = true;
    try {
      // 搜索接口与字段映射在 Home/SearchRunner
      const items: SearchResultItem[] = await runSongSearch(query, this.currentSource as Source);
      // 版本过期（用户已发起新搜索）：丢弃本次结果
      if (currentEpoch !== this.searchEpoch) {
        return;
      }
      // 同关键词重复请求若返回空，保留已有结果，避免点击歌曲后因偶发重复搜索导致「瞬间空列表」
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
        // 同关键词异常时保留已有结果，避免误显示「未找到相关结果」
        this.searchResults = previousResults.length > 0 && query === this.lastResolvedSearchQuery
          ? previousResults
          : [];
      }
    } finally {
      if (currentEpoch === this.searchEpoch) {
        this.isSearching = false;
      }
    }
  }

  private async doSearchSonglist(query: string): Promise<void> {
    addHistoryWord(query).catch((err: Error): void => {
      hilog.warn(0x0001, 'HomePage', 'addHistoryWord failed: %{public}s', err.message);
    });
    this.isSearching = true;
    try {
      this.songlistResults = await runSonglistSearch(query, this.currentSource as Source);
      this.searchViewState = SearchViewState.RESULT;
    } catch (err) {
      hilog.error(0x0001, 'HomePage', 'doSearchSonglist failed: %{public}s', JSON.stringify(err));
      this.songlistResults = [];
    } finally {
      this.isSearching = false;
    }
  }

  private switchSearchType(type: string): void {
    if (this.searchType === type) {
      return;
    }
    this.searchType = type;
    if (this.searchText.trim().length > 0) {
      void this.doSearch();
    }
  }

  /** 打开歌单详情 */
  private openSonglist(item: SonglistSearchResult): void {
    const params: NavigationParams = {
      songListId: item.id,
      songListName: item.name,
      songListSource: item.source,
    };
    navigationService.navigateTo(RouteName.SONGLIST_DETAIL, params);
  }

  // 点击热搜项：填入搜索框并搜索，不自动播放（用户自行选择结果播放）
  onHotSearchClick(keyword: string): void {
    this.searchText = keyword;
    void this.doSearch();
  }

  /** 点击搜索历史 */
  onHistoryClick(keyword: string): void {
    this.searchText = keyword;
    void this.doSearch();
  }

  /** 清除搜索历史 */
  clearSearchHistory(): void {
    this.searchHistory = [];
    clearHistoryList().catch((err: Error) => {
      hilog.warn(0x0001, 'HomePage', 'clearHistoryList failed: %{public}s', err.message);
    });
  }

  /** 歌单主页：与排行榜页内搜索条一致的圆角灰底 + 放大镜 + 输入（提交即打开结果浮层） */
  async submitGlobalSearchFromStrip(): Promise<void> {
    const q = this.searchText.trim();
    this.clearSearchTips();
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
          // 音源切换：横向滚动标签 + 选中下划线（组件化）
          SourceTabBar({
            options: this.getSourceOptions(),
            activeId: this.currentSource,
            onSelect: (id: string): void => {
              this.onSourceSelected(id);
            },
          })
        } else if (this.currentTab === 2) {
          // 大标题 + 一行说明（此前两行都写成 download_title，等于同一句话重复两遍）
          Column() {
            Text(t('download_title'))
              .fontSize(DesignTokens.fontDisplayXl())
              .fontWeight(FontWeight.Bold)
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .letterSpacing(-0.5)
            Text(t('download_subtitle'))
              .fontSize(DesignTokens.fontCallout())
              .fontColor(DesignTokens.labelSecondary(this.theme))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .padding({ left: DesignTokens.spaceGutter() })
          .justifyContent(FlexAlign.Center)
        } else {
          Row() {
            Text(t('tab_my'))
              .fontSize(DesignTokens.fontDisplay())
              .fontWeight(FontWeight.Bold)
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .layoutWeight(1)
              .padding({ left: DesignTokens.spaceGutter() })

            Text(t('settings_title'))
              .fontSize(DesignTokens.fontTitle())
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

  /** 切换音源：加锁避免连点导致内容区反复重建 */
  private onSourceSelected(id: string): void {
    if (this.currentSource === id || this.sourceSwitchLocked) {
      return;
    }
    this.sourceSwitchLocked = true;
    this.sourceContentEpoch++;
    this.currentSource = id;
    setTimeout((): void => {
      this.sourceSwitchLocked = false;
    }, 180);
    if (this.searchViewState === SearchViewState.INPUT) {
      void this.loadHotSearch();
    }
  }

  // 搜索面板（覆盖在内容区上方）
  @Builder
  SearchOverlay() {
    if (this.searchViewState !== SearchViewState.HIDDEN) {
      Column() {
        Row() {
          Row() {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(DesignTokens.fontLarge())
              .fontColor([DesignTokens.labelSecondary(this.theme)])
              .margin({ left: 10, right: 6 })
            TextInput({ placeholder: t('search_placeholder'), text: this.searchText })
              // 焦点键：浮层出现时自动聚焦（见 onAppear），用户不必再点一次
              .key(SEARCH_INPUT_KEY)
              .onAppear(() => {
                requestFocusSafe(this.getUIContext(), SEARCH_INPUT_KEY);
              })
              .layoutWeight(1)
              .height(DesignTokens.heightSearchField())
              .backgroundColor(Color.Transparent)
              .fontSize(DesignTokens.fontTitle())
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .placeholderColor(DesignTokens.labelTertiary(this.theme))
              .padding({ right: 10 })
              .onChange((text: string) => {
                this.searchText = text;
                this.scheduleSearchTips(text);
              })
              .onSubmit(() => {
                this.clearSearchTips();
                void this.submitGlobalSearchFromStrip();
              })
          }
          .layoutWeight(1)
          .height(DesignTokens.heightSearchField())
          .backgroundColor(DesignTokens.mutedFill(this.theme))
          .borderRadius(DesignTokens.radiusSearch())
          .border({ width: 0.5, color: DesignTokens.searchFieldBorder(this.theme) })
          .alignItems(VerticalAlign.Center)

          Text(t('cancel'))
            .fontSize(DesignTokens.fontTitle())
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
          SearchInputContent({
            searchText: this.searchText,
            tips: this.searchTips,
            history: this.searchHistory,
            hotList: this.hotSearchList,
            showHotSearch: this.showHotSearchSetting,
            showHistory: this.showSearchHistorySetting,
            onTipClick: (tip: string): void => this.onSearchTipClick(tip),
            onHotClick: (keyword: string): void => this.onHotSearchClick(keyword),
            onHistoryClick: (keyword: string): void => this.onHistoryClick(keyword),
            onClearHistory: (): void => this.clearSearchHistory(),
          })
        } else if (this.searchViewState === SearchViewState.RESULT) {
          this.SearchResultContent()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(DesignTokens.pageBg(this.theme))
    }
  }

  @Builder
  SearchTypeChip(type: string, label: string) {
    Text(label)
      .fontSize(DesignTokens.fontBody())
      .fontWeight(this.searchType === type ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.searchType === type ? DesignTokens.onAccent() : DesignTokens.labelSecondary(this.theme))
      .backgroundColor(this.searchType === type ? DesignTokens.accent() : DesignTokens.mutedFill(this.theme))
      .borderRadius(15)
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .margin({ right: 8 })
      .onClick(() => {
        this.switchSearchType(type);
      })
  }

  /** 歌单搜索结果列表 */
  /** 歌单结果列表（组件化，空态统一） */
  @Builder
  SonglistResultList() {
    SearchSonglistResultList({
      results: this.songlistResults,
      onOpen: (index: number): void => {
        if (index >= 0 && index < this.songlistResults.length) {
          this.openSonglist(this.songlistResults[index]);
        }
      },
    })
  }


  // 搜索结果界面
  @Builder
  SearchResultContent() {
    Column() {
      // 单曲 / 歌单 切换（吸顶，切换后自动重搜）
      Row() {
        this.SearchTypeChip('music', t('search_type_music'))
        this.SearchTypeChip('songlist', t('search_type_songlist'))
      }
      .width('100%')
      .padding({ left: DesignTokens.spaceGutter(), right: DesignTokens.spaceGutter(), top: 4, bottom: 8 })

      if (this.isSearching) {
        StateView({ state: 'loading' })
          .width('100%')
          .layoutWeight(1)
      } else if (this.searchType === 'songlist') {
        this.SonglistResultList()
      } else {
        SearchMusicResultList({
          results: this.searchResults,
          onPlay: (index: number): void => {
            if (index >= 0 && index < this.searchResults.length) {
              void this.playSearchResult(this.searchResults[index]);
            }
          },
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  /** 搜索overlay内：点击搜索结果行播放 */
  async playSearchResult(item: SearchResultItem): Promise<void> {
    try {
      // 队列 = 当前搜索结果列表（临时队列，不写入用户列表）
      // 这样「下一首/上一首」可以在结果里连续播放，且不会静默改动用户数据
      if (this.searchResults.length > 1) {
        const queue: SongInfo[] = [];
        let startIndex = 0;
        for (let i = 0; i < this.searchResults.length; i++) {
          const r = this.searchResults[i];
          if (r.id === item.id && r.source === item.source) {
            startIndex = i;
          }
          queue.push({
            id: r.id,
            songmid: r.songmid || r.id,
            url: '',
            title: r.name,
            artist: r.singer,
            album: r.album,
            artwork: r.pic || null,
            duration: r.duration > 0 ? r.duration : 0,
            source: r.source,
            hash: r.hash,
            strMediaMid: r.strMediaMid,
            songId: r.songId,
            albumId: r.albumId,
            copyrightId: r.copyrightId,
          });
        }
        playerService.setPlayList(queue, startIndex);
      }
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
      // 选中歌曲（受「自动播放」设置控制）
      await playerService.playFromSelection(songInfo, url, durSec);
      // 不关闭搜索浮层，用户可在结果列表中自由切换歌曲
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      hilog.error(0x0001, 'HomePage', 'playSearchResult failed: %{public}s', msg);
    }
  }

  /** 底部 Tab 数据（getter 保证每次渲染重新取 t()） */
  private getBottomTabs(): HomeTabItem[] {
    return [
      { idx: 0, icon: $r('sys.symbol.music_note_list'), label: t('songlist_title') },
      { idx: 1, icon: $r('sys.symbol.list_number'), label: t('tab_leaderboard') },
      { idx: 2, icon: $r('sys.symbol.arrow_down_circle'), label: t('download_title') },
      { idx: 3, icon: $r('sys.symbol.person'), label: t('tab_my') },
    ];
  }

  /** 底部 Tab 栏（组件化，选中态带放大动效） */
  @Builder
  BottomTabBar(vertical: boolean) {
    HomeBottomTabBar({
      tabs: this.getBottomTabs(),
      activeIndex: this.currentTab,
      // 宽屏走左侧竖排导航（大屏使用习惯），窄屏仍是底部 Tab
      vertical: vertical,
      onSelect: (index: number): void => {
        this.currentTab = index;
      },
    })
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

  /** 主界面右半部：顶栏 + 内容 + 播放条（宽屏时右侧，窄屏时整屏） */
  @Builder
  MainPane() {
    Column() {
      // 下载页使用自身头部，避免与 Home 顶栏重复
      if (this.currentTab !== 2) {
        this.TopBar()
      }

      // 内容区
      Column() {
        this.ContentArea()
      }
      .width('100%')
      .layoutWeight(1)

      // 播放器栏
      PlayerBar()
    }
    .width('100%')
    .height('100%')
  }

  build() {
    Stack() {
      if (Breakpoints.isWide(this.breakpoint)) {
        // 一多：平板横屏 / PC 用「左侧导航 + 右侧内容」，与主流音乐 App 的大屏形态一致
        Row() {
          this.BottomTabBar(true)
          Column() {
            this.MainPane()
          }
          .layoutWeight(1)
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .backgroundColor(DesignTokens.pageBg(this.theme))
      } else {
        Column() {
          this.MainPane()
          // 底部 Tab 栏
          this.BottomTabBar(false)
        }
        .width('100%')
        .height('100%')
        .backgroundColor(DesignTokens.pageBg(this.theme))
      }

      // 搜索面板覆盖层
      this.SearchOverlay()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
