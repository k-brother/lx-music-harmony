import { t } from '../../service/LocalizationService';
import { formatPlayCount } from '../../utils/FormatTools';
// 排行榜视图：纵向分组卡片 + 榜单内预览曲目 + 展开/收起与进入完整榜单
// 信息架构：一屏浏览多个榜；弱打扰预览 3 条；展开看更多；右侧箭头进二级页

import { getBoardsList, getLeaderboardDetailReliable } from '../../core/leaderboard';
import type { BoardItem, BoardSource, BoardMusicItem } from '../../store/leaderboard/LeaderboardStoreState';
import { navigationService, RouteName } from '../../service/NavigationService';
import { playerService, SongInfo } from '../../service/PlayerService';
import { getMusicUrl } from '../../core/music/MusicFeatureEntry';
import type { MusicInfo } from '../../types/MusicTypes';
import hilog from '@ohos.hilog';
import { DesignTokens } from '../../theme/DesignTokens';
import { CoverPalette } from '../../theme/CoverPalette';
import { DeferredScrollToTop } from '../../utils/ScrollTools';
import { Breakpoints } from '../../theme/Breakpoints';
import { SearchStrip, SearchStripActions } from '../../components/common/SearchStrip';
import { FilterPillBar, type FilterPillOption } from './Home/FilterPillBar';
import { RefreshContainer } from '../../components/ui/RefreshContainer';
import { StateView } from '../../components/ui/StateView';
import { SkeletonBoards } from './Leaderboard/SkeletonBoards';
import { LeaderboardSearchOverlay } from './Leaderboard/LeaderboardSearchOverlay';
import { ChartCard } from './Leaderboard/ChartCard';
import { hapticService } from '../../service/HapticService';

const PREVIEW_COLLAPSED = 3;
const PREVIEW_EXPANDED = 8;
/** 预览请求超时；与 HttpClient 默认 readTimeout 对齐并略放宽 */
const PREVIEW_REQUEST_TIMEOUT_MS = 20000;
/** 每批并发预览数：酷我/酷狗等源并发过高易空包，略保守 */
const PREVIEW_CONCURRENCY = 2;

/** 单个榜单卡片状态（预览与展开） */
/** 卡片试听列表的加载态（idle → loading → ready/err） */
type CardLoadState = 'idle' | 'loading' | 'ready' | 'err';

interface LeaderboardCardState {
  board: BoardItem;
  topSongs: BoardMusicItem[];
  /** 当前展示的预览行（随展开收起从 topSongs 切片，供 ForEach 稳定渲染） */
  displayList: BoardMusicItem[];
  loadState: CardLoadState;
  expanded: boolean;
}

interface LeaderboardFilterOption {
  id: string;
  name: string;
}

@Component
export struct LeaderboardView {
  @StorageProp('theme') theme: string = 'light';
  /** 一多：窗口宽度（vp），大屏内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
  @StorageProp('language') language: string = 'zh-CN';
  // 语言变化时重建筛选文案：这些文案缓存在 @State 里，不重建会残留旧语言
  @StorageProp('langVersion') @Watch('onLanguageChanged') langVersion: number = 0;
  @Prop sourceId: string = 'kw';
  @Prop @Watch("onReCreateKeyChange") reCreateKey: number = 0;
  @State boardList: BoardItem[] = [];
  @State isLoading: boolean = false;
  /** 下拉刷新中（榜单列表重新拉取） */
  @State isRefreshing: boolean = false;

