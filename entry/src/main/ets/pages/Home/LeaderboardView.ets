import { t, tf } from '../../service/LocalizationService';
import { SkeletonGridItem } from '../../components/common/SkeletonView';
// 排行榜视图：纵向分组卡片 + 榜单内预览曲目 + 展开/收起与进入完整榜单
// 信息架构：一屏浏览多个榜；弱打扰预览 3 条；展开看更多；右侧箭头进二级页

import { getBoardsList, getLeaderboardDetail, type ListDetailInfo } from '../../core/leaderboard';
import type { BoardItem, BoardSource, BoardMusicItem } from '../../store/leaderboard/LeaderboardStoreState';
import { navigationService, RouteName } from '../../service/NavigationService';
import { playerService, SongInfo } from '../../service/PlayerService';
import { getMusicUrl } from '../../core/music/MusicFeatureEntry';
import type { MusicInfo } from '../../types/MusicTypes';
import hilog from '@ohos.hilog';
import { DesignTokens } from '../../theme/DesignTokens';
import { SearchStrip, SearchStripActions } from '../../components/common/SearchStrip';
import { FilterPillBar, type FilterPillOption } from './Home/FilterPillBar';
import { RefreshContainer } from '../../components/ui/RefreshContainer';
import { hapticService } from '../../service/HapticService';

const PREVIEW_COLLAPSED = 3;
const PREVIEW_EXPANDED = 8;
/** 预览请求超时；与 HttpClient 默认 readTimeout 对齐并略放宽 */
const PREVIEW_REQUEST_TIMEOUT_MS = 20000;
/** 每批并发预览数：酷我/酷狗等源并发过高易空包，略保守 */
const PREVIEW_CONCURRENCY = 2;

/** 单个榜单卡片状态（预览与展开） */
interface LeaderboardCardState {
  board: BoardItem;
  topSongs: BoardMusicItem[];
  /** 当前展示的预览行（随展开收起从 topSongs 切片，供 ForEach 稳定渲染） */
  displayList: BoardMusicItem[];
  loadState: 'idle' | 'loading' | 'ready' | 'err';
  expanded: boolean;
}

interface LeaderboardFilterOption {
  id: string;
  name: string;
}

@Component
export struct LeaderboardView {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
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
  private alive: boolean = false;
  private scrollTopTimer: number = -1;
  @State coverInteractionUnlocked: boolean = false;
  private readonly startupPreviewLimit: number = 1;

  private scrollToTopSoon(): void {
    if (!this.alive) {
      return;
    }
    if (this.scrollTopTimer >= 0) {
      clearTimeout(this.scrollTopTimer);
      this.scrollTopTimer = -1;
    }
    this.scrollTopTimer = setTimeout((): void => {
      if (!this.alive) {
        return;
      }
      try {
        this.leaderboardScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
      } catch (e) {
        hilog.warn(0x0001, 'LeaderboardView', 'scrollToTop failed: %{public}s', (e as Error)?.message);
      }
      this.scrollTopTimer = -1;
    }, 0);
  }

  private leaderboardSearchActions: SearchStripActions = new SearchStripActions();
  private leaderboardOverlaySearchActions: SearchStripActions = new SearchStripActions();

