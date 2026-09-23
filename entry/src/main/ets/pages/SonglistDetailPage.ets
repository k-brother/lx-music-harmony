// 歌单详情页 - 对应 src/screens/SonglistDetail/index.tsx
// 显示歌单信息和歌曲列表

import hilog from '@ohos.hilog';
import { showAppToast, TOAST_DURATION_SHORT } from '../utils/Toast';
import { PlayerBar } from '../components/player/PlayerBar';
import { setDownloadContext } from '../core/music/MusicFeatureEntry';
import { NavigationParams } from '../service/NavigationService';
import { playerService } from '../service/PlayerService';
import { navigationService } from '../service/NavigationService';
import { common } from '@kit.AbilityKit';
import { getUserListMusic } from '../service/ListService';
import { emitSearchRequest } from '../service/EventBus';
import { showSongItemMenu, showSonglistMoreMenu } from './SonglistDetail/SonglistMenus';
import { songRowToQueueItem } from '../core/list/SongMappers';
import { loadLocalSonglist, loadOnlineSonglist, type SonglistLoadOutcome } from './SonglistDetail/SonglistLoader';
import {
  applyMovePosition,
  applyMoveToList,
  buildMoveTargetOptions,
  positionOf,
} from './SonglistDetail/SonglistMoveActions';
import { appActionMenu, appConfirm } from '../service/DialogService';
import { ListRow } from '../components/ui/ListRow';
import { NavBar } from '../components/ui/NavBar';
import { InputSheet } from '../components/ui/InputSheet';
import { SelectSheet } from '../components/ui/SelectSheet';
import type { SettingOption } from '../components/ui/SettingsTypes';
import type { SongItem, SonglistInfo } from './SonglistDetail/SonglistTypes';
import { SonglistDetailHeader } from './SonglistDetail/SonglistDetailHeader';
import { SonglistBatchBar } from './SonglistDetail/SonglistBatchBar';
import { SonglistSortSheet } from './SonglistDetail/SonglistSortSheet';
import { musicRowListToSongItems } from './SonglistDetail/SonglistMapper';
import {
  collectSonglist,
  syncBoundSonglist,
  uncollectSonglist,
} from './SonglistDetail/SonglistCollectActions';
import {
  batchAddToDefaultList,
  batchDownloadSongs,
  batchRemoveFromLocalList,
  downloadWholeList,
  type SonglistTarget,
} from './SonglistDetail/SonglistActions';
import { DesignTokens } from '../theme/DesignTokens';
import { Breakpoints } from '../theme/Breakpoints';
import { LazyDataSource } from '../utils/LazyDataSource';
import { formatPlayTime } from '../utils/CommonUtils';
import { scrollerOffsetY } from '../utils/ScrollTools';
import { SkeletonListItem } from '../components/common/SkeletonView';
import { StateView } from '../components/ui/StateView';
import { t, tf, sourceLabel } from '../service/LocalizationService';
import { type SortField, type SortOrder } from '../utils/ListTools';
import {
  sortRows,
  dedupeRows,
  countDuplicateGroupsOf,
} from './SonglistDetail/SonglistListOps';
import { persistLocalOrder, syncOnlineListToLocal } from './SonglistDetail/SonglistLocalLibrary';
import {
  addRowToDefaultList,
  addRowToDislike,
  downloadRow,
  openInBrowser,
  shareSongRow,
  sourceDetailUrl,
} from './SonglistDetail/SonglistRowActions';
import {
  clearPlayingRows,
  markPlayingRow,
  playAllRows,
  playSongRow,
} from './SonglistDetail/SonglistPlayActions';
import {
  allIndexes,
  containsRowRef,
  indexOfRowRef,
  isAllSelected,
  rowsAt,
  toggleIndex,
} from './SonglistDetail/SonglistSelection';
import { loadScrollOffset, saveScrollOffset } from './SonglistDetail/SonglistScrollMemory';

interface PromptActionResult {
  index: number;
}

interface MenuActionItem {
  label: string;
  action: () => void;
}