  /** 下拉刷新：重新拉取当前音源的榜单列表 */
  private reloadBoards(): void {
    hapticService.selection();
    hilog.info(0x0001, 'LeaderboardView', 'Pull-to-refresh: reload boards, source=%{public}s', this.sourceId);
    this.isRefreshing = true;
    this.loadBoardList().then((): void => {
      this.isRefreshing = false;
    }).catch((): void => {
      this.isRefreshing = false;
    });
  }
  @State searchText: string = '';
  @State overlaySearchText: string = '';
  @State searchOverlayVisible: boolean = false;
  @State filteredBoardList: BoardItem[] = [];
  @State cardStates: LeaderboardCardState[] = [];
  @State categoryFilterOptions: LeaderboardFilterOption[] = [{ id: 'all', name: t('filter_all') }];
  @State selectedCategoryFilterId: string = 'all';
  @State boardFilterOptions: LeaderboardFilterOption[] = [{ id: 'all', name: t('filter_all_board') }];
  @State selectedBoardFilterId: string = 'all';
  @State isFilterPinned: boolean = false;
  // 请求版本控制，防止竞态
  private requestEpoch: number = 0;
  /** 榜单卡片集重建代数；与 requestEpoch 解耦，专门丢弃已过期的预览异步回调 */
  private previewGeneration: number = 0;

  private leaderboardScroller: Scroller = new Scroller();
  private readonly filterPinThreshold: number = DesignTokens.heightSearchField() + DesignTokens.spaceUnit() * 2;
  private readonly searchStripHostHeight: number = DesignTokens.heightSearchField() + DesignTokens.spaceUnit() * 2;
  private readonly filterBarPinnedHeight: number = 76;
  private readonly minPinCards: number = 2;
  /** 切源/切筛选后「等一帧再回顶部」（实现在 utils/ScrollTools） */
  private scrollTopDefer: DeferredScrollToTop = new DeferredScrollToTop();
  @State coverInteractionUnlocked: boolean = false;
  private readonly startupPreviewLimit: number = 1;

  private scrollToTopSoon(): void {
    this.scrollTopDefer.schedule(this.leaderboardScroller);
  }

  private leaderboardSearchActions: SearchStripActions = new SearchStripActions();
  private leaderboardOverlaySearchActions: SearchStripActions = new SearchStripActions();

  aboutToAppear() {
    this.scrollTopDefer.start();
    this.coverInteractionUnlocked = true;
    this.leaderboardSearchActions.onTextChange = (_t: string): void => {};
    this.leaderboardSearchActions.onMagnifierClick = (): void => {
      this.openSearchOverlay();
    };
    this.leaderboardSearchActions.onSubmit = (): void => {
      this.openSearchOverlay();
    };

    this.leaderboardOverlaySearchActions.onTextChange = (t: string): void => {
      this.onSearchChange(t);
    };
    this.leaderboardOverlaySearchActions.onMagnifierClick = (): void => {};
    this.leaderboardOverlaySearchActions.onSubmit = (): void => {
      this.onSearchChange(this.overlaySearchText);
    };
    this.scrollToTopSoon();
    void this.loadBoardList();
  }

  aboutToDisappear() {
    this.scrollTopDefer.stop();
  }


  // reCreateKey 变化时重新加载（响应音乐源切换）
  // 注意：@Watch 回调参数为被监听属性名 (string)，不是属性新值，请读 this.reCreateKey
  onReCreateKeyChange(_changedPropertyName?: string): void {
    const epoch = this.reCreateKey;
    hilog.info(0x0001, 'LeaderboardView', 'reCreateKey changed to %{public}d, reloading...', epoch);
    this.isFilterPinned = false;
    this.coverInteractionUnlocked = true;
    this.scrollToTopSoon();
    void this.loadBoardList();
  }

  pageBg(): string {
    return DesignTokens.pageBg(this.theme);
  }

  cardBorder(): string {
    return DesignTokens.cardBorder(this.theme);
  }

  primaryText(): string {
    return DesignTokens.labelPrimary(this.theme);
  }

  tertiaryText(): string {
    return DesignTokens.labelTertiary(this.theme);
  }

  /** 前三名配色：与榜单卡片 ChartCard.rankColor 一致（金/银/铜语义走 token） */
  rankColor(rank: number): string {
    if (rank === 1) {
      return DesignTokens.accent();
    }
    if (rank === 2) {
      return DesignTokens.warning();
    }
    if (rank === 3) {
      return DesignTokens.info();
    }
    return this.tertiaryText();
  }

