// SongList 视图 - 歌单列表视图
// 优化：字体放大、标签筛选、下拉刷新

import hilog from '@ohos.hilog';
import {
  musicSdk,
  type SongListResult,
  type SongListInfo,
  type SingleMusicSdkInterface,
} from '../../core/music/MusicFeatureEntry';
import { RouteName, navigateTo, NavigationParams } from '../../service/NavigationService';
import { DesignTokens } from '../../theme/DesignTokens';
import { SearchStrip, SearchStripActions } from '../../components/common/SearchStrip';

// 排序选项接口
interface SortOption {
  name: string;
  tid: string;
}

// 标签选项接口
interface TagOption {
  name: string;
  tid: string;
}

// 歌单项接口
interface SongListItemData {
  id: string;
  name: string;
  author: string;
  img: string;
  play_count: string;
  desc: string;
  total: number;
  source: string;
}

@Component
export struct SongListView {
  @Prop sourceId: string = 'kw';
  @Prop @Watch("onReCreateKeyChange") reCreateKey: number = 0;
  @StorageProp('theme') theme: string = 'light';
  /** 与 HomePage 全局搜索联动（置于垂直 Scroll 内首位，随列表上滑滚出） */
  @Link searchText: string;
  @Prop searchStripActions: SearchStripActions = new SearchStripActions();

