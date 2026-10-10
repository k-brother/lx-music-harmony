// 首页 - 对应 src/screens/Home/Vertical/index.tsx
// 顶部音乐源 Tab；全局搜歌仅在「歌单」Tab 内容区上方（与排行榜页内搜索条样式一致）

import { hilog } from '@kit.PerformanceAnalysisKit';
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
import { appActionMenu, appToast } from '../service/DialogService';
import { showSongItemMenu } from './SonglistDetail/SonglistMenus';
import { songRowToQueueItem } from '../core/list/SongMappers';
import {
  addRowToDefaultList,
  addRowToDislike,
  downloadRow,
  openInBrowser,
  shareSongRow,
  sourceDetailUrl,
} from './SonglistDetail/SonglistRowActions';
import type { SongItem } from './SonglistDetail/SonglistTypes';
import type { ShareResult } from '../service/ShareService';
import { getStorageService } from '../core/interfaces/IStorageService';
import { isBuiltinSourceId } from '../core/music/MusicSourceRegistry';
import { stateEvent } from '../event/StateEvent';
import { SongListView } from './Home/SongListView';
import { LeaderboardView } from './Home/LeaderboardView';
import { MylistView } from './Home/MylistView';
import { navigationService, navigateTo, RouteName } from '../service/NavigationService';
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
import { t, tf, sourceLabel } from '../service/LocalizationService';
import { settingsService } from '../service/SettingsService';
import {
  addHistoryWord,
  clearHistoryList,
  getSearchHistory,
  removeHistoryWord,
  type SonglistSearchResult,
} from '../core/search/search';
import { type NavigationParams } from '../service/NavigationService';
import { on, EventTypes } from '../service/EventBus';