  async loadBoardList() {
    // 不在 isLoading 时早退：否则切源时若前一次仍在 await，新一次被跳过且 finally 可能永远不置回 false。
    const currentEpoch = ++this.requestEpoch;
    this.isLoading = true;
    hilog.info(0x0001, 'LeaderboardView', 'Loading boards for source: %{public}s, epoch: %{public}d', this.sourceId, currentEpoch);
    try {
      const boards = await getBoardsList(this.sourceId as BoardSource);
      // 检查版本是否过期（用户可能已切换到其他源）
      if (currentEpoch !== this.requestEpoch) {
        hilog.info(0x0001, 'LeaderboardView', 'Stale request ignored, current epoch: %{public}d', this.requestEpoch);
        return;
      }
      this.boardList = boards;
      this.isFilterPinned = false;
      this.rebuildCategoryFilterOptions();
      this.rebuildBoardFilterOptions();
      this.applyBoardFilters();
    } catch (err) {
      // 检查版本是否过期
      if (currentEpoch !== this.requestEpoch) {
        return;
      }
      hilog.error(0x0001, 'LeaderboardView', 'Failed to load boards: %{public}s', JSON.stringify(err));
      this.boardList = [];
      this.filteredBoardList = [];
      this.cardStates = [];
      this.categoryFilterOptions = [{ id: 'all', name: t('filter_all') }];
      this.selectedCategoryFilterId = 'all';
      this.boardFilterOptions = [{ id: 'all', name: t('filter_all_board') }];
      this.selectedBoardFilterId = 'all';
    } finally {
      if (currentEpoch === this.requestEpoch) {
        this.isLoading = false;
      }
    }
  }

  private getCategoryLabelById(id: string): string {
    if (id === 'official') {
      return t('category_official');
    }
    if (id === 'cn') {
      return t('category_chinese');
    }
    if (id === 'west') {
      return t('category_western');
    }
    if (id === 'jpkr') {
      return t('category_jk');
    }
    if (id === 'feature') {
      return t('category_feature');
    }
    return t('category_all');
  }

  private detectBoardCategoryId(boardName: string): string {
    const n = boardName.toLowerCase();
    if (n.includes('欧美') || n.includes('billboard') || n.includes('英国') || n.includes('space shower') || n.includes('beatport')) {
      return 'west';
    }
    if (n.includes('日本') || n.includes('日语') || n.includes('韩国') || n.includes('韩语') || n.includes('melon')) {
      return 'jpkr';
    }
    if (n.includes('华语') || n.includes('内地') || n.includes('粤语') || n.includes('国风') || n.includes('港台') || n.includes('台湾') || n.includes('闽南')) {
      return 'cn';
    }
    if (
      n.includes('抖音') || n.includes('快手') || n.includes('dj') || n.includes('电音') || n.includes('说唱') ||
      n.includes('影视') || n.includes('动漫') || n.includes('游戏') || n.includes('校园') || n.includes('网红') ||
      n.includes('民谣') || n.includes('摇滚') || n.includes('爵士') || n.includes('古典') || n.includes('纯音乐') ||
      n.includes('伤感') || n.includes('雷达') || n.includes('听歌识曲')
    ) {
      return 'feature';
    }
    return 'official';
  }

  private rebuildCategoryFilterOptions(): void {
    const order: string[] = ['official', 'cn', 'west', 'jpkr', 'feature'];
    const exists: Set<string> = new Set();
    for (let i = 0; i < this.boardList.length; i++) {
      const b = this.boardList[i];
      exists.add(this.detectBoardCategoryId(b.name || ''));
    }
    const options: LeaderboardFilterOption[] = [{ id: 'all', name: t('filter_all') }];
    for (let j = 0; j < order.length; j++) {
      const id = order[j];
      if (exists.has(id)) {
        options.push({ id, name: this.getCategoryLabelById(id) });
      }
    }
    this.categoryFilterOptions = options;
    const keep = options.some((o: LeaderboardFilterOption) => o.id === this.selectedCategoryFilterId);
    if (!keep) {
      this.selectedCategoryFilterId = 'all';
    }
  }