@Component
export struct SonglistDetailPage {
  @StorageProp('theme') theme: string = 'light';
  /** 一多：窗口宽度（vp），大屏内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
  // 列表显示项（设置 → 列表设置）
  @StorageProp('showListSource') showListSource: boolean = true;
  @StorageProp('showListAlbum') showListAlbum: boolean = true;
  @StorageProp('showListDuration') showListDuration: boolean = true;
  @StorageProp('rememberScrollPosition') rememberScrollPosition: boolean = true;
  /** 收藏/同步进行中（避免重复触发） */
  private collectBusy: boolean = false;
  /** 点击列表项：播放整个列表 / 只播这一首（设置 → 列表） */
  @StorageProp('listClickPlay') listClickPlay: boolean = false;

  /** 按压反馈：列表行/按钮变淡 */
  @Styles
  pressDim() {
    .opacity(0.65)
  }

  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State creator: string = t('unknown');
  @State playCount: string = '0';
  @State songList: SongItem[] = [];
  /** 列表用 LazyForEach：上千首歌只创建可视区的行（ForEach 会全量建树） */
  private songListSource: LazyDataSource<SongItem> = new LazyDataSource<SongItem>();
  @State isLoading: boolean = true;
  @State hasError: boolean = false;
  @State headerCompact: boolean = false;
  @State listCoverLoadFailed: boolean = false;

  // ===== 列表能力：多选 / 排序 / 去重（对齐安卓版歌单菜单）=====
  /** 多选模式：行点击变为勾选，底部出现批量操作栏 */
  @State selectMode: boolean = false;
  /** 已选下标（用下标而非 id，重复歌曲也能精确删掉某一首） */
  @State selectedIndexes: number[] = [];
  /** 排序设置面板 */
  @State showSortSheet: boolean = false;
  @State sortField: string = 'name';
  @State sortOrder: string = 'up';
  /** 去重时是否忽略 Live/伴奏等版本后缀 */
  @State dedupeFilterVariant: boolean = true;

  // ===== 本地列表的「调整位置 / 移动到其他列表」（对齐安卓版 change_position / move_to）=====
  @State showMovePositionSheet: boolean = false;
  @State movePositionValue: string = '';
  private movePositionTarget: SongItem | null = null;
  @State showMoveToListSheet: boolean = false;
  @State moveToListOptions: SettingOption[] = [];
  private moveToListTarget: SongItem | null = null;

  // 歌单信息
  @State listInfo: SonglistInfo = {
    source: '',
    id: '',
    name: t('loading'),
    creator: '',
    pic: '',
    desc: '',
    playCount: 0,
  };

  // 防止重复加载标志
  private detailLoaded: boolean = false;
  /** 最近一次加载的歌单参数，用于失败重试 */
  private lastSourceId: string = '';
  private lastListId: string = '';
  private songListScroller: Scroller = new Scroller();

  /** 失败重试：用上次的参数重新拉取 */
  private reloadDetail(): void {
    if (this.lastSourceId.length === 0 || this.lastListId.length === 0) {
      return;
    }
    void this.loadSonglistDetail(this.lastSourceId, this.lastListId);
  }

  /** 列表副标题：歌手 [· 专辑] [· 音源]，按设置裁剪 */
  private buildSubtitle(song: SongItem): string {
    const parts: string[] = [];
    if (song.singer && song.singer.length > 0) {
      parts.push(song.singer);
    }
    if (this.showListAlbum && song.album && song.album.length > 0) {
      parts.push(song.album);
    }
    if (this.showListSource && song.source && song.source.length > 0) {
      parts.push(sourceLabel(song.source));
    }
    return parts.join(' · ');
  }

  /** 行尾时长（无时长信息时不显示占位） */
  private formatSongDuration(song: SongItem): string {
    if (!song.duration || song.duration <= 0) {
      return '';
    }
    return formatPlayTime(song.duration);
  }

  /** 滚动位置记忆的存储键（按歌单区分） */
  /** 退出页面时记住滚动位置（读写由 SonglistScrollMemory 负责） */
  private saveScrollPosition(): void {
    void saveScrollOffset(this.lastSourceId, this.lastListId, this.getSongListOffsetY(),
      this.rememberScrollPosition, this.detailLoaded);
  }

