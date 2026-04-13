// 排行榜视图：纵向分组卡片 + 榜单内预览曲目 + 展开/收起与进入完整榜单
// 信息架构：一屏浏览多个榜；弱打扰预览 3 条；展开看更多；右侧箭头进二级页

import { getBoardsList, getLeaderboardDetail } from '../../core/leaderboard';
import type { BoardItem, BoardSource, BoardMusicItem } from '../../store/leaderboard/LeaderboardStoreState';
import { navigationService, RouteName } from '../../service/NavigationService';
import hilog from '@ohos.hilog';

const PREVIEW_COLLAPSED = 3;
const PREVIEW_EXPANDED = 8;
const PREVIEW_LOAD_BATCH = 4;
const MAX_PREVIEW_BOARDS = 24;

/** 单个榜单卡片状态（预览与展开） */
interface LeaderboardCardState {
  board: BoardItem;
  topSongs: BoardMusicItem[];
  /** 当前展示的预览行（随展开收起从 topSongs 切片，供 ForEach 稳定渲染） */
  displayList: BoardMusicItem[];
  loadState: 'idle' | 'loading' | 'ready' | 'err';
  expanded: boolean;
}

@Component
export struct LeaderboardView {
  @StorageProp('theme') theme: string = 'light';
  @Prop sourceId: string = 'kw';
  @Prop @Watch("onReCreateKeyChange") reCreateKey: number = 0;
  @State boardList: BoardItem[] = [];
  @State isLoading: boolean = false;
  @State searchText: string = '';
  @State isSearchActive: boolean = false;
  @State filteredBoardList: BoardItem[] = [];
  @State cardStates: LeaderboardCardState[] = [];
  // 请求版本控制，防止竞态
  private requestEpoch: number = 0;

  aboutToAppear() {
    void this.loadBoardList();
  }

  // reCreateKey 变化时重新加载（响应音乐源切换）
  onReCreateKeyChange(newKey: number): void {
    hilog.info(0x0001, 'LeaderboardView', 'reCreateKey changed to %{public}d, reloading...', newKey);
    void this.loadBoardList();
  }

  /** 主题色 */
  pageBg(): string {
    return this.theme === 'dark' ? '#0F0F0F' : '#F2F3F5';
  }

  cardBg(): string {
    return this.theme === 'dark' ? '#1A1A1C' : '#FFFFFF';
  }

  cardBorder(): string {
    return this.theme === 'dark' ? '#2A2A2E' : '#E8E9EC';
  }

  primaryText(): string {
    return this.theme === 'dark' ? '#F2F2F7' : '#1C1C1E';
  }

  secondaryText(): string {
    return this.theme === 'dark' ? '#8E8E93' : '#636366';
  }