  private rebuildBoardFilterOptions(): void {
    const options: LeaderboardFilterOption[] = [{ id: 'all', name: t('filter_all_board') }];
    const maxCount = 40;
    for (let i = 0; i < this.boardList.length && options.length < maxCount; i++) {
      const b = this.boardList[i];
      const cid = this.detectBoardCategoryId(b.name || '');
      if (this.selectedCategoryFilterId !== 'all' && cid !== this.selectedCategoryFilterId) {
        continue;
      }
      options.push({ id: b.id, name: b.name || t('board_item') });
    }
    this.boardFilterOptions = options;
    const keep = options.some((o: LeaderboardFilterOption) => o.id === this.selectedBoardFilterId);
    if (!keep) {
      this.selectedBoardFilterId = 'all';
    }
  }

  private applyBoardFilters(): void {
    const keyword = this.searchText.trim().toLowerCase();
    const out: BoardItem[] = [];
    for (let i = 0; i < this.boardList.length; i++) {
      const item = this.boardList[i];
      const cid = this.detectBoardCategoryId(item.name || '');
      if (this.selectedCategoryFilterId !== 'all' && cid !== this.selectedCategoryFilterId) {
        continue;
      }
      if (this.selectedBoardFilterId !== 'all' && item.id !== this.selectedBoardFilterId) {
        continue;
      }
      if (keyword.length > 0) {
        const name = item.name ? item.name.toLowerCase() : '';
        if (!name.includes(keyword)) {
          continue;
        }
      }
      out.push(item);
    }
    this.filteredBoardList = out;
    if (out.length < this.minPinCards && this.isFilterPinned) {
      this.isFilterPinned = false;
    }
    if (out.length < this.minPinCards) {
      this.scrollToTopSoon();
    }
    this.rebuildCardsAndLoadPreviews();
  }

  onCategoryFilterChange(filterId: string): void {
    if (this.selectedCategoryFilterId === filterId) {
      return;
    }
    this.isFilterPinned = false;
    this.scrollToTopSoon();
    this.selectedCategoryFilterId = filterId;
    this.selectedBoardFilterId = 'all';
    this.rebuildBoardFilterOptions();
    this.applyBoardFilters();
  }

  onBoardFilterChange(filterId: string): void {
    if (this.selectedBoardFilterId === filterId) {
      return;
    }
    this.isFilterPinned = false;
    this.scrollToTopSoon();
    this.selectedBoardFilterId = filterId;
    this.applyBoardFilters();
  }

  private syncFilterPinnedByOffset(): void {
    const y = this.leaderboardScroller.currentOffset().yOffset;
    if (y < 0) {
      this.scrollToTopSoon();
      if (this.isFilterPinned) {
        this.isFilterPinned = false;
      }
      return;
    }
    if (this.filteredBoardList.length < this.minPinCards) {
      if (this.isFilterPinned) {
        this.isFilterPinned = false;
      }
      return;
    }
    const pinLine = this.filterPinThreshold;
    if (!this.isFilterPinned && y >= pinLine) {
      this.isFilterPinned = true;
      return;
    }
    if (this.isFilterPinned && y <= pinLine - 18) {
      this.isFilterPinned = false;
    }
  }

  rebuildCardsAndLoadPreviews(): void {
    this.previewGeneration++;
    const list = this.filteredBoardList;
    const next: LeaderboardCardState[] = [];
    for (let i = 0; i < list.length; i++) {
      const b = list[i];
      const row: LeaderboardCardState = {
        board: b,
        topSongs: [],
        displayList: [],
        loadState: 'idle',
        expanded: false,
      };
      next.push(row);
    }
    this.cardStates = next;
  }

  onSearchChange(text: string) {
    this.searchText = text;
    this.overlaySearchText = text;
    this.isFilterPinned = false;
    this.scrollToTopSoon();
    this.applyBoardFilters();
  }

  openSearchOverlay(): void {
    this.searchOverlayVisible = true;
    this.overlaySearchText = this.searchText;
    this.onSearchChange(this.overlaySearchText);
  }