  /** 列表渲染后恢复上次滚动位置 */
  private async restoreScrollPosition(): Promise<void> {
    if (!this.rememberScrollPosition) {
      return;
    }
    const offset = await loadScrollOffset(this.lastSourceId, this.lastListId);
    if (offset <= 0) {
      return;
    }
    // 等一帧让列表完成布局，否则 scrollTo 会被忽略
    setTimeout(() => {
      try {
        this.songListScroller.scrollTo({ xOffset: 0, yOffset: offset, animation: false });
        hilog.info(0x0001, 'SonglistDetail', 'Scroll restored to %{public}d', offset);
      } catch (err) {
        hilog.warn(0x0001, 'SonglistDetail', 'scrollTo failed: %{public}s', JSON.stringify(err));
      }
    }, 120);
  }

  private getSongListOffsetY(): number {
    return scrollerOffsetY(this.songListScroller);
  }

  private getSourceLabel(): string {
    const src = (this.listInfo.source ?? '').trim();
    if (src.length === 0) {
      return '--';
    }
    return src.toUpperCase();
  }

  /** 宿主 Ability 上下文（下载上下文 / 分享 / 打开外链共用一处） */
  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear() {
    hilog.info(0x0001, 'SonglistDetail', 'SonglistDetailPage appearing');
    // 初始化下载上下文
    setDownloadContext(this.hostContext());
    // 防止重复加载
    if (this.detailLoaded) {
      hilog.info(0x0001, 'SonglistDetail', 'Detail already loaded, skipping');
      return;
    }
    // 从导航参数获取歌单信息
    const params = navigationService.getCurrentParams() as NavigationParams;
    if (params && params.songListId && params.songListSource) {
      hilog.info(0x0001, 'SonglistDetail', 'Loading with params - id: %{public}s, source: %{public}s',
        params.songListId, params.songListSource);
      this.loadSonglistDetail(params.songListSource, params.songListId);
    } else {
      hilog.warn(0x0001, 'SonglistDetail', 'No navigation params found');
      this.isLoading = false;
      this.hasError = true;
    }
  }

  aboutToDisappear(): void {
    this.saveScrollPosition();
  }

  onBackPressed(): boolean {
    navigationService.back();
    return true;
  }

  /** 头部：交给 SonglistDetailHeader（展开/收缩两态） */
  @Builder
  Header() {
    SonglistDetailHeader({
      listName: this.listInfo.name,
      creator: this.listInfo.creator,
      description: this.listInfo.desc,
      cover: this.listInfo.pic,
      sourceLabel: this.getSourceLabel(),
      songCount: this.songList.length,
      playCount: this.listInfo.playCount,
      compact: this.headerCompact,
      onPlayAll: (): void => {
        void this.playAll();
      },
      onCollect: (): void => {
        void this.toggleCollect();
      },
    })
  }

  @Builder
  SongList() {
    List({ space: 8, scroller: this.songListScroller }) {
      LazyForEach(this.songListSource, (song: SongItem, index: number) => {
        ListItem() {
          ListRow({
            index: index + 1,
            title: song.name,
            subtitle: this.buildSubtitle(song),
            trailingText: this.showListDuration ? this.formatSongDuration(song) : '',
            active: song.isPlaying,
            divider: false,
            onTap: (): void => {
              if (this.selectMode) {
                this.toggleSelect(index);
              } else {
                void this.playSong(index);
              }
            },
            onLongPress: (): void => {
              if (!this.selectMode) {
                void this.openSongMenu(song);
              }
            },
            trailing: (): void => {
              this.SongRowTrailing(song, index);
            },
          })
        }
        .stateStyles({ pressed: this.pressDim })
      }, (song: SongItem, index: number) => `${song.id}_${song.source}_${index}`)
    }
    .width('100%')
    .layoutWeight(1)
    // 大屏内容列居中（平板/PC 上歌曲行不拉满整屏）
    .padding({
      left: 12 + Breakpoints.contentInset(this.windowWidthVp),
      right: 12 + Breakpoints.contentInset(this.windowWidthVp),
      bottom: 8,
    })
    .edgeEffect(EdgeEffect.None)
    .onDidScroll(() => {
      const y = this.getSongListOffsetY();
      if (y > 18 && !this.headerCompact) {
        this.headerCompact = true;
      } else if (y <= 4 && this.headerCompact) {
        this.headerCompact = false;
      }
    })
  }