/** 搜索输入框的焦点键（供 FocusController 定位，浮层出现时自动聚焦） */
const SEARCH_INPUT_KEY: string = 'homeSearchInput';
/** 首页「上次选中的音源」存储键（与「设置 → 默认搜索源」分开，避免临时切换改写设置） */
const HOME_SOURCE_KEY: string = 'home.lastSource';
/** 首页「上次停留的 Tab」存储键 */
const HOME_TAB_KEY: string = 'home.lastTab';

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
  /** 一多：窗口宽度（vp），大屏内容列居中（搜索浮层等） */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
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
      // 事件里的载荷是序列化字符串：脏数据不能把事件回调炸掉（回调抛错无人接）
      try {
        const musicInfo: MusicInfoType = JSON.parse(musicInfoStr);
        this.musicName = musicInfo.name || '';
        this.singer = musicInfo.singer || '';
        this.pic = musicInfo.pic || '';
      } catch (err) {
        hilog.warn(0x0001, 'HomePage', 'playerMusicInfoChanged parse failed: %{public}s', JSON.stringify(err));
      }
    };
    stateEvent.on('playStateChanged', this.onPlayStateChanged);
    stateEvent.on('playerMusicInfoChanged', this.onPlayerMusicInfoChanged);

    this.globalSearchStripActions.onMagnifierClick = (): void => {
      this.openSearch();
    };
    this.globalSearchStripActions.onSubmit = (): void => {
      void this.submitGlobalSearchFromStrip();
    };
    // 搜索条右端麦克风：进听歌识曲页（点击被麦克风按钮自身消费，不会触发整条跳转）
    this.globalSearchStripActions.onMicClick = (): void => {
      navigateTo(RouteName.RECOGNIZE);
    };
    // 搜索条只负责「点开浮层」，条内文字变化不需要处理（SearchStripActions 默认空实现）

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
    // 首页顶部选过的音源优先（设置里的「默认搜索源」只在还没选过时生效）
    void this.restoreLastSource();
    // 上次停留的 Tab 也接着用，避免每次都回到「歌单」
    void this.restoreLastTab();
  }

  /**
   * 恢复用户上次在首页选的音源。
   *
   * 与「设置 → 搜索 → 默认搜索源」分开存：设置项是用户显式声明的默认值，
   * 不该被首页的一次临时切换静默改写；这里单独记「上次看的源」。
   */
  private async restoreLastSource(): Promise<void> {
    try {
      const saved: string = await getStorageService().getString(HOME_SOURCE_KEY, '');
      if (isBuiltinSourceId(saved)) {
        this.currentSource = saved;
      }
    } catch (err) {
      hilog.warn(0x0001, 'HomePage', 'restoreLastSource failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 记住首页选中的音源（失败只告警：不影响本次浏览） */
  private persistLastSource(id: string): void {
    getStorageService().setString(HOME_SOURCE_KEY, id).catch((err: Error) => {
      hilog.warn(0x0001, 'HomePage', 'persistLastSource failed: %{public}s', err.message);
    });
  }

  /**
   * 恢复上次停留的首页 Tab（歌单 / 排行榜 / 下载 / 我的）。
   * 与「设置 → 启动页」不冲突：启动页决定是进首页还是进播放页，这里只决定首页落在哪个 Tab。
   */
  private async restoreLastTab(): Promise<void> {
    try {
      const saved: number = await getStorageService().getNumber(HOME_TAB_KEY, 0);
      const tabCount: number = this.getBottomTabs().length;
      if (saved >= 0 && saved < tabCount && saved !== this.currentTab) {
        this.currentTab = saved;
      }
    } catch (err) {
      hilog.warn(0x0001, 'HomePage', 'restoreLastTab failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 记住当前 Tab（失败只告警） */
  private persistLastTab(index: number): void {
    getStorageService().setNumber(HOME_TAB_KEY, index).catch((err: Error) => {
      hilog.warn(0x0001, 'HomePage', 'persistLastTab failed: %{public}s', err.message);
    });
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

  /** 长按删除单条搜索历史：按单词定位下标后交给核心层（下标会随之变化） */
  removeSearchHistoryWord(word: string): void {
    const index: number = this.searchHistory.indexOf(word);
    if (index < 0) {
      return;
    }
    this.searchHistory = this.searchHistory.filter((item: string): boolean => item !== word);
    removeHistoryWord(index).catch((err: Error) => {
      hilog.warn(0x0001, 'HomePage', 'removeHistoryWord failed: %{public}s', err.message);
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
    this.persistLastSource(id);
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
        this.SearchFieldRow()

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
            onRemoveHistory: (word: string): void => this.removeSearchHistoryWord(word),
          })
        } else if (this.searchViewState === SearchViewState.RESULT) {
          this.SearchResultContent()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(DesignTokens.pageBg(this.theme))
      // 大屏内容列居中：搜索框与结果列表都不该横跨整屏（背景仍通栏）
      .padding({
        left: Breakpoints.contentInset(this.windowWidthVp),
        right: Breakpoints.contentInset(this.windowWidthVp),
      })
    }
  }

  /** 搜索浮层顶部：输入框（出现即自动聚焦）+ 取消按钮 */
  @Builder
  SearchFieldRow() {
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
          .accessibilityText(t('search_placeholder'))
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
        .accessibilityText(t('cancel'))
        .onClick(() => {
          this.closeSearch();
        })
    }
    .width('100%')
    .padding({ left: DesignTokens.spaceGutter(), right: DesignTokens.spaceGutter() - 8, top: 10, bottom: 6 })
    .alignItems(VerticalAlign.Center)
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
          onLongPress: (index: number): void => {
            if (index >= 0 && index < this.searchResults.length) {
              void this.openSearchResultMenu(this.searchResults[index]);
            }
          },
        })
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  /** 搜索结果行 → 队列歌曲（取到播放地址后再回填 url / duration） */
  /**
   * 长按搜索结果 → 与歌单详情同一套单曲菜单。
   *
   * 搜索结果以前只能点一下播放，想「下一首播放 / 收藏 / 下载 / 分享 / 不喜欢」得先点进
   * 歌单详情才行。这里复用 SonglistMenus + SonglistRowActions，菜单文案与动作实现都只有一份。
   */
  private async openSearchResultMenu(item: SearchResultItem): Promise<void> {
    const row: SongItem = {
      id: item.id,
      name: item.name,
      singer: item.singer,
      album: item.album,
      duration: item.duration > 0 ? item.duration : 0,
      source: item.source,
      pic: item.pic ?? '',
      albumId: item.albumId,
      songmid: item.songmid,
      strMediaMid: item.strMediaMid,
      hash: item.hash,
      copyrightId: item.copyrightId,
      isPlaying: false,
    };
    await showSongItemMenu(row, {
      onPlayLater: (target: SongItem): void => {
        playerService.insertNext(songRowToQueueItem(target));
        appToast(tf('toast_play_later_added', [target.name]));
      },
      onAddToList: (target: SongItem): void => {
        void this.addSearchRowToDefaultList(target);
      },
      onDownload: (target: SongItem): void => {
        void this.downloadSearchRow(target);
      },
      onShare: (target: SongItem): void => {
        void this.shareSearchRow(target);
      },
      onDislike: (target: SongItem): void => {
        void this.dislikeSearchRow(target);
      },
      onSourceDetail: (target: SongItem): void => {
        if (!openInBrowser(this.hostContext(), sourceDetailUrl(target))) {
          appToast(t('toast_operation_failed'));
        }
      },
      onViewArtist: (target: SongItem): void => {
        this.startSearchFromMenu(target.singer);
      },
      onViewAlbum: (target: SongItem): void => {
        this.startSearchFromMenu(target.album);
      },
    }, {
      // 搜索结果没有「所属列表」，因此不提供改位置/移动/多选
      canEditPosition: false,
      canMoveToList: false,
    });
  }

  /** 收藏到默认歌单（我喜欢） */
  private async addSearchRowToDefaultList(row: SongItem): Promise<void> {
    const error: string = await addRowToDefaultList(row);
    appToast(error.length === 0
      ? tf('toast_added_to_default', [row.name]) : t('toast_operation_failed'));
  }

  /** 下载单曲 */
  private async downloadSearchRow(row: SongItem): Promise<void> {
    const error: string = await downloadRow(row);
    appToast(error.length === 0
      ? tf('toast_download_start_song', [row.name]) : t('toast_operation_failed'));
  }

  /** 分享单曲（按设置走系统分享，失败回退剪贴板） */
  private async shareSearchRow(row: SongItem): Promise<void> {
    const result: ShareResult = await shareSongRow(this.hostContext(), row, sourceLabel(row.source));
    if (result === 'clipboard') {
      appToast(t('toast_share_copy'));
    } else if (result === 'failed') {
      appToast(t('toast_operation_failed'));
    }
  }

  /** 不喜欢（歌曲 / 歌手 / 歌名三种粒度） */
  private async dislikeSearchRow(row: SongItem): Promise<void> {
    const picked: number = await appActionMenu(t('dislike_title'), [
      t('dislike_song'),
      t('dislike_singer'),
      t('dislike_name'),
    ]);
    if (picked < 0) {
      return;
    }
    try {
      const count: number = await addRowToDislike(row, picked);
      appToast(tf('dislike_added', [count.toString()]));
    } catch (err) {
      hilog.warn(0x0001, 'HomePage', 'dislike failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_operation_failed'));
    }
  }

  /** 菜单里的「查看歌手 / 专辑」：沿用详情页做法，直接发起一次搜索 */
  private startSearchFromMenu(keyword: string): void {
    if (!keyword || keyword.length === 0) {
      appToast(t('toast_operation_failed'));
      return;
    }
    this.searchText = keyword;
    void this.doSearch();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 搜索结果行 → 队列歌曲（取到播放地址后再回填 url / duration） */
  private searchItemToSongInfo(item: SearchResultItem, url: string, duration: number): SongInfo {
    return {
      id: item.id,
      songmid: item.songmid || item.id,
      url,
      title: item.name,
      artist: item.singer,
      album: item.album,
      artwork: item.pic || null,
      duration,
      source: item.source,
      hash: item.hash,
      strMediaMid: item.strMediaMid,
      songId: item.songId,
      albumId: item.albumId,
      copyrightId: item.copyrightId,
    };
  }

  /** 搜索结果行 → 音乐信息（用于取播放地址、歌词等） */
  private searchItemToMusicInfo(item: SearchResultItem): MusicInfo {
    const src = item.source as MusicSource;
    return {
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
  }

  /**
   * 把当前搜索结果整列设为临时播放队列（不写入用户歌单），并定位到被点击的那首。
   * 这样「下一首/上一首」可以在结果里连续播放，且不会静默改动用户数据。
   */
  private syncSearchQueueAsPlaylist(item: SearchResultItem): void {
    if (this.searchResults.length <= 1) {
      return;
    }
    const queue: SongInfo[] = [];
    let startIndex = 0;
    for (let i = 0; i < this.searchResults.length; i++) {
      const r = this.searchResults[i];
      if (r.id === item.id && r.source === item.source) {
        startIndex = i;
      }
      queue.push(this.searchItemToSongInfo(r, '', r.duration > 0 ? r.duration : 0));
    }
    playerService.setPlayList(queue, startIndex);
  }

  /** 搜索overlay内：点击搜索结果行播放 */
  async playSearchResult(item: SearchResultItem): Promise<void> {
    try {
      this.syncSearchQueueAsPlaylist(item);
      const musicInfo: MusicInfo = this.searchItemToMusicInfo(item);
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
      const songInfo: SongInfo = this.searchItemToSongInfo(item, url, durSec);
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
        this.persistLastTab(index);
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
          // 内容区必须用 layoutWeight 占剩余高度，不能直接用 MainPane
          // （MainPane 自身是 height('100%')，会和底栏一起把底栏挤出屏幕）
          Column() {
            this.MainPane()
          }
          .layoutWeight(1)
          .width('100%')

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
  }
}