  closeSearchOverlay(): void {
    this.searchOverlayVisible = false;
  }

  /** 兼容历史错误 id（如 `kg__kg__8888`）：反复去掉第一个 `__` 前缀段，直到只剩业务 id */
  private unwrapBangFromRowId(rowId: string): string {
    let s = rowId;
    let ix = s.indexOf('__');
    while (ix >= 0) {
      s = s.substring(ix + 2);
      ix = s.indexOf('__');
    }
    return s;
  }

  private normalizePicUrl(url: string): string {
    if (url.length === 0) {
      return '';
    }
    if (url.startsWith('http://')) {
      return `https://${url.substring(7)}`;
    }
    return url;
  }

  async loadPreviewForIndex(i: number): Promise<void> {
    if (i < 0 || i >= this.cardStates.length) {
      return;
    }
    await this.loadPreviewForBoardId(this.cardStates[i].board.id);
  }

  private async loadPreviewForBoardId(boardId: string): Promise<void> {
    const startedPreviewGen = this.previewGeneration;
    const idx = this.indexOfCard(boardId);
    if (idx < 0 || this.isStalePreview(startedPreviewGen)) {
      return;
    }
    const snapshot = this.cardStates[idx];
    if (snapshot.loadState === 'loading' || snapshot.loadState === 'ready') {
      return;
    }

    this.patchCard(idx, snapshot.board, 'loading', snapshot.topSongs, snapshot.displayList, snapshot.expanded);

    try {
      // 超时 + 空包重试策略收在 core/leaderboard.getLeaderboardDetailReliable 里
      const bang = this.unwrapBangFromRowId(snapshot.board.id);
      const detail = await getLeaderboardDetailReliable(snapshot.board.source, bang, 1);
      const songs = detail?.list ? detail.list.slice(0, PREVIEW_EXPANDED) : [];
      this.applyPreviewReady(boardId, songs, startedPreviewGen, snapshot.board);
    } catch (e) {
      this.applyPreviewError(boardId, startedPreviewGen, snapshot.board);
    }
  }

  /** 榜单在列表中的下标（列表被重建后按 id 重新定位） */
  private indexOfCard(boardId: string): number {
    return this.cardStates.findIndex((c: LeaderboardCardState) => c.board.id === boardId);
  }

  /** 预览请求是否已过期（换源/重建会让 generation 递增） */
  private isStalePreview(generation: number): boolean {
    return generation !== this.previewGeneration;
  }

  /** 按下标替换一张卡片的状态（ArkUI 需要整数组重新赋值才会刷新） */
  private patchCard(
    index: number, board: BoardItem, loadState: CardLoadState,
    topSongs: BoardMusicItem[], displayList: BoardMusicItem[], expanded: boolean
  ): void {
    if (index < 0 || index >= this.cardStates.length) {
      return;
    }
    const slice = this.cardStates.slice();
    slice[index] = {
      board: board,
      topSongs: topSongs,
      displayList: displayList,
      loadState: loadState,
      expanded: expanded,
    };
    this.cardStates = slice;
  }

  /** 试听列表拉取成功：写回列表（只展示展开/收起对应的条数） */
  private applyPreviewReady(
    boardId: string, songs: BoardMusicItem[], generation: number, board: BoardItem
  ): void {
    if (this.isStalePreview(generation)) {
      return;
    }
    const idx = this.indexOfCard(boardId);
    if (idx < 0) {
      hilog.warn(0x0001, 'LeaderboardView', 'preview stale: board %{public}s not in list (gen)', boardId);
      return;
    }
    if (this.cardStates[idx].loadState !== 'loading') {
      return;
    }
    const expanded = this.cardStates[idx].expanded;
    const visible = expanded ? PREVIEW_EXPANDED : PREVIEW_COLLAPSED;
    const display: BoardMusicItem[] = [];
    for (let k = 0; k < Math.min(visible, songs.length); k++) {
      display.push(songs[k]);
    }
    this.patchCard(idx, this.cardStates[idx].board, 'ready', songs, display, expanded);
    hilog.info(0x0001, 'LeaderboardView', 'preview ok %{public}s %{public}s songs=%{public}d gen=%{public}d',
      board.source, board.name, songs.length, generation);
  }