  tertiaryText(): string {
    return this.theme === 'dark' ? '#636366' : '#8E8E93';
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
    if (this.isLoading) {
      return;
    }
    // 递增版本号，标记新的请求开始
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
      this.filteredBoardList = boards;
      this.rebuildCardsAndLoadPreviews();
    } catch (err) {
      // 检查版本是否过期
      if (currentEpoch !== this.requestEpoch) {
        return;
      }
      hilog.error(0x0001, 'LeaderboardView', 'Failed to load boards: %{public}s', JSON.stringify(err));
      this.boardList = [];
      this.filteredBoardList = [];
      this.cardStates = [];
    } finally {
      if (currentEpoch === this.requestEpoch) {
        this.isLoading = false;
      }
    }
  }

  rebuildCardsAndLoadPreviews(): void {
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
    void this.runPreviewLoadsInBatches();
  }

  onSearchChange(text: string) {
    this.searchText = text;
    if (!text.trim()) {
      this.filteredBoardList = this.boardList;
    } else {
      const keyword = text.toLowerCase();
      const filtered: BoardItem[] = [];
      for (let i = 0; i < this.boardList.length; i++) {
        const item = this.boardList[i];
        if (item.name && item.name.toLowerCase().includes(keyword)) {
          filtered.push(item);
        }
      }
      this.filteredBoardList = filtered;
    }
    this.rebuildCardsAndLoadPreviews();
  }

  async loadPreviewForIndex(i: number): Promise<void> {
    if (i < 0 || i >= this.cardStates.length) {
      return;
    }
    const snapshot = this.cardStates[i];
    if (snapshot.loadState === 'loading' || snapshot.loadState === 'ready') {
      return;
    }
    const board = snapshot.board;
    const loadingSlice = this.cardStates.slice();
    loadingSlice[i] = {
      board,
      topSongs: snapshot.topSongs,
      displayList: snapshot.displayList,
      loadState: 'loading',
      expanded: snapshot.expanded,
    };
    this.cardStates = loadingSlice;
    try {
      const raw = board.id;
      const ix = raw.indexOf('__');
      const source = ix >= 0 ? raw.substring(0, ix) : board.source;
      const bang = ix >= 0 ? raw.substring(ix + 2) : raw;
      const detail = await getLeaderboardDetail(source, bang, 1);
      const songs = detail?.list ? detail.list.slice(0, PREVIEW_EXPANDED) : [];
      if (i >= this.cardStates.length || this.cardStates[i].board.id !== board.id) {
        return;
      }
      const doneSlice = this.cardStates.slice();
      const exp = doneSlice[i].expanded;
      const vis = exp ? PREVIEW_EXPANDED : PREVIEW_COLLAPSED;
      const disp: BoardMusicItem[] = [];
      for (let k = 0; k < Math.min(vis, songs.length); k++) {
        disp.push(songs[k]);
      }
      doneSlice[i] = {
        board,
        topSongs: songs,
        displayList: disp,
        loadState: 'ready',
        expanded: exp,
      };
      this.cardStates = doneSlice;
    } catch {
      if (i >= this.cardStates.length) {
        return;
      }
      const errSlice = this.cardStates.slice();
      errSlice[i] = {
        board: errSlice[i].board,
        topSongs: [],
        displayList: [],
        loadState: 'err',
        expanded: errSlice[i].expanded,
      };
      this.cardStates = errSlice;
    }
  }

  async runPreviewLoadsInBatches(): Promise<void> {
    const n = Math.min(this.cardStates.length, MAX_PREVIEW_BOARDS);
    let start = 0;
    while (start < n) {
      const batch: Promise<void>[] = [];
      const end = Math.min(start + PREVIEW_LOAD_BATCH, n);
      for (let j = start; j < end; j++) {
        batch.push(this.loadPreviewForIndex(j));
      }
      await Promise.all(batch);
      start = end;
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
      // 开始加载预览
      slice[index] = {
        board: cur.board,
        topSongs: cur.topSongs,
        displayList: cur.displayList,
        loadState: 'loading',
        expanded: newExp,
      };
      this.cardStates = slice;
      void this.loadPreviewForIndex(index);
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

  navigateToBoardDetail(board: BoardItem): void {
    hilog.info(0x0001, 'LeaderboardView', 'Navigate to board: %{public}s', board.name);
    const raw = board.id;
    const ix = raw.indexOf('__');
    const idSource = ix >= 0 ? raw.substring(0, ix) : board.source;
    const bang = ix >= 0 ? raw.substring(ix + 2) : raw;
    const canonicalBoardId = `${idSource}__${bang}`;
    navigationService.navigateTo(RouteName.BOARD_DETAIL, {
      boardId: canonicalBoardId,
      boardName: board.name,
      boardSource: idSource,
    });
  }

  formatPlayCount(count: number): string {
    if (count >= 100000000) {
      return (count / 100000000).toFixed(1) + '亿';
    }
    if (count >= 10000) {
      return (count / 10000).toFixed(1) + '万';
    }
    return count.toString();
  }

  build() {
    Column() {
      this.SearchBar()

      Column() {
        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(32)
              .height(32)
            Text('加载榜单…')
              .fontSize(14)
              .fontColor(this.secondaryText())
              .margin({ top: 12 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.cardStates.length === 0) {
          Column() {
            Text('暂无排行榜数据')
              .fontSize(15)
              .fontColor(this.secondaryText())
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 0 }) {
            ListItem() {
              this.SectionIntro()
            }
            ForEach(this.cardStates, (card: LeaderboardCardState, index: number) => {
              ListItem() {
                this.ChartCard(index)
              }
            }, (card: LeaderboardCardState, index: number) => `${card.board.id}_${index}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: 12, right: 12, bottom: 16 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(this.pageBg())
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  SearchBar() {
    Column() {
      Row() {
        if (!this.isSearchActive && !this.searchText) {
          Image($r('sys.symbol.magnifyingglass'))
            .width(20)
            .height(20)
            .fillColor(this.secondaryText())
            .margin({ left: 16 })
            .onClick(() => {
              this.isSearchActive = true;
            })
          Blank()
        } else {
          TextInput({ placeholder: '搜索榜单名称', text: this.searchText })
            .layoutWeight(1)
            .height(40)
            .backgroundColor(this.theme === 'dark' ? '#2C2C2E' : '#E8E9EC')
            .borderRadius(20)
            .padding({ left: 16, right: 16 })
            .fontSize(14)
            .fontColor(this.primaryText())
            .placeholderColor(this.tertiaryText())
            .onChange((text: string) => {
              this.onSearchChange(text);
            })
            .onEditChange((isEditing: boolean) => {
              if (!isEditing && !this.searchText) {
                this.isSearchActive = false;
              }
            })
        }
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .backgroundColor(this.theme === 'dark' ? '#1A1A1C' : '#FFFFFF')
    .border({ width: { bottom: 0.5 }, color: this.cardBorder() })
  }

  /** 页内说明：降低认知成本 */
  @Builder
  SectionIntro() {
    Column() {
      Text('精选榜单')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.secondaryText())
        .letterSpacing(0.5)
        .margin({ top: 14, bottom: 4 })
      Text('下滑浏览各榜；卡片内为试听预览，展开可看更多，右侧进入完整歌单')
        .fontSize(11)
        .fontColor(this.tertiaryText())
        .lineHeight(16)
        .margin({ bottom: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ChartCard(index: number) {
    if (index < 0 || index >= this.cardStates.length) {
      Blank()
    } else {
      this.ChartCardInner(this.cardStates[index], index)
    }
  }

  @Builder
  ChartCardInner(card: LeaderboardCardState, index: number) {
    Column() {
      Row() {
        Stack() {
          if (card.board.pic && card.board.pic.length > 0) {
            Image(card.board.pic)
              .width(52)
              .height(52)
              .borderRadius(10)
              .objectFit(ImageFit.Cover)
          } else {
            Column() {
              Image($r('sys.symbol.play_circle'))
                .width(26)
                .height(26)
                .fillColor(this.tertiaryText())
            }
            .width(52)
            .height(52)
            .borderRadius(10)
            .backgroundColor(this.theme === 'dark' ? '#2C2C2E' : '#E8E9EC')
            .justifyContent(FlexAlign.Center)
          }
        }
        .width(52)
        .height(52)

        Column() {
          Text(card.board.name || '榜单')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryText())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (card.board.playCount !== null && card.board.playCount !== undefined) {
            Text(this.formatPlayCount(card.board.playCount))
              .fontSize(12)
              .fontColor(this.tertiaryText())
              .margin({ top: 4 })
          } else {
            Text('官方榜')
              .fontSize(12)
              .fontColor(this.tertiaryText())
              .margin({ top: 4 })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .onClick(() => {
          this.navigateToBoardDetail(card.board);
        })

        Row() {
          Image(card.expanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
            .width(22)
            .height(22)
            .fillColor(this.secondaryText())
            .padding(8)
            .onClick(() => {
              this.toggleExpand(index);
            })
          Image($r('sys.symbol.chevron_right'))
            .width(20)
            .height(20)
            .fillColor(this.theme === 'dark' ? '#E63946' : '#E63946')
            .padding({ left: 4, right: 4, top: 8, bottom: 8 })
            .onClick(() => {
              this.navigateToBoardDetail(card.board);
            })
        }
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({
        left: 14,
        right: 10,
        top: 14,
        bottom: 10,
      })
      .alignItems(VerticalAlign.Center)

      if (card.loadState === 'loading') {
        Row() {
          LoadingProgress()
            .width(20)
            .height(20)
          Text('加载预览…')
            .fontSize(12)
            .fontColor(this.tertiaryText())
            .margin({ left: 8 })
        }
        .width('100%')
        .padding({ left: 14, right: 14, bottom: 12 })
      } else if (card.loadState === 'err') {
        Text('预览加载失败，仍可进入完整榜单')
          .fontSize(12)
          .fontColor(this.tertiaryText())
          .padding({ left: 14, right: 14, bottom: 12 })
      } else if (card.displayList.length === 0) {
        Text('暂无预览曲目')
          .fontSize(12)
          .fontColor(this.tertiaryText())
          .padding({ left: 14, right: 14, bottom: 12 })
      } else {
        Column() {
          ForEach(card.displayList, (song: BoardMusicItem, si: number) => {
            Row() {
              Text((si + 1).toString())
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.rankColor(si + 1))
                .width(28)
                .textAlign(TextAlign.Center)
              Column() {
                Text(song.name || '—')
                  .fontSize(14)
                  .fontColor(this.primaryText())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(song.singer || '')
                  .fontSize(12)
                  .fontColor(this.secondaryText())
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .backgroundColor(this.theme === 'dark' ? '#141415' : '#F9F9FB')
            .borderRadius(8)
            .margin({ bottom: si < card.displayList.length - 1 ? 6 : 0 })
          }, (song: BoardMusicItem, si: number) => `${card.board.id}_song_${si}_${song.id}`)
        }
        .width('100%')
        .padding({ left: 0, right: 0, bottom: 12 })
      }

      Row() {
        Blank()
        Text('查看完整榜单')
          .fontSize(13)
          .fontColor('#E63946')
          .fontWeight(FontWeight.Medium)
        Image($r('sys.symbol.chevron_right'))
          .width(14)
          .height(14)
          .fillColor('#E63946')
          .margin({ left: 2 })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 4, bottom: 14 })
      .onClick(() => {
        this.navigateToBoardDetail(card.board);
      })
    }
    .width('100%')
    .backgroundColor(this.cardBg())
    .borderRadius(14)
    .border({ width: 0.5, color: this.cardBorder() })
    .margin({ top: 10 })
  }
}