  aboutToAppear() {
    this.alive = true;
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
    this.alive = false;
    if (this.scrollTopTimer >= 0) {
      clearTimeout(this.scrollTopTimer);
      this.scrollTopTimer = -1;
    }
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

  cardBg(): string {
    return DesignTokens.card(this.theme);
  }

  cardBorder(): string {
    return DesignTokens.cardBorder(this.theme);
  }

  primaryText(): string {
    return DesignTokens.labelPrimary(this.theme);
  }

  secondaryText(): string {
    return DesignTokens.labelSecondary(this.theme);
  }

  tertiaryText(): string {
    return DesignTokens.labelTertiary(this.theme);
  }

  rankColor(rank: number): string {
    if (rank === 1) {
      return '#E63946';
    }
    if (rank === 2) {
      return '#FF6B35';
    }
    if (rank === 3) {
      return '#FF9500';
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
    let idx = this.cardStates.findIndex((c: LeaderboardCardState) => c.board.id === boardId);
    if (idx < 0) {
      return;
    }
    if (startedPreviewGen !== this.previewGeneration) {
      return;
    }
    const snapshot = this.cardStates[idx];
    if (snapshot.loadState === 'loading' || snapshot.loadState === 'ready') {
      return;
    }
    const board = snapshot.board;
    const loadingSlice = this.cardStates.slice();
    loadingSlice[idx] = {
      board,
      topSongs: snapshot.topSongs,
      displayList: snapshot.displayList,
      loadState: 'loading',
      expanded: snapshot.expanded,
    };
    this.cardStates = loadingSlice;
    try {
      const bang = this.unwrapBangFromRowId(board.id);
      const fetchDetail = (): Promise<ListDetailInfo | null> =>
        Promise.race<ListDetailInfo | null>([
          getLeaderboardDetail(board.source, bang, 1),
          new Promise<ListDetailInfo | null>((_, reject) => {
            setTimeout(() => reject(new Error('preview timeout')), PREVIEW_REQUEST_TIMEOUT_MS);
          }),
        ]);
      let detail = await fetchDetail();
      if (startedPreviewGen !== this.previewGeneration) {
        return;
      }
      if (!detail || !detail.list || detail.list.length === 0) {
        detail = await fetchDetail();
      }
      if (startedPreviewGen !== this.previewGeneration) {
        return;
      }
      // 酷狗 HTTP 等偶发首包空列表：短延迟后再拉一次，减少「有榜无预览」
      if (!detail || !detail.list || detail.list.length === 0) {
        await new Promise<void>((resolve: (v: void) => void) => {
          setTimeout((): void => {
            resolve();
          }, 450);
        });
        if (startedPreviewGen !== this.previewGeneration) {
          return;
        }
        detail = await fetchDetail();
      }
      if (startedPreviewGen !== this.previewGeneration) {
        return;
      }
      const songs = detail?.list ? detail.list.slice(0, PREVIEW_EXPANDED) : [];
      idx = this.cardStates.findIndex((c: LeaderboardCardState) => c.board.id === boardId);
      if (idx < 0) {
        hilog.warn(0x0001, 'LeaderboardView', 'preview stale: board %{public}s not in list (gen)', boardId);
        return;
      }
      if (startedPreviewGen !== this.previewGeneration) {
        return;
      }
      if (this.cardStates[idx].loadState !== 'loading') {
        return;
      }
      const doneSlice = this.cardStates.slice();
      const exp = doneSlice[idx].expanded;
      const vis = exp ? PREVIEW_EXPANDED : PREVIEW_COLLAPSED;
      const disp: BoardMusicItem[] = [];
      for (let k = 0; k < Math.min(vis, songs.length); k++) {
        disp.push(songs[k]);
      }
      doneSlice[idx] = {
        board: doneSlice[idx].board,
        topSongs: songs,
        displayList: disp,
        loadState: 'ready',
        expanded: exp,
      };
      this.cardStates = doneSlice;
      hilog.info(
        0x0001,
        'LeaderboardView',
        'preview ok %{public}s %{public}s songs=%{public}d gen=%{public}d',
        board.source,
        board.name,
        songs.length,
        startedPreviewGen,
      );
    } catch (e) {
      if (startedPreviewGen !== this.previewGeneration) {
        return;
      }
      idx = this.cardStates.findIndex((c: LeaderboardCardState) => c.board.id === boardId);
      if (idx < 0) {
        return;
      }
      if (this.cardStates[idx].loadState !== 'loading') {
        return;
      }
      const errSlice = this.cardStates.slice();
      errSlice[idx] = {
        board: errSlice[idx].board,
        topSongs: [],
        displayList: [],
        loadState: 'err',
        expanded: errSlice[idx].expanded,
      };
      this.cardStates = errSlice;
      const msg = e instanceof Error ? e.message : String(e);
      hilog.warn(0x0001, 'LeaderboardView', 'preview err %{public}s %{public}s: %{public}s', board.source, board.name, msg);
    }
  }

  /**
   * 分批并发拉预览：比严格串行更快出首屏；单批内并发有限，降低源站限流概率。
   */
  async runPreviewLoadsInBatches(): Promise<void> {
    const batchGen = this.previewGeneration;
    let base = 0;
    while (true) {
      if (batchGen !== this.previewGeneration) {
        hilog.info(0x0001, 'LeaderboardView', 'preview batch aborted: list rebuilt gen %{public}d→%{public}d', batchGen, this.previewGeneration);
        return;
      }
      const n = this.cardStates.length;
      if (base >= n) {
        break;
      }
      const batch: Promise<void>[] = [];
      for (let k = 0; k < PREVIEW_CONCURRENCY && base + k < n; k++) {
        batch.push(this.loadPreviewForIndex(base + k));
      }
      await Promise.all(batch);
      base += PREVIEW_CONCURRENCY;
    }
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

  formatPlayCount(count: number): string {
    if (count >= 100000000) {
      return (count / 100000000).toFixed(1) + ' ' + t('billion_unit');
    }
    if (count >= 10000) {
      return (count / 10000).toFixed(1) + ' ' + t('ten_thousand_unit');
    }
    return count.toString();
  }

  resolveCardCover(card: LeaderboardCardState): string {
    if (card.board.pic && card.board.pic.length > 0) {
      return this.normalizePicUrl(card.board.pic);
    }
    for (let i = 0; i < card.topSongs.length; i++) {
      const p = card.topSongs[i].pic;
      if (p && p.length > 0) {
        return this.normalizePicUrl(p);
      }
    }
    return '';
  }

  /** 按索引读封面，供列表项 build 直接订阅 cardStates，避免 @Builder 传入整卡快照不刷新 */
  resolveCardCoverAt(index: number): string {
    if (index < 0 || index >= this.cardStates.length) {
      return '';
    }
    return this.resolveCardCover(this.cardStates[index]);
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
  @Builder
  SkeletonBoards() {
    Column() {
      ForEach([0, 1, 2], (index: number) => {
        SkeletonGridItem()
      }, (index: number) => `board_skeleton_${index}`)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: DesignTokens.spaceGutter(), right: DesignTokens.spaceGutter(), top: 12 })
  }

  build() {
    Stack() {
      Column() {
        if (this.isLoading) {
          // 榜单首屏用骨架卡片占位，与歌单页保持一致
          this.SkeletonBoards()
        } else {
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
                Column() {
                  Text(this.boardList.length === 0 ? t('no_data') : t('search_no_result'))
                    .fontSize(15)
                    .fontColor(this.secondaryText())
                }
                .width('100%')
                .layoutWeight(1)
                .justifyContent(FlexAlign.Center)
              } else {
                Column() {
                  ForEach(this.cardStates, (card: LeaderboardCardState, index: number) => {
                    Column() {
                      this.ChartCard(index)
                    }
                    .width('100%')
                    .padding({ left: 12, right: 12 })
                    .onAppear(() => {
                      this.ensurePreviewAtIndex(index);
                    })
                  }, (card: LeaderboardCardState, index: number) => `${card.board.source}_${card.board.id}_${index}`)
                }
                .width('100%')
                .layoutWeight(1)
                .padding({ bottom: 16 })
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
                  Column() {
                    ForEach(this.cardStates, (card: LeaderboardCardState, index: number) => {
                      Column() {
                        this.ChartCard(index)
                      }
                      .width('100%')
                      .padding({ left: 12, right: 12 })
                      .onAppear(() => {
                        this.ensurePreviewAtIndex(index);
                      })
                    }, (card: LeaderboardCardState, index: number) => `${card.board.source}_${card.board.id}_${index}`)
                  }
                  .width('100%')
                  .padding({ bottom: 16 })
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
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(this.pageBg())

      if (this.searchOverlayVisible) {
        this.LeaderboardSearchOverlay()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  LeaderboardSearchOverlay() {
    Column() {
      Row() {
        SearchStrip({
          text: $overlaySearchText,
          placeholder: t('search_board_hint'),
          marginH: 0,
          marginV: 0,
          actions: this.leaderboardOverlaySearchActions,
        })
        .layoutWeight(1)
        Text(t('cancel'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.accent())
          .padding({ left: 12, right: 0, top: 8, bottom: 8 })
          .onClick(() => {
            this.closeSearchOverlay();
          })
      }
      .width('100%')
      .padding({ left: DesignTokens.spaceGutter(), right: DesignTokens.spaceGutter(), top: 10, bottom: 8 })
      .alignItems(VerticalAlign.Center)

      if (this.filteredBoardList.length === 0) {
        Column() {
          Text(this.boardList.length === 0 ? t('no_data') : t('no_data'))
            .fontSize(15)
            .fontColor(this.secondaryText())
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.filteredBoardList, (board: BoardItem) => {
            ListItem() {
              Row() {
                Text(board.name || t('board_item'))
                  .layoutWeight(1)
                  .fontSize(16)
                  .fontColor(this.primaryText())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(t('leaderboard_title'))
                  .fontSize(12)
                  .fontColor(this.tertiaryText())
                Image($r('sys.symbol.chevron_right'))
                  .width(14)
                  .height(14)
                  .fillColor(this.tertiaryText())
                  .margin({ left: 6 })
              }
              .width('100%')
              .padding({ left: DesignTokens.spaceGutter(), right: DesignTokens.spaceGutter(), top: 12, bottom: 12 })
              .border({ width: { bottom: 0.33 }, color: DesignTokens.hairlineSeparator(this.theme) })
              .onClick(() => {
                this.closeSearchOverlay();
                this.navigateToBoardDetail(board);
              })
            }
          }, (board: BoardItem) => board.id)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.pageBg())
  }

  @Builder
  ChartCard(index: number) {
    if (index < 0 || index >= this.cardStates.length) {
      Blank()
    } else {
      this.ChartCardInnerByIndex(index)
    }
  }

  /** 仅用 index 订阅 this.cardStates，避免 @Builder(card) 快照导致 loadState/封面不随预览更新 */
  @Builder
  ChartCardInnerByIndex(index: number) {
    if (index < 0 || index >= this.cardStates.length) {
      Blank()
    } else {
      Column() {
        Row() {
          Stack() {
            if (this.resolveCardCoverAt(index).length > 0) {
              Image(this.resolveCardCoverAt(index))
                .width(72)
                .height(72)
                .borderRadius(14)
                .objectFit(ImageFit.Cover)
            } else {
              Image($r('app.media.ic_player_cover_placeholder'))
              .width(72)
              .height(72)
              .borderRadius(14)
              .objectFit(ImageFit.Cover)
            }
          }
          .width(72)
          .height(72)
          .onClick(() => {
            if (index >= 0 && index < this.cardStates.length) {
              this.navigateToBoardDetail(this.cardStates[index].board);
            }
          })

          Column() {
            Text(this.cardStates[index].board.name || t('board_item'))
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.primaryText())
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .lineHeight(22)
            if (this.cardStates[index].board.playCount !== null && this.cardStates[index].board.playCount !== undefined) {
              Text(tf('count_plays', [this.formatPlayCount(this.cardStates[index].board.playCount as number)]))
                .fontSize(12)
                .fontColor(this.tertiaryText())
                .margin({ top: 8 })
            } else {
              Text(t('leaderboard_official'))
                .fontSize(12)
                .fontColor(this.tertiaryText())
                .margin({ top: 8 })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 14 })
          .onClick(() => {
            if (index >= 0 && index < this.cardStates.length) {
              this.navigateToBoardDetail(this.cardStates[index].board);
            }
          })

          Row() {
            Image(this.cardStates[index].expanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
              .width(22)
              .height(22)
              .fillColor(this.secondaryText())
              .padding(8)
              .onClick(() => {
                this.toggleExpand(index);
              })
            Image($r('sys.symbol.chevron_right'))
              .width(22)
              .height(22)
              .fillColor(DesignTokens.accent())
              .padding({ left: 4, right: 4, top: 8, bottom: 8 })
              .onClick(() => {
                if (index >= 0 && index < this.cardStates.length) {
                  this.navigateToBoardDetail(this.cardStates[index].board);
                }
              })
          }
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({
          left: 14,
          right: 10,
          top: 16,
          bottom: 12,
        })
        .alignItems(VerticalAlign.Center)

        if (this.cardStates[index].loadState === 'loading') {
          Column({ space: 8 }) {
            ForEach([0, 1, 2], (_: number, si: number) => {
              Row() {
                Column()
                  .width(28)
                  .height(12)
                  .borderRadius(6)
                  .backgroundColor(DesignTokens.mutedFill(this.theme))
                Column()
                  .layoutWeight(1)
                  .height(12)
                  .borderRadius(6)
                  .backgroundColor(DesignTokens.mutedFill(this.theme))
                  .margin({ left: 12, right: 24 })
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 12, bottom: 12 })
              .backgroundColor(this.theme === 'dark' ? '#17181B' : '#F8F9FB')
              .borderRadius(10)
            })
          }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 12 })
        } else if (this.cardStates[index].loadState === 'err') {
          Row() {
            Text(t('load_failed'))
              .fontSize(13)
              .fontColor(this.tertiaryText())
              .layoutWeight(1)
            Text(t('retry'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(DesignTokens.accent())
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .onClick(() => {
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
              })
          }
          .width('100%')
          .padding({ left: 14, right: 14, bottom: 12 })
          .alignItems(VerticalAlign.Center)
        } else if (this.cardStates[index].displayList.length === 0) {
          Text(t('no_data'))
            .fontSize(13)
            .fontColor(this.tertiaryText())
            .padding({ left: 14, right: 14, bottom: 12 })
        } else {
          Column() {
            ForEach(this.cardStates[index].displayList, (song: BoardMusicItem, si: number) => {
              Column() {
                Row() {
                  Text((si + 1).toString())
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.rankColor(si + 1))
                    .width(32)
                    .textAlign(TextAlign.Center)
                  Column() {
                    Text(song.name || '—')
                      .fontSize(15)
                      .fontColor(this.primaryText())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(song.singer || '')
                      .fontSize(12)
                      .fontColor(this.secondaryText())
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .margin({ top: 3 })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 12, bottom: 12 })
                .onClick(() => {
                  void this.playPreviewSong(song);
                })
                if (si < this.cardStates[index].displayList.length - 1) {
                  Divider()
                    .strokeWidth(0.5)
                    .color(this.cardBorder())
                    .margin({ left: 44, right: 0 })
                }
              }
              .width('100%')
            }, (song: BoardMusicItem, si: number) => `${this.cardStates[index].board.id}_song_${si}_${song.id}`)
          }
          .width('100%')
          .padding({ bottom: 8 })
        }

        Row() {
          Text(this.cardStates[index].expanded ? t('collapse_preview') : t('expand_preview'))
            .fontSize(12)
            .fontColor(this.secondaryText())
            .onClick(() => {
              this.toggleExpand(index);
            })
          Blank()
          Text(t('view_full_chart'))
            .fontSize(14)
            .fontColor(DesignTokens.accent())
            .fontWeight(FontWeight.Medium)
          Image($r('sys.symbol.chevron_right'))
            .width(14)
            .height(14)
            .fillColor(DesignTokens.accent())
            .margin({ left: 4 })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 4, bottom: 16 })
        .onClick(() => {
          if (index >= 0 && index < this.cardStates.length) {
            this.navigateToBoardDetail(this.cardStates[index].board);
          }
        })
      }
      .width('100%')
      .backgroundColor(this.cardBg())
      .borderRadius(DesignTokens.radiusCard())
      .border({ width: 0.5, color: this.cardBorder() })
      .margin({ top: 12 })
    }
  }
}