  /** 试听列表拉取失败：标记为可重试的错误态 */
  private applyPreviewError(boardId: string, generation: number, board: BoardItem): void {
    if (this.isStalePreview(generation)) {
      return;
    }
    const idx = this.indexOfCard(boardId);
    if (idx < 0 || this.cardStates[idx].loadState !== 'loading') {
      return;
    }
    this.patchCard(idx, this.cardStates[idx].board, 'err', [], [], this.cardStates[idx].expanded);
    hilog.warn(0x0001, 'LeaderboardView', 'preview err %{public}s %{public}s', board.source, board.name);
  }


  /** 列表懒渲染时：项进入可视区域再补一次 idle 预览（与顺序预拉互补） */
  private ensurePreviewAtIndex(index: number): void {
    if (index < 0 || index >= this.cardStates.length) {
      return;
    }
    const st = this.cardStates[index];
    if (st.loadState === 'idle') {
      void this.loadPreviewForBoardId(st.board.id);
    }
  }

  toggleExpand(index: number): void {
    if (index < 0 || index >= this.cardStates.length) {
      return;
    }
    const slice = this.cardStates.slice();
    const cur = slice[index];
    const newExp = !cur.expanded;

    // 只有展开时才加载预览数据
    if (newExp && cur.loadState === 'idle') {
      // 先展开 UI，再由 loadPreview 内部置为 loading（避免已是 loading 时被入口 guard 直接 return）
      slice[index] = {
        board: cur.board,
        topSongs: cur.topSongs,
        displayList: cur.displayList,
        loadState: 'idle',
        expanded: newExp,
      };
      this.cardStates = slice;
      void this.loadPreviewForBoardId(cur.board.id);
    } else {
      const vis = newExp ? PREVIEW_EXPANDED : PREVIEW_COLLAPSED;
      const disp: BoardMusicItem[] = [];
      for (let k = 0; k < Math.min(vis, cur.topSongs.length); k++) {
        disp.push(cur.topSongs[k]);
      }
      slice[index] = {
        board: cur.board,
        topSongs: cur.topSongs,
        displayList: disp,
        loadState: cur.loadState,
        expanded: newExp,
      };
      this.cardStates = slice;
    }
  }

  async playPreviewSong(song: BoardMusicItem): Promise<void> {
    try {
      const src = song.source as 'kw' | 'kg' | 'tx' | 'wy' | 'mg';
      const musicInfo: MusicInfo = {
        id: song.id,
        name: song.name || '',
        singer: song.singer || '',
        source: src,
        songmid: song.id,
        interval: null,
        img: song.pic || null,
        lrc: null,
        albumName: song.album || '',
        album: song.album || '',
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
        return;
      }
      const songInfo: SongInfo = {
        id: song.id,
        url,
        title: song.name || '',
        artist: song.singer || '',
        album: song.album || '',
        artwork: song.pic || null,
        duration: song.duration || 0,
        source: song.source,
      };
      await playerService.playFromSelection(songInfo, url, song.duration || 0);
    } catch (e) {
      hilog.warn(0x0001, 'LeaderboardView', 'playPreviewSong failed: %{public}s', (e as Error)?.message);
    }
  }

  navigateToBoardDetail(board: BoardItem): void {
    hilog.info(0x0001, 'LeaderboardView', 'Navigate to board: %{public}s', board.name);
    const canonicalBoardId = `${board.source}__${this.unwrapBangFromRowId(board.id)}`;
    navigationService.navigateTo(RouteName.BOARD_DETAIL, {
      boardId: canonicalBoardId,
      boardName: board.name,
      boardSource: board.source,
    });
  }

  /** 播放量格式统一在 utils/FormatTools（单位文案由调用方注入，保持纯函数） */
  formatPlayCount(count: number): string {
    return formatPlayCount(count, t('ten_thousand_unit'), t('billion_unit'));
  }