  /** 行尾：多选态给勾选圆点，普通态给 ⋮ 菜单 */
  @Builder
  SongRowTrailing(song: SongItem, index: number) {
    if (this.selectMode) {
      Stack() {
        if (this.isSelected(index)) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(26)
            .fontColor([DesignTokens.accent()])
        } else {
          Circle({ width: 22, height: 22 })
            .fill(Color.Transparent)
            .stroke(DesignTokens.labelTertiary(this.theme))
            .strokeWidth(1.5)
        }
      }
      .width(DesignTokens.touchTarget())
      .height(DesignTokens.touchTarget())
    } else {
      Stack() {
        Circle({ width: 28, height: 28 })
          .fill(DesignTokens.mutedFill(this.theme))
        Image($r('app.media.ic_pd_more'))
          .width(14)
          .height(14)
          .fillColor(DesignTokens.labelSecondary(this.theme))
      }
      .width(DesignTokens.touchTarget())
      .height(DesignTokens.touchTarget())
      .accessibilityText(t('a11y_more'))
      .onClick(() => {
        void this.openSongMenu(song);
      })
    }
  }

  // NavDestination onReady callback
  onReady(params: Record<string, object | string | number | boolean | undefined>): void {
    // 防止重复加载
    if (this.detailLoaded) {
      hilog.info(0x0001, 'SonglistDetail', 'Detail already loaded, skipping onReady');
      return;
    }
    const songListId: string = (params.songListId as string) || '';
    const songListSource: string = (params.songListSource as string) || '';
    hilog.info(0x0001, 'SonglistDetail', 'onReady - id: %{public}s, source: %{public}s', songListId, songListSource);
    if (songListId && songListSource) {
      this.loadSonglistDetail(songListSource, songListId);
    } else {
      hilog.error(0x0001, 'SonglistDetail', 'Missing params: id=%{public}s, source=%{public}s', songListId, songListSource);
    }
  }

  /** 加载歌单详情：数据在 SonglistDetail/SonglistLoader，页面只应用结果 */
  async loadSonglistDetail(source: string, id: string) {
    hilog.info(0x0001, 'SonglistDetail', 'Loading detail for source: %{public}s, id: %{public}s', source, id);
    this.isLoading = true;
    this.hasError = false;
    this.lastSourceId = source;
    this.lastListId = id;

    const outcome: SonglistLoadOutcome = source === 'local'
      ? loadLocalSonglist(id)
      : await loadOnlineSonglist(source, id);

    if (outcome.status === 'ok' && outcome.info && outcome.songs) {
      this.listInfo = outcome.info;
      this.listCoverLoadFailed = false;
      this.songList = outcome.songs;
      this.songListSource.reload(this.songList);
      this.detailLoaded = true;
      this.isLoading = false;
      void this.restoreScrollPosition();
      return;
    }
    // unsupported（该源没有详情接口）与 error 都按「加载失败」处理，页面展示错误态
    this.hasError = outcome.status === 'error';
    this.detailLoaded = false;
    this.isLoading = false;
  }


  /** 播放单首（点行）：流程在 SonglistDetail/SonglistPlayActions */
  async playSong(index: number): Promise<void> {
    if (this.songList.length === 0) {
      return;
    }
    markPlayingRow(this.songList, index);
    this.songListSource.reload(this.songList);

    const result = await playSongRow(this.songList, index, this.listInfo, this.listClickPlay);
    if (result === 'no-url') {
      // 回滚播放态，避免列表看起来"在播但没声音"
      clearPlayingRows(this.songList);
      this.songListSource.reload(this.songList);
      this.showToast(t('toast_play_url_failed'));
    }
  }

  /** 播放全部：等价于点第一行（第一行会显示为播放中） */
  async playAll(): Promise<void> {
    if (this.songList.length === 0) {
      return;
    }
    const result = await playAllRows(this.songList, this.listInfo);
    if (result === 'no-url') {
      this.showToast(t('toast_play_url_failed'));
      return;
    }
    if (result === 'ok') {
      markPlayingRow(this.songList, 0);
      this.songListSource.reload(this.songList);
    }
  }

  /** 收藏：语义在 SonglistDetail/SonglistCollectActions */
  async toggleCollect(): Promise<void> {
    if (this.collectBusy) {
      return;
    }
    this.collectBusy = true;
    try {
      const outcome = await collectSonglist(this.listInfo, this.toast());
      if (outcome.kind === 'menu') {
        await this.openCollectedMenu();
      }
    } finally {
      this.collectBusy = false;
    }
  }

  /** 已收藏时的菜单：更新内容 / 取消收藏 */
  private async openCollectedMenu(): Promise<void> {
    // 统一走 DialogService：「取消收藏」用危险色，取消项由系统菜单提供
    const picked = await appActionMenu(this.listInfo.name, [
      t('list_sync_content'),
      t('toast_uncollected_action'),
    ], { dangerIndexes: [1] });
    if (picked === 0) {
      void this.syncBoundList();
    } else if (picked === 1) {
      void this.uncollect();
    }
  }

  /** 更新歌单内容（列表级同步） */
  private async syncBoundList(): Promise<void> {
    await syncBoundSonglist(this.listInfo, this.toast());
  }

  /** 取消收藏（删除绑定列表） */
  private async uncollect(): Promise<void> {
    await uncollectSonglist(this.listInfo, this.confirm(), this.toast());
  }

  // 显示提示
  private showToast(message: string): void {
    showAppToast(this.getUIContext(), message, TOAST_DURATION_SHORT);
  }





  private actionTarget(): SonglistTarget {
    return { source: this.listInfo.source, listId: this.listInfo.id, name: this.listInfo.name };
  }

  /** 批量加入默认列表 */
  private async batchAddToPlaylist(): Promise<void> {
    await batchAddToDefaultList(this.selectedSongs(), this.toast());
    this.exitSelectMode();
  }

  /** 批量下载 */
  private async batchDownload(): Promise<void> {
    await batchDownloadSongs(this.selectedSongs(), this.confirm(), this.toast());
    this.exitSelectMode();
  }

  /** 批量移出本地歌单（在线歌单只读） */
  private async batchRemove(): Promise<void> {
    const songs = this.selectedSongs();
    const removed = await batchRemoveFromLocalList(
      this.actionTarget(), songs, this.confirm(), this.toast());
    if (removed < 0) {
      return;
    }
    this.songList = this.songList.filter((song: SongItem) => !this.containsSong(songs, song));
    this.songListSource.reload(this.songList);
    this.exitSelectMode();
  }

  /** 二次确认：统一走 DialogService.appConfirm（取消返回 false） */
  private showConfirmDialog(title: string, message: string): Promise<boolean> {
    return appConfirm(title, message);
  }

  /** 传给动作模块的两个回调 */
  private confirm(): (title: string, message: string) => Promise<boolean> {
    return (title: string, message: string): Promise<boolean> => this.showConfirmDialog(title, message);
  }

  private toast(): (message: string) => void {
    return (message: string): void => {
      this.showToast(message);
    };
  }

  private enterSelectMode(song?: SongItem): void {
    this.selectMode = true;
    if (song) {
      const index = this.indexOfSong(song);
      this.selectedIndexes = index >= 0 ? [index] : [];
    } else {
      this.selectedIndexes = [];
    }
  }

  private exitSelectMode(): void {
    this.selectMode = false;
    this.selectedIndexes = [];
  }

  /** 多选的纯计算在 SonglistDetail/SonglistSelection，页面只做赋值 */
  private indexOfSong(song: SongItem): number {
    return indexOfRowRef(this.songList, song);
  }

  private isSelected(index: number): boolean {
    return this.selectedIndexes.indexOf(index) >= 0;
  }

  private toggleSelect(index: number): void {
    this.selectedIndexes = toggleIndex(this.selectedIndexes, index);
  }

  private selectAllSongs(): void {
    if (isAllSelected(this.selectedIndexes, this.songList.length)) {
      this.selectedIndexes = [];
      return;
    }
    this.selectedIndexes = allIndexes(this.songList.length);
  }

  private selectedSongs(): SongItem[] {
    return rowsAt(this.songList, this.selectedIndexes);
  }

  private containsSong(songs: SongItem[], target: SongItem): boolean {
    return containsRowRef(songs, target);
  }

  // ===== 排序 =====



  private applySort(): void {
    const field = this.sortField as SortField;
    const order = this.sortOrder as SortOrder;
    const locale = this.language.replace('_', '-');
    this.songList = sortRows(this.songList, field, order, locale);
    this.songListSource.reload(this.songList);
    this.showSortSheet = false;
    this.showToast(tf('toast_sorted_count', [this.songList.length.toString()]));

    // 本地列表排序结果要落库，否则退出再进又变回原顺序
    if (this.canEditLocalList()) {
      void persistLocalOrder(this.listInfo.id, this.songList);
    }
  }

  // ===== 去重 =====

  private async runDedupe(): Promise<void> {
    if (this.songList.length < 2) {
      this.showToast(t('list_dedupe_none'));
      return;
    }
    const duplicateGroups = countDuplicateGroupsOf(this.songList, this.dedupeFilterVariant);
    if (duplicateGroups === 0) {
      this.showToast(t('list_dedupe_none'));
      return;
    }
    const confirmed = await this.showConfirmDialog(
      t('list_dedupe'),
      tf('confirm_dedupe_songs', [duplicateGroups.toString()]));
    if (!confirmed) {
      return;
    }
    const outcome = dedupeRows(this.songList, this.dedupeFilterVariant);
    const removed = outcome.removed;
    this.songList = outcome.rows;
    this.songListSource.reload(this.songList);
    // 本地歌单：同步把重复项从存储里删掉，避免下次进来又出现
    if (this.listInfo.source === 'local') {
      await persistLocalOrder(this.listInfo.id, this.songList);
    }
    this.exitSelectMode();
    this.showToast(tf('toast_dedupe_done', [removed.toString()]));
  }

  /** 下载整张歌单：流程在 SonglistDetail/SonglistActions（逐首提交 + 进度汇总） */
  private async downloadAll(): Promise<void> {
    await downloadWholeList(this.actionTarget(), this.songList, this.confirm(), this.toast());
  }

  /** 同步成本地自建歌单：流程在 SonglistDetail/SonglistLocalLibrary */
  private async syncToLocalList(): Promise<void> {
    await syncOnlineListToLocal(this.listInfo, this.songList, this.confirm(), this.toast());
  }

  /** 打开单曲菜单（长按行 / 行尾 ⋮）：动作集合见 SonglistMenus */
  private async openSongMenu(song: SongItem): Promise<void> {
    await showSongItemMenu(song, {
      onPlayLater: (target: SongItem): void => {
        playerService.insertNext(songRowToQueueItem(target));
        this.showToast(tf('toast_play_later_added', [target.name]));
      },
      onAddToList: (target: SongItem): void => {
        void this.addToPlaylist(target);
      },
      onDownload: (target: SongItem): void => {
        void this.downloadSongFromMenu(target);
      },
      onShare: (target: SongItem): void => {
        void this.shareSong(target);
      },
      onSelectMode: (target: SongItem): void => {
        this.enterSelectMode(target);
      },
      onDislike: (target: SongItem): void => {
        void this.showDislikeMenu(target);
      },
      onSourceDetail: (target: SongItem): void => {
        this.openSourceDetail(target);
      },
      onViewArtist: (target: SongItem): void => {
        this.viewArtist(target);
      },
      onViewAlbum: (target: SongItem): void => {
        this.viewAlbum(target);
      },
      onMovePosition: (target: SongItem): void => {
        this.openMovePosition(target);
      },
      onMoveToList: (target: SongItem): void => {
        this.openMoveToList(target);
      },
    }, {
      // 只有本地（我的）列表能改顺序/移动；在线歌单是只读的
      canEditPosition: this.canEditLocalList(),
      canMoveToList: this.canEditLocalList() && this.buildMoveTargetOptions().length > 0,
    });
  }

  /** 打开该歌曲在对应平台的详情页（外部浏览器） */
  private openSourceDetail(song: SongItem): void {
    const url = sourceDetailUrl(song);
    if (!openInBrowser(this.hostContext(), url)) {
      this.showToast(t('toast_operation_failed'));
    }
  }

  /** 不喜欢：歌曲 / 歌手 / 歌名三种粒度（与播放页同一套规则） */
  private async showDislikeMenu(song: SongItem): Promise<void> {
    const picked = await appActionMenu(t('dislike_title'), [
      t('dislike_song'),
      t('dislike_singer'),
      t('dislike_name'),
    ]);
    if (picked < 0) {
      return;
    }
    try {
      const count = await addRowToDislike(song, picked);
      this.showToast(tf('dislike_added', [count.toString()]));
    } catch (err) {
      hilog.warn(0x0001, 'SonglistDetail', 'addDislike failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_operation_failed'));
    }
  }

  /** 顶部「更多」菜单：排序 / 去重 / 多选 / 同步到本地歌单（动作集合见 SonglistMenus） */
  private async openMoreMenu(): Promise<void> {
    await showSonglistMoreMenu(this.listInfo.name, {
      onSort: (): void => {
        this.showSortSheet = true;
      },
      onDedupe: (): void => {
        void this.runDedupe();
      },
      onSelectMode: (): void => {
        this.enterSelectMode();
      },
      onDownloadAll: (): void => {
        void this.downloadAll();
      },
      onSyncLocal: (): void => {
        void this.syncToLocalList();
      },
    });
  }


  // ===== 调整位置 / 移动到其他列表（仅本地列表）=====

  /** 在线歌单是只读的：只有本地（我的）列表能改顺序和移动 */
  private canEditLocalList(): boolean {
    return this.listInfo.source === 'local' && this.listInfo.id.length > 0;
  }

  /** 按存储顺序刷新本地列表（位置调整/移动后调用，避免看到的顺序和库里不一致） */
  private refreshLocalRows(): void {
    if (!this.canEditLocalList()) {
      return;
    }
    this.songList = musicRowListToSongItems(getUserListMusic(this.listInfo.id));
    this.songListSource.reload(this.songList);
  }

  /** 可移动的目标列表（排除当前列表） */
  /** 可移动的目标歌单（实现在 SonglistDetail/SonglistMoveActions） */
  private buildMoveTargetOptions(): SettingOption[] {
    return buildMoveTargetOptions(this.listInfo.id);
  }
  /** 调整位置：面板默认填当前所在位置 */
  private openMovePosition(song: SongItem): void {
    this.movePositionTarget = song;
    this.movePositionValue = positionOf(this.songList, song.id).toString();
    this.showMovePositionSheet = true;
  }
  /** 应用位置调整 */
  private async applyMovePosition(value: string): Promise<void> {
    const song = this.movePositionTarget;
    this.movePositionTarget = null;
    if (!song) {
      return;
    }
    const ok = await applyMovePosition(this.listInfo.id, song, value, this.songList, this.toast());
    if (ok) {
      this.refreshLocalRows();
    }
  }
  /** 移动到其他列表 */
  private openMoveToList(song: SongItem): void {
    const options = this.buildMoveTargetOptions();
    if (options.length === 0) {
      this.showToast(t('list_move_no_target'));
      return;
    }
    this.moveToListTarget = song;
    this.moveToListOptions = options;
    this.showMoveToListSheet = true;
  }

  /** 「移动」= 加入目标列表 + 从当前列表移除（与安卓版 move_to 语义一致） */
  private async applyMoveToList(listId: string): Promise<void> {
    const song = this.moveToListTarget;
    this.moveToListTarget = null;
    if (!song) {
      return;
    }
    const ok = await applyMoveToList(this.listInfo.id, song, listId, this.toast());
    if (ok) {
      this.refreshLocalRows();
    }
  }
  // 添加到歌单
  private async addToPlaylist(song: SongItem): Promise<void> {
    const error = await addRowToDefaultList(song);
    this.showToast(error.length === 0
      ? tf('toast_added_to_default', [song.name])
      : t('toast_add_to_list_failed') + ': ' + error);
  }

  // 下载单曲（从菜单调用）
  private async downloadSongFromMenu(song: SongItem): Promise<void> {
    const error = await downloadRow(song);
    this.showToast(error.length === 0
      ? tf('toast_download_start_song', [song.name])
      : t('toast_download_failed') + ': ' + error);
  }

  // 分享歌曲
  private async shareSong(song: SongItem): Promise<void> {
    // 与播放页分享一致：按「设置 → 分享方式」走系统分享，失败回退剪贴板
    const result = await shareSongRow(this.hostContext(), song, sourceLabel(song.source));
    if (result === 'clipboard') {
      this.showToast(t('toast_share_copy'));
    } else if (result === 'failed') {
      this.showToast(t('toast_operation_failed'));
    }
  }

  // 查看歌手
  private viewArtist(song: SongItem): void {
    if (!song.singer || song.singer.length === 0) {
      this.showToast(t('toast_operation_failed'));
      return;
    }
    // 返回首页并由首页发起一次按歌手名的搜索
    emitSearchRequest(song.singer);
    navigationService.back();
  }

  // 查看专辑
  private viewAlbum(song: SongItem): void {
    if (!song.album || song.album.length === 0) {
      this.showToast(t('toast_operation_failed'));
      return;
    }
    emitSearchRequest(song.album);
    navigationService.back();
  }

  build() {
    Column() {
      NavBar({
        title: t('songlist_title'),
        trailing: (): void => {
          this.NavTrailingAction();
        },
      })

      if (this.isLoading) {
        // 加载中：用骨架列表代替转圈，避免整屏白等
        Column() {
          ForEach([0, 1, 2, 3, 4, 5], (index: number) => {
            SkeletonListItem()
          }, (index: number) => `songlist_skeleton_${index}`)
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.hasError) {
        // 失败态：统一状态视图（带重试按钮），与其它页面同一套
        StateView({
          state: 'error',
          message: t('load_failed_hint'),
          actionText: t('retry'),
          onAction: (): void => {
            this.reloadDetail();
          },
        })
          .width('100%')
          .layoutWeight(1)
      } else if (this.songList.length === 0) {
        // 空状态
        Column() {
          Text(t('songlist_empty'))
            .fontSize(14)
            .fontColor(DesignTokens.labelSecondary(this.theme))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 歌单信息头部
        this.Header()

        // 歌曲列表
        this.SongList()

        // 多选批量操作栏
        if (this.selectMode) {
          this.BatchBar()
        }
      }

      // 播放器栏（组件内部处理底部沉浸）
      PlayerBar({ immersiveBottom: true })

      // 面板类浮层：必须在 build 中挂载才会渲染（此前排序面板漏挂，点了没反应）
      this.SortSheet()
      this.MovePositionSheet()
      this.MoveToListSheet()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /** 顶栏右侧：普通态给「更多」，多选态给「完成」 */
  @Builder
  NavTrailingAction() {
    if (this.selectMode) {
      Text(t('list_select_done'))
        .fontSize(14)
        .fontColor(DesignTokens.accent())
        .padding({ left: 10, right: 4, top: 6, bottom: 6 })
        .onClick(() => {
          this.exitSelectMode();
        })
    } else {
      Stack() {
        Circle({ width: 34, height: 34 })
          .fill(DesignTokens.mutedFill(this.theme))
        Image($r('app.media.ic_pd_more'))
          .width(16)
          .height(16)
          .fillColor(DesignTokens.labelPrimary(this.theme))
      }
      .width(DesignTokens.touchTarget())
      .height(DesignTokens.touchTarget())
      .accessibilityText(t('a11y_more'))
      .onClick(() => {
        this.openMoreMenu();
      })
    }
  }

  /** 多选批量操作栏（组件化） */
  @Builder
  BatchBar() {
    SonglistBatchBar({
      selectedCount: this.selectedIndexes.length,
      totalCount: this.songList.length,
      removable: this.listInfo.source === 'local',
      onToggleSelectAll: (): void => {
        this.selectAllSongs();
      },
      onAddToList: (): void => {
        void this.batchAddToPlaylist();
      },
      onDownload: (): void => {
        void this.batchDownload();
      },
      onRemove: (): void => {
        void this.batchRemove();
      },
    })
  }

  /** 排序面板（组件化，含字段 + 方式选择） */
  @Builder
  SortSheet() {
    SonglistSortSheet({
      visible: $showSortSheet,
      field: this.sortField,
      order: this.sortOrder,
      onApply: (field: string, order: string): void => {
        this.sortField = field;
        this.sortOrder = order;
        this.applySort();
      },
    })
  }

  /** 调整位置：输入 1 起始的位置 */
  @Builder
  MovePositionSheet() {
    InputSheet({
      visible: $showMovePositionSheet,
      title: t('list_change_position'),
      placeholder: tf('list_position_placeholder', [this.songList.length.toString()]),
      value: this.movePositionValue,
      numberOnly: true,
      onSubmit: (value: string): void => {
        void this.applyMovePosition(value);
      },
    })
  }

  /** 移动到其他列表 */
  @Builder
  MoveToListSheet() {
    SelectSheet({
      visible: $showMoveToListSheet,
      title: t('list_move_to'),
      options: this.moveToListOptions,
      value: '',
      onPick: (listId: string): void => {
        void this.applyMoveToList(listId);
      },
    })
  }
}