  private songListScroller: Scroller = new Scroller();
  @State isFilterPinned: boolean = false;
  private readonly filterPinThreshold: number = DesignTokens.heightSearchField() + DesignTokens.spaceUnit() * 2;
  private readonly searchStripHostHeight: number = DesignTokens.heightSearchField() + DesignTokens.spaceUnit() * 2;
  private readonly filterBarPinnedHeight: number = 52;
  private readonly minPinItems: number = 9;
  private alive: boolean = false;
  private scrollTopTimer: number = -1;
  private coverStartupTimer: number = -1;
  private readonly coverStartupDelayMs: number = 1800;
  @State allowRemoteCoverRender: boolean = false;
  @State coverInteractionUnlocked: boolean = false;

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
        this.songListScroller.scrollTo({ xOffset: 0, yOffset: 0, animation: false });
      } catch {
        // ignore
      }
      this.scrollTopTimer = -1;
    }, 0);
  }

  // 排序选项
  private sortOptions: SortOption[] = [];
  @State selectedSort: string = 'default';

  // 标签选项
  @State tagOptions: TagOption[] = [];
  @State selectedTag: string = '';

  // 歌单数据
  @State songLists: SongListItemData[] = [];
  @State coverWindowStart: number = 0;
  @State coverWindowEnd: number = 11;
  @State hasUserScrolledForPagination: boolean = false;
  @State isLoading: boolean = true;
  @State isRefreshing: boolean = false;
  @State currentPage: number = 1;
  @State hasMore: boolean = true;
  // 请求版本控制，防止竞态
  private requestEpoch: number = 0;
  private readonly gridColumns: number = 3;
  private readonly estimatedRowHeight: number = 210;
  private readonly visibleRowsEstimate: number = 3;
  private readonly preloadRows: number = 1;

  aboutToAppear() {
    this.alive = true;
    this.allowRemoteCoverRender = true;
    this.coverInteractionUnlocked = true;
    // 初始化排序选项
    const defaultOption: SortOption = { name: '默认', tid: 'default' };
    const hotOption: SortOption = { name: '最热', tid: 'hot' };
    const newOption: SortOption = { name: '最新', tid: 'new' };
    this.sortOptions = [defaultOption, hotOption, newOption];
    this.scrollToTopSoon();
    this.loadTags();
    this.loadSongList(true);
  }

  aboutToDisappear() {
    this.alive = false;
    if (this.scrollTopTimer >= 0) {
      clearTimeout(this.scrollTopTimer);
      this.scrollTopTimer = -1;
    }
    if (this.coverStartupTimer >= 0) {
      clearTimeout(this.coverStartupTimer);
      this.coverStartupTimer = -1;
    }
  }

  private startCoverStartupGate(): void {
    if (this.coverStartupTimer >= 0) {
      clearTimeout(this.coverStartupTimer);
      this.coverStartupTimer = -1;
    }
    this.coverStartupTimer = setTimeout(() => {
      if (!this.alive) {
        return;
      }
      this.allowRemoteCoverRender = true;
      this.coverStartupTimer = -1;
    }, this.coverStartupDelayMs);
  }

  // reCreateKey 变化时重新加载（响应音乐源切换）
  // 注意：@Watch 回调参数为被监听属性名 (string)，不是属性新值，请读 this.reCreateKey
  onReCreateKeyChange(_changedPropertyName?: string): void {
    const epoch = this.reCreateKey;
    hilog.info(0x0001, 'SongListView', 'reCreateKey changed to %{public}d, reloading...', epoch);
    this.selectedSort = 'default';
    this.selectedTag = '';
    this.allowRemoteCoverRender = true;
    this.coverInteractionUnlocked = true;
    this.isFilterPinned = false;
    this.scrollToTopSoon();
    this.loadTags();
    this.loadSongList(true);
  }

  // 加载标签
  async loadTags(): Promise<void> {
    try {
      let sdk: SingleMusicSdkInterface | undefined;
      if (this.sourceId === 'kw') sdk = musicSdk.kw;
      else if (this.sourceId === 'kg') sdk = musicSdk.kg;
      else if (this.sourceId === 'tx') sdk = musicSdk.tx;
      else if (this.sourceId === 'wy') sdk = musicSdk.wy;
      else if (this.sourceId === 'mg') sdk = musicSdk.mg;

      if (!sdk?.songList) return;

      const result = await sdk.songList.getTags();
      if (result && result.tags) {
        const tags: TagOption[] = [];
        tags.push({ name: '全部', tid: '' });
        for (let i = 0; i < result.tags.length; i++) {
          const t = result.tags[i];
          tags.push({ name: t.name || '', tid: t.id || '' });
        }
        this.tagOptions = tags;
        const keep = tags.some((t: TagOption) => t.tid === this.selectedTag);
        if (!keep) {
          this.selectedTag = '';
        }
      }
    } catch (err) {
      hilog.error(0x0001, 'SongListView', 'Load tags failed: %{public}s', JSON.stringify(err));
    }
  }

  // 加载歌单列表
  async loadSongList(isRefresh: boolean = false): Promise<void> {
    if (this.isLoading && !isRefresh) return;
    // 递增版本号，标记新的请求开始
    const currentEpoch = ++this.requestEpoch;
    if (isRefresh) {
      this.currentPage = 1;
      this.hasMore = true;
      this.isRefreshing = true;
      this.songLists = [];
      this.hasUserScrolledForPagination = false;
      this.resetCoverWindow();
    }
    this.isLoading = true;

    try {
      let sdk: SingleMusicSdkInterface | undefined;
      if (this.sourceId === 'kw') sdk = musicSdk.kw;
      else if (this.sourceId === 'kg') sdk = musicSdk.kg;
      else if (this.sourceId === 'tx') sdk = musicSdk.tx;
      else if (this.sourceId === 'wy') sdk = musicSdk.wy;
      else if (this.sourceId === 'mg') sdk = musicSdk.mg;

      if (!sdk?.songList) {
        this.isLoading = false;
        return;
      }

      const tagId = this.selectedTag || '';
      const sortId = this.selectedSort === 'default' ? '' : this.selectedSort;
      const result: SongListResult = await sdk.songList.getList(sortId, tagId, this.currentPage);

      // 检查版本是否过期（用户可能已切换到其他源）
      if (currentEpoch !== this.requestEpoch) {
        hilog.info(0x0001, 'SongListView', 'Stale request ignored, current epoch: %{public}d', this.requestEpoch);
        return;
      }

      const items: SongListItemData[] = [];
      for (let i = 0; i < result.list.length; i++) {
        const sl: SongListInfo = result.list[i];
        const item: SongListItemData = {
          id: sl.id || '',
          name: sl.name || '',
          author: sl.author || '',
          img: sl.img || '',
          play_count: sl.play_count || '0',
          desc: sl.desc || '',
          total: sl.total || 0,
          source: this.sourceId,
        };
        items.push(item);
      }

      if (isRefresh) {
        this.songLists = items;
      } else {
        this.songLists = this.songLists.concat(items);
      }
      this.updateCoverWindowByOffset();
      if (this.songLists.length < this.minPinItems && this.isFilterPinned) {
        this.isFilterPinned = false;
      }
      if (this.songLists.length < this.minPinItems) {
        this.scrollToTopSoon();
      }

      this.hasMore = items.length >= (result.limit || 20);
      this.currentPage++;
    } catch (err) {
      // 检查版本是否过期
      if (currentEpoch !== this.requestEpoch) {
        return;
      }
      const msg = this.describeError(err);
      hilog.error(0x0001, 'SongListView', 'Load song list failed: %{public}s', msg);
    } finally {
      if (currentEpoch === this.requestEpoch) {
        this.isLoading = false;
        this.isRefreshing = false;
      }
    }
  }

  private describeError(err: Object): string {
    if (err instanceof Error) {
      return `${err.name}: ${err.message}`;
    }
    const anyErr = err as Record<string, Object>;
    const code = anyErr['code'];
    const message = anyErr['message'];
    const raw = JSON.stringify(err);
    const parts: string[] = [];
    if (code !== undefined && code !== null) {
      parts.push(`code=${String(code)}`);
    }
    if (typeof message === 'string' && message.length > 0) {
      parts.push(`message=${message}`);
    }
    if (raw && raw !== '{}') {
      parts.push(`raw=${raw}`);
    }
    if (parts.length > 0) {
      return parts.join(', ');
    }
    return 'unknown-error(empty-payload)';
  }

  // 切换排序
  onSortChange(sortId: string): void {
    if (this.selectedSort === sortId) return;
    this.coverInteractionUnlocked = true;
    this.isFilterPinned = false;
    this.scrollToTopSoon();
    this.selectedSort = sortId;
    this.loadSongList(true);
  }

  // 切换标签
  onTagChange(tagId: string): void {
    if (this.selectedTag === tagId) return;
    this.coverInteractionUnlocked = true;
    this.isFilterPinned = false;
    this.scrollToTopSoon();
    this.selectedTag = tagId;
    this.loadSongList(true);
  }

  private syncFilterPinnedByOffset(): void {
    const y = this.getSafeScrollOffsetY();
    this.updateCoverWindowByOffset(y);
    if (y < 0) {
      this.scrollToTopSoon();
      if (this.isFilterPinned) {
        this.isFilterPinned = false;
      }
      return;
    }
    if (this.songLists.length < this.minPinItems) {
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
    if (this.isFilterPinned && y <= pinLine - 16) {
      this.isFilterPinned = false;
    }
  }

  private resetCoverWindow(): void {
    this.coverWindowStart = 0;
    this.coverWindowEnd = this.gridColumns * (this.visibleRowsEstimate + this.preloadRows) - 1;
  }

  private updateCoverWindowByOffset(offsetY?: number): void {
    const y = offsetY ?? this.getSafeScrollOffsetY();
    const safeY = y > 0 ? y : 0;
    const topRow = Math.floor(safeY / this.estimatedRowHeight);
    const start = Math.max(0, (topRow - this.preloadRows) * this.gridColumns);
    const end = Math.max(start, (topRow + this.visibleRowsEstimate + this.preloadRows) * this.gridColumns - 1);
    if (start !== this.coverWindowStart) {
      this.coverWindowStart = start;
    }
    if (end !== this.coverWindowEnd) {
      this.coverWindowEnd = end;
    }
  }

  private getSafeScrollOffsetY(): number {
    try {
      const rawY = this.songListScroller.currentOffset().yOffset;
      return typeof rawY === 'number' && Number.isFinite(rawY) ? rawY : 0;
    } catch {
      return 0;
    }
  }

  // 跳转到歌单详情
  openSonglistDetail(item: SongListItemData): void {
    const navParams: NavigationParams = {
      songListId: item.id,
      songListName: item.name,
      songListSource: item.source,
    };
    navigateTo(RouteName.SONGLIST_DETAIL, navParams);
  }

  build() {
    Column() {
      if (this.songLists.length < this.minPinItems) {
        SearchStrip({
          text: $searchText,
          placeholder: '搜索歌曲、歌手、专辑',
          marginH: DesignTokens.spaceGutter(),
          marginV: DesignTokens.spaceUnit(),
          tapToOpenOnly: true,
          actions: this.searchStripActions,
        })
        this.FilterBar()
        if (this.isLoading && this.songLists.length === 0) {
          Column() {
            LoadingProgress()
              .width(32)
              .height(32)
              .color(DesignTokens.accent())
            Text('加载中…')
              .fontSize(15)
              .fontColor(DesignTokens.labelSecondary(this.theme))
              .margin({ top: 12 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.songLists.length === 0) {
          Column() {
            Text('暂无歌单')
              .fontSize(15)
              .fontColor(DesignTokens.labelSecondary(this.theme))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          this.SongListGrid()
        }
      } else {
        if (this.isFilterPinned) {
          this.FilterBar()
        }
        Scroll(this.songListScroller) {
          Column() {
            if (!this.isFilterPinned) {
              SearchStrip({
                text: $searchText,
                placeholder: '搜索歌曲、歌手、专辑',
                marginH: DesignTokens.spaceGutter(),
                marginV: DesignTokens.spaceUnit(),
                tapToOpenOnly: true,
                actions: this.searchStripActions,
              })
            } else {
              Blank()
                .width('100%')
                .height(this.searchStripHostHeight)
            }
            if (!this.isFilterPinned) {
              this.FilterBar()
            } else {
              Blank()
                .width('100%')
                .height(this.filterBarPinnedHeight)
            }
            this.SongListGrid()
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .onDidScroll(() => {
          const y = this.getSafeScrollOffsetY();
          if (!this.coverInteractionUnlocked && y > 16) {
            this.coverInteractionUnlocked = true;
          }
          if (!this.hasUserScrolledForPagination && y > 120) {
            this.hasUserScrolledForPagination = true;
          }
          this.syncFilterPinnedByOffset();
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }

  @Builder
  FilterBar() {
    Scroll() {
      Row() {
        // 排序：UISegmentedControl 式轨道 + 浮起选中块
        Row() {
          ForEach(this.sortOptions, (option: SortOption) => {
            Text(option.name)
              .fontSize(13)
              .fontColor(this.selectedSort === option.tid ? DesignTokens.labelPrimary(this.theme) : DesignTokens.labelSecondary(this.theme))
              .fontWeight(this.selectedSort === option.tid ? FontWeight.Medium : FontWeight.Normal)
              .padding({ left: 14, right: 14, top: 5, bottom: 5 })
              .backgroundColor(this.selectedSort === option.tid ? DesignTokens.segmentedThumb(this.theme) : Color.Transparent)
              .borderRadius(DesignTokens.radiusSearch())
              .onClick(() => {
                this.onSortChange(option.tid);
              })
          })
        }
        .padding(2)
        .backgroundColor(DesignTokens.segmentedTrack(this.theme))
        .borderRadius(DesignTokens.radiusSearch())

        if (this.tagOptions.length > 1) {
          Column()
            .width(0.33)
            .height(20)
            .backgroundColor(DesignTokens.hairlineSeparator(this.theme))
            .margin({ left: 12, right: 10 })

          ForEach(this.tagOptions, (tag: TagOption) => {
            Text(tag.name)
              .fontSize(13)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .fontColor(this.selectedTag === tag.tid ? DesignTokens.accent() : DesignTokens.labelSecondary(this.theme))
              .fontWeight(this.selectedTag === tag.tid ? FontWeight.Medium : FontWeight.Normal)
              .backgroundColor(this.selectedTag === tag.tid ? DesignTokens.accentSoft(this.theme) : Color.Transparent)
              .borderRadius(DesignTokens.radiusSearch())
              .margin({ right: 4 })
              .onClick(() => {
                this.onTagChange(tag.tid);
              })
          })
        }
      }
      .padding({
        left: DesignTokens.spaceGutter(),
        right: DesignTokens.spaceGutter(),
        top: DesignTokens.spaceUnit(),
        bottom: DesignTokens.spaceUnit(),
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(this.filterBarPinnedHeight)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .backgroundColor(DesignTokens.chromeBar(this.theme))
    .border({ width: { bottom: 0.33 }, color: DesignTokens.hairlineSeparator(this.theme) })
  }

  @Builder
  SongListGrid() {
    Grid() {
      ForEach(this.songLists, (item: SongListItemData, index: number) => {
        GridItem() {
          this.SongListCard(item, index)
        }
        .onAppear(() => {
          if (this.hasUserScrolledForPagination &&
            this.hasMore &&
            !this.isLoading &&
            this.songLists.length > 0 &&
            index >= this.songLists.length - 3) {
            this.loadSongList(false);
          }
        })
      }, (item: SongListItemData, index: number) => `${item.id}_${index}`)

      // 加载更多
      if (this.hasMore) {
        GridItem() {
          Column() {
            if (this.isLoading) {
              LoadingProgress()
                .width(24)
                .height(24)
                .color(DesignTokens.labelTertiary(this.theme))
            } else {
              Text('加载更多')
                .fontSize(13)
                .fontColor(DesignTokens.labelSecondary(this.theme))
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            if (!this.isLoading) {
              this.loadSongList(false);
            }
          })
        }
        .padding(DesignTokens.spaceGutter())
      }
    }
    .columnsTemplate('1fr 1fr 1fr')
    .cachedCount(4)
    .rowsGap(12)
    .columnsGap(12)
    .padding(DesignTokens.spaceGutter())
    .width('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }

  private toLightweightCoverUrl(rawUrl: string): string {
    const url = (rawUrl ?? '').trim();
    if (!url) {
      return '';
    }
    let next = url;
    // Kuwo/通用目录尺寸：/500/ -> /150/
    next = next.replace('/500/', '/150/');
    next = next.replace('/300/', '/150/');
    // QQ 500x500 封面降级到 300x300
    next = next.replace('T002R500x500M000', 'T002R300x300M000');
    next = next.replace('T001R500x500M000', 'T001R300x300M000');
    // 通用后缀尺寸 _500.jpg -> _150.jpg
    next = next.replace('_500.jpg', '_150.jpg');
    next = next.replace('_500.png', '_150.png');
    return next;
  }

  private canRenderCover(index: number, item: SongListItemData): boolean {
    if (!this.allowRemoteCoverRender) {
      return false;
    }
    if (!this.coverInteractionUnlocked) {
      return false;
    }
    if (index < this.coverWindowStart || index > this.coverWindowEnd) {
      return false;
    }
    return !!this.toLightweightCoverUrl(item.img || '');
  }

  @Builder
  SongListCard(item: SongListItemData, index: number) {
    Column() {
      // 封面
      Stack() {
        if (this.canRenderCover(index, item)) {
          Image(this.toLightweightCoverUrl(item.img || ''))
            .width('100%')
            .aspectRatio(1)
            .borderRadius(DesignTokens.radiusCover())
            .objectFit(ImageFit.Cover)
            .onError(() => {
              // 单卡封面失败时降级占位，避免重复解码/重试风暴。
              item.img = '';
            })
        } else {
          Image($r('app.media.ic_player_cover_placeholder'))
          .width('100%')
          .aspectRatio(1)
          .borderRadius(DesignTokens.radiusCover())
          .objectFit(ImageFit.Cover)
        }

        // 播放量
        Row() {
          Image($r('sys.symbol.play_fill'))
            .width(10)
            .height(10)
            .fillColor('#FFFFFF')
          Text(this.formatPlayCount(item.play_count))
            .fontSize(10)
            .fontColor('#FFFFFF')
            .margin({ left: 3 })
        }
        .padding({ left: 6, right: 6, top: 3, bottom: 3 })
        .backgroundColor('rgba(0, 0, 0, 0.4)')
        .borderRadius(DesignTokens.radiusCover())
        .position({ x: 6, y: 6 })
      }
      .width('100%')
      .aspectRatio(1)

      // 信息
      Column() {
        Text(item.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .maxLines(2)
          .lineHeight(19)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(item.author)
          .fontSize(12)
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 5 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ top: 10 })
    }
    .width('100%')
    .padding(6)
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .border({ width: 0.33, color: DesignTokens.cardBorder(this.theme) })
    .onClick(() => {
      this.openSonglistDetail(item);
    })
  }

  private formatPlayCount(count: string): string {
    const num = parseFloat(count);
    if (isNaN(num)) return '0';
    if (num >= 100000000) return (num / 100000000).toFixed(1) + '亿';
    if (num >= 10000) return (num / 10000).toFixed(1) + '万';
    return num.toString();
  }
}