  /**
   * 榜单封面：只用榜单自己的图。
   *
   * 之前拿「第一首歌的封面」兜底（真机截图里流行指数榜和热歌榜都是同一张专辑图），
   * 不同榜单看起来一模一样、还会让人误以为是同一张榜 —— 那是误导，不是封面。
   * 没有榜单图时返回空，交给下方按榜单 id 生成的渐变占位块（每个榜颜色不同）。
   */
  resolveCardCover(card: LeaderboardCardState): string {
    if (card.board.pic && card.board.pic.length > 0) {
      return this.normalizePicUrl(card.board.pic);
    }
    return '';
  }


  /** 卡片渐变占位色（按榜单 id 稳定取色，色板与算法在 theme/CoverPalette） */
  placeholderPair(index: number): string[] {
    if (index < 0 || index >= this.cardStates.length) {
      return CoverPalette.defaultPair();
    }
    const card = this.cardStates[index];
    return CoverPalette.pairFor(`${card.board.source}__${card.board.id}`);
  }

  /** 试听加载失败后的重试：回到 idle 再拉一次 */
  retryPreview(index: number): void {
    const slice = this.cardStates.slice();
    if (index < 0 || index >= slice.length) {
      return;
    }
    const cur = slice[index];
    slice[index] = {
      board: cur.board,
      topSongs: [],
      displayList: [],
      loadState: 'idle',
      expanded: cur.expanded,
    };
    this.cardStates = slice;
    void this.loadPreviewForIndex(index);
  }

  /** 按索引读封面，供列表项 build 直接订阅 cardStates，避免 @Builder 传入整卡快照不刷新 */
  resolveCardCoverAt(index: number): string {
    if (index < 0 || index >= this.cardStates.length) {
      return '';
    }
    return this.resolveCardCover(this.cardStates[index]);
  }

  /** 语言切换后刷新缓存文案（数据沿用，只重建 label） */
  private onLanguageChanged(): void {
    this.rebuildCategoryFilterOptions();
    this.rebuildBoardFilterOptions();
  }

  /** 分类筛选 -> 通用胶囊数据 */
  private getCategoryPills(): FilterPillOption[] {
    const pills: FilterPillOption[] = [];
    for (const opt of this.categoryFilterOptions) {
      pills.push({ id: opt.id, label: opt.name });
    }
    return pills;
  }

  /** 榜单筛选 -> 通用胶囊数据 */
  private getBoardPills(): FilterPillOption[] {
    const pills: FilterPillOption[] = [];
    for (const opt of this.boardFilterOptions) {
      pills.push({ id: opt.id, label: opt.name });
    }
    return pills;
  }

  @Builder
  LeaderboardFilterBar() {
    Column() {
      // 分类筛选
      FilterPillBar({
        options: this.getCategoryPills(),
        activeId: this.selectedCategoryFilterId,
        topPadding: 4,
        bottomPadding: 2,
        onSelect: (id: string): void => {
          this.onCategoryFilterChange(id);
        },
      })

      // 榜单筛选
      FilterPillBar({
        options: this.getBoardPills(),
        activeId: this.selectedBoardFilterId,
        topPadding: 0,
        bottomPadding: 4,
        onSelect: (id: string): void => {
          this.onBoardFilterChange(id);
        },
      })
    }
    .width('100%')
    .height(this.filterBarPinnedHeight)
    .backgroundColor(DesignTokens.chromeBar(this.theme))
    .border({ width: { bottom: 0.33 }, color: DesignTokens.hairlineSeparator(this.theme) })
  }

  /** 榜单首屏骨架（与歌单页一致的加载观感） */
  /** 首屏骨架（与歌单页同一套骨架卡片） */
  @Builder
  LoadingSkeleton() {
    // 榜单首屏用骨架卡片占位，与歌单页保持一致
    SkeletonBoards()
  }

  /** 榜单区：搜索条/筛选条吸顶占位 + 卡片列表 + 空态 */
  @Builder
  BoardArea() {
    if (this.filteredBoardList.length < this.minPinCards) {
      Column() {
        SearchStrip({
          text: $searchText,
          placeholder: t('search_board_hint'),
          marginH: DesignTokens.spaceGutter(),
          marginV: DesignTokens.spaceUnit(),
          tapToOpenOnly: true,
          actions: this.leaderboardSearchActions,
        })
        this.LeaderboardFilterBar()
        if (this.cardStates.length === 0) {
          StateView({
            state: 'empty',
            iconRes: $r('sys.symbol.list_number'),
            message: this.boardList.length === 0 ? t('no_data') : t('search_no_result'),
          })
            .width('100%')
            .layoutWeight(1)
        } else {
          this.CardsColumn()
        }
      }
      .width('100%')
      .layoutWeight(1)
    } else {
      Column() {
        if (this.isFilterPinned) {
          this.LeaderboardFilterBar()
        }
        RefreshContainer({
          refreshing: $isRefreshing,
          onRefresh: (): void => {
            this.reloadBoards();
          },
        }) {
          Scroll(this.leaderboardScroller) {
            Column() {
            if (!this.isFilterPinned) {
              SearchStrip({
                text: $searchText,
                placeholder: t('search_board_hint'),
                marginH: DesignTokens.spaceGutter(),
                marginV: DesignTokens.spaceUnit(),
                tapToOpenOnly: true,
                actions: this.leaderboardSearchActions,
              })
            } else {
              Blank()
                .width('100%')
                .height(this.searchStripHostHeight)
            }
            if (!this.isFilterPinned) {
              this.LeaderboardFilterBar()
            } else {
              Blank()
                .width('100%')
                .height(this.filterBarPinnedHeight)
            }
            this.CardsColumn()
            }
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.None)
          .onDidScroll(() => {
            this.syncFilterPinnedByOffset();
          })
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
  }


  /** 榜单卡片列表（吸顶与未吸顶两种布局共用一份，含大屏内容列居中） */
  @Builder
  CardsColumn() {
    Column() {
      ForEach(this.cardStates, (card: LeaderboardCardState, index: number) => {
        ChartCard({
          cardId: this.cardStates[index].board.id,
          title: this.cardStates[index].board.name,
          playCount: this.cardStates[index].board.playCount ?? -1,
          coverUrl: this.resolveCardCoverAt(index),
          placeholderColors: this.placeholderPair(index),
          songs: this.cardStates[index].displayList,
          loadState: this.cardStates[index].loadState,
          expanded: this.cardStates[index].expanded,
          onToggleExpand: (): void => this.toggleExpand(index),
          onOpenBoard: (): void => this.navigateToBoardDetail(this.cardStates[index].board),
          onPlaySong: (song: BoardMusicItem): void => {
            void this.playPreviewSong(song);
          },
          onRetry: (): void => this.retryPreview(index),
        })
        .width('100%')
        // 大屏内容列居中（榜单卡片在 PC 上不拉满整屏）
        .padding({
          left: 12 + Breakpoints.contentInset(this.windowWidthVp),
          right: 12 + Breakpoints.contentInset(this.windowWidthVp),
        })
        .onAppear(() => {
          this.ensurePreviewAtIndex(index);
        })
      }, (card: LeaderboardCardState, index: number) => `${card.board.source}_${card.board.id}_${index}`)
    }
    .width('100%')
    .padding({ bottom: 16 })
  }


  build() {
    Stack() {
      Column() {
        if (this.isLoading) {
          this.LoadingSkeleton()
        } else {
          this.BoardArea()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(this.pageBg())

      if (this.searchOverlayVisible) {
        LeaderboardSearchOverlay({
          searchText: $overlaySearchText,
          boards: this.filteredBoardList,
          allEmpty: this.boardList.length === 0,
          searchActions: this.leaderboardOverlaySearchActions,
          onCancel: (): void => this.closeSearchOverlay(),
          onOpenBoard: (board: BoardItem): void => this.navigateToBoardDetail(board),
        })
      }
    }
    .width('100%')
    .height('100%')
  }


}
