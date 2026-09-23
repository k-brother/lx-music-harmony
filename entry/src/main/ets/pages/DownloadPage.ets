/**
 * 下载管理页（编排层）
 *
 * 832 行 → 这一版只负责「状态 + 串联」：
 * - 纯逻辑（筛选/计数/状态文案与配色/行模型）在 `pages/Download/DownloadView.ets`
 * - 任务行在 `pages/Download/DownloadTaskRow.ets`
 * - 多选批量栏在 `pages/Download/DownloadSelectionBar.ets`
 * - 顶栏/空态/分段控件复用 UI Kit（NavBar / StateView / SegmentedBar / RefreshContainer）
 *
 * 顺带修掉的三处体验问题：
 * 1. 多选栏把「全选」写成了「播放全部」，空选时又显示「暂无数据」；
 * 2. 暂停中的任务文案显示成「下载中」，无法区分；
 * 3. 底部「清空已完成」按钮只有「已完成」两个字，看不出是操作。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { DesignTokens } from '../theme/DesignTokens';
import { Breakpoints } from '../theme/Breakpoints';
import { t, tf } from '../service/LocalizationService';
import { appConfirm, appToast } from '../service/DialogService';
import { hapticService } from '../service/HapticService';
import { playerService, type SongInfo } from '../service/PlayerService';
import { download, setDownloadContext, DownloadStatus, type DownloadTask } from '../core/music/MusicFeatureEntry';
import { parsePlayTime } from '../utils/CommonUtils';
import { NavBar } from '../components/ui/NavBar';
import { SegmentedBar } from '../components/ui/SegmentedBar';
import { RefreshContainer } from '../components/ui/RefreshContainer';
import { StateView } from '../components/ui/StateView';
import { DownloadTaskRow } from './Download/DownloadTaskRow';
import { DownloadSelectionBar } from './Download/DownloadSelectionBar';
import {
  DownloadFilter,
  countDownloadTasks,
  downloadTasksSignature,
  filterDownloadTasks,
  isActiveStatus,
  toDownloadRowModel,
  type DownloadCounts,
  type DownloadRowModel,
} from './Download/DownloadView';

const DOMAIN: number = 0x0001;
const TAG: string = 'DownloadPage';
/** 轮询间隔：只用来刷新进度，真正的重绘由「指纹变化」决定 */
const POLL_INTERVAL_MS: number = 1000;

@Component
export struct DownloadPage {
  @StorageProp('theme') theme: string = 'light';
  /** 一多：窗口宽度（vp），大屏内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
  /** 设置 → 列表 → 显示专辑（下载列表副标题与其它列表同一口径） */
  @StorageProp('showListAlbum') showListAlbum: boolean = true;
  @State downloadTasks: DownloadTask[] = [];
  @State rows: DownloadRowModel[] = [];
  @State selectedTasks: Set<string> = new Set();
  @State isSelectMode: boolean = false;
  @State filter: DownloadFilter = DownloadFilter.ALL;
  @State isRefreshing: boolean = false;
  @State counts: DownloadCounts = { all: 0, active: 0, completed: 0, failed: 0 };

  private refreshInterval: number | null = null;
  /** 上次渲染的数据指纹：进度没变就不重建列表 */
  private lastSignature: string = '';

  aboutToAppear() {
    this.attachDownloadContext();
    this.reload();
    this.refreshInterval = setInterval((): void => {
      this.reload();
    }, POLL_INTERVAL_MS);
  }

  aboutToDisappear() {
    if (this.refreshInterval !== null) {
      clearInterval(this.refreshInterval);
      this.refreshInterval = null;
    }
  }

  /** 下载模块需要 UIAbilityContext 才能写公共目录 */
  private attachDownloadContext(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      setDownloadContext(context);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'attachDownloadContext failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 拉取任务并重建行模型。
   * signature 用来避免「每秒无脑赋值新数组」造成的整列表重建（进度没动时不重绘）。
   */
  private reload(): void {
    const tasks = download.getAllDownloadTasks();
    const signature = downloadTasksSignature(tasks);
    if (signature === this.lastSignature) {
      return;
    }
    this.lastSignature = signature;
    this.downloadTasks = tasks;
    this.counts = countDownloadTasks(tasks);
    // 筛选切换 / 任务被删掉后，选中集合里可能残留看不见的 id，这里收敛一次
    this.selectedTasks = this.pruneSelection(this.selectedTasks, tasks);
    this.rebuildRows();
  }

  private pruneSelection(selected: Set<string>, tasks: DownloadTask[]): Set<string> {
    if (selected.size === 0) {
      return selected;
    }
    const visible = new Set<string>();
    const scope = filterDownloadTasks(tasks, this.filter);
    for (let i = 0; i < scope.length; i++) {
      visible.add(scope[i].id);
    }
    let changed = false;
    const next = new Set<string>();
    selected.forEach((id: string): void => {
      if (visible.has(id)) {
        next.add(id);
      } else {
        changed = true;
      }
    });
    return changed ? next : selected;
  }

  private rebuildRows(): void {
    const scope = filterDownloadTasks(this.downloadTasks, this.filter);
    const rows: DownloadRowModel[] = [];
    for (let i = 0; i < scope.length; i++) {
      rows.push(toDownloadRowModel(scope[i], this.selectedTasks.has(scope[i].id), this.isSelectMode,
        this.showListAlbum));
    }
    this.rows = rows;
    if (rows.length === 0 && this.isSelectMode) {
      this.exitSelectMode();
    }
  }

  private enterSelectMode(): void {
    hapticService.light();
    this.isSelectMode = true;
    this.rebuildRows();
  }

  private exitSelectMode(): void {
    this.isSelectMode = false;
    this.selectedTasks = new Set();
    this.rebuildRows();
  }

  private toggleTaskSelection(taskId: string): void {
    hapticService.selection();
    const next = new Set(this.selectedTasks);
    if (next.has(taskId)) {
      next.delete(taskId);
    } else {
      next.add(taskId);
    }
    this.selectedTasks = next;
    this.rebuildRows();
  }

  private allScopeSelected(): boolean {
    const scope = filterDownloadTasks(this.downloadTasks, this.filter);
    if (scope.length === 0) {
      return false;
    }
    for (let i = 0; i < scope.length; i++) {
      if (!this.selectedTasks.has(scope[i].id)) {
        return false;
      }
    }
    return true;
  }

  private toggleSelectAll(): void {
    const scope = filterDownloadTasks(this.downloadTasks, this.filter);
    const next = new Set(this.selectedTasks);
    if (this.allScopeSelected()) {
      for (let i = 0; i < scope.length; i++) {
        next.delete(scope[i].id);
      }
    } else {
      for (let i = 0; i < scope.length; i++) {
        next.add(scope[i].id);
      }
    }
    this.selectedTasks = next;
    this.rebuildRows();
  }

  private selectedTaskList(): DownloadTask[] {
    const result: DownloadTask[] = [];
    this.downloadTasks.forEach((task: DownloadTask): void => {
      if (this.selectedTasks.has(task.id)) {
        result.push(task);
      }
    });
    return result;
  }

  private hasSelectedStatus(predicate: (status: DownloadStatus) => boolean): boolean {
    const selected = this.selectedTaskList();
    for (let i = 0; i < selected.length; i++) {
      if (predicate(selected[i].status)) {
        return true;
      }
    }
    return false;
  }

  private async pauseSelected(): Promise<void> {
    if (this.selectedTasks.size === 0) {
      return;
    }
    this.selectedTaskList().forEach((task: DownloadTask): void => {
      if (task.status === DownloadStatus.DOWNLOADING) {
        download.pauseDownload(task.id);
      }
    });
    appToast(t('download_paused'));
    this.reload();
  }

  private async resumeSelected(): Promise<void> {
    if (this.selectedTasks.size === 0) {
      return;
    }
    const resumable = this.selectedTaskList().filter((task: DownloadTask): boolean =>
      task.status === DownloadStatus.PENDING || task.status === DownloadStatus.PAUSED);
    for (let i = 0; i < resumable.length; i++) {
      await download.resumeDownload(resumable[i].id);
    }
    this.reload();
  }

  /** 批量删除：二次确认（对齐商业 App 的破坏性操作习惯） */
  private async deleteSelected(): Promise<void> {
    const ids: string[] = [];
    this.selectedTasks.forEach((id: string): void => {
      ids.push(id);
    });
    if (ids.length === 0) {
      return;
    }
    const confirmed = await appConfirm(
      t('delete'),
      tf('confirm_delete_download', [ids.length.toString()]),
      { danger: true, confirmText: t('delete') });
    if (!confirmed) {
      return;
    }
    for (let i = 0; i < ids.length; i++) {
      download.cancelDownload(ids[i]);
    }
    this.selectedTasks = new Set();
    appToast(tf('toast_download_deleted', [ids.length.toString()]));
    this.reload();
  }

  private async clearCompleted(): Promise<void> {
    download.clearCompletedTasks();
    this.lastSignature = '';
    this.reload();
    hilog.info(DOMAIN, TAG, 'cleared completed download tasks');
  }

  private async retryTask(task: DownloadTask): Promise<void> {
    const confirmed = await appConfirm(
      t('retry_download'),
      tf('confirm_redownload', [task.musicInfo.name]));
    if (!confirmed) {
      return;
    }
    await download.cancelDownload(task.id);
    const newTaskId = await download.startDownload({
      musicInfo: task.musicInfo,
      quality: task.quality,
    });
    appToast(newTaskId ? t('toast_redownload_started') : t('toast_redownload_failed'));
    this.lastSignature = '';
    this.reload();
  }

  private async startTask(task: DownloadTask): Promise<void> {
    await download.resumeDownload(task.id);
    this.lastSignature = '';
    this.reload();
  }

  private async playTask(task: DownloadTask): Promise<void> {
    const filePath = task.filePath;
    if (!filePath) {
      appToast(t('file_not_found'));
      return;
    }
    const info = task.musicInfo;
    const duration = info.interval ? parsePlayTime(info.interval) : 0;
    const songInfo: SongInfo = {
      id: info.id || task.id,
      songmid: info.songmid || info.id || '',
      url: filePath,
      title: info.name || t('unknown_song'),
      artist: info.singer || t('unknown_artist'),
      album: info.albumName || info.album || '',
      artwork: info.img || info.pic || null,
      duration: duration,
      source: info.source || 'local',
    };
    try {
      await playerService.setSource(songInfo, filePath, songInfo.duration);
      await playerService.play();
      hilog.info(DOMAIN, TAG, 'play downloaded task: %{public}s', info.name);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'playTask failed: %{public}s', JSON.stringify(err));
      appToast(t('file_corrupted'));
    }
  }

  private findTask(taskId: string): DownloadTask | undefined {
    return this.downloadTasks.find((task: DownloadTask): boolean => task.id === taskId);
  }

  private emptyMessage(): string {
    if (this.downloadTasks.length === 0) {
      return t('download_empty_hint');
    }
    if (this.filter === DownloadFilter.ACTIVE) {
      return t('download_empty_active');
    }
    if (this.filter === DownloadFilter.COMPLETED) {
      return t('download_empty_completed');
    }
    if (this.filter === DownloadFilter.FAILED) {
      return t('download_empty_failed');
    }
    return t('download_empty_hint');
  }

  /** 顶栏右侧：多选入口 / 取消多选 */
  @Builder
  NavTrailing() {
    Text(this.isSelectMode ? t('cancel') : t('multiselect'))
      .fontSize(DesignTokens.fontCaption())
      .fontColor(DesignTokens.accent())
      .fontWeight(FontWeight.Medium)
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.isSelectMode ? DesignTokens.mutedFill(this.theme) : DesignTokens.accentSoft(this.theme))
      .borderRadius(DesignTokens.radiusPill())
      .onClick(() => {
        if (this.isSelectMode) {
          this.exitSelectMode();
        } else {
          this.enterSelectMode();
        }
      })
  }

  @Builder
  FilterBar() {
    Column() {
      SegmentedBar({
        variant: 'chip',
        options: [
          { id: '0', label: `${t('download_all')} (${this.counts.all})` },
          { id: '1', label: `${t('download_active')} (${this.counts.active})` },
          { id: '2', label: `${t('download_completed')} (${this.counts.completed})` },
          { id: '3', label: `${t('download_failed')} (${this.counts.failed})` },
        ],
        activeId: this.filter.toString(),
        onSelect: (id: string): void => {
          this.filter = parseInt(id, 10) as DownloadFilter;
          this.selectedTasks = this.pruneSelection(this.selectedTasks, this.downloadTasks);
          this.rebuildRows();
        },
      })
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    }
    .width('100%')
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
    .margin({ left: 12, right: 12, bottom: 8 })
  }

  @Builder
  ClearCompletedRow() {
    Row() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(DesignTokens.fontHeading())
        .fontColor([DesignTokens.accent()])
      Text(t('download_clear_completed'))
        .fontSize(DesignTokens.fontBody())
        .fontColor(DesignTokens.accent())
        .margin({ left: 6 })
    }
    .width('100%')
    .height(DesignTokens.touchTarget())
    .justifyContent(FlexAlign.Center)
    .margin({ left: 12, right: 12, top: 12 })
    .borderRadius(DesignTokens.radiusCard())
    .backgroundColor(DesignTokens.card(this.theme))
    .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
    .onClick(() => {
      void this.clearCompleted();
    })
  }

  @Builder
  Content() {
    Scroll() {
      Column() {
        if (this.rows.length === 0) {
          StateView({
            state: 'empty',
            message: this.emptyMessage(),
            iconRes: $r('sys.symbol.arrow_down_circle'),
          })
            .margin({ top: 40 })
        } else {
          ForEach(this.rows, (row: DownloadRowModel): void => {
            this.TaskRow(row)
            // key 带上「会影响外观的状态」：对象型 @Prop 在节点复用时不一定触发重绘
            // （设置页 ForEach 就是踩过这个坑），进度按 5% 分桶避免每个百分点都重建。
          }, (row: DownloadRowModel): string =>
            `${row.id}_${row.statusText}_${row.selected}_${row.selectMode}_${Math.floor(row.progress / 5)}`)
        }

        if (this.counts.completed > 0 &&
          (this.filter === DownloadFilter.ALL || this.filter === DownloadFilter.COMPLETED)) {
          this.ClearCompletedRow()
        }
      }
      .width('100%')
      .padding({ top: 8, bottom: 24 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.TopStart)
  }

  /**
   * 单个下载任务行（含四个回调）。
   * 四个动作都先按 id 找任务：列表可能在等待期间被刷新，找不到就提示而不是静默失败。
   */
  @Builder
  TaskRow(row: DownloadRowModel) {
    DownloadTaskRow({
      row: row,
      onToggleSelect: (): void => this.toggleTaskSelection(row.id),
      onPrimaryAction: (): void => {
        const task = this.findTask(row.id);
        if (!task) {
          appToast(t('task_not_found'));
          return;
        }
        if (task.status === DownloadStatus.FAILED) {
          void this.retryTask(task);
        } else if (task.status === DownloadStatus.DOWNLOADING) {
          download.pauseDownload(task.id);
          this.reload();
        } else {
          void this.startTask(task);
        }
      },
      onDelete: (): void => {
        if (!this.findTask(row.id)) {
          appToast(t('task_not_found'));
          return;
        }
        download.cancelDownload(row.id);
        this.lastSignature = '';
        this.reload();
      },
      onPlay: (): void => {
        const task = this.findTask(row.id);
        if (!task) {
          appToast(t('task_not_found'));
          return;
        }
        void this.playTask(task);
      },
    })
      .margin({ left: 12, right: 12, top: 8 })
  }

  build() {
    Column() {
      NavBar({
        title: t('download_title'),
        // 下载管理是底部导航的一级页，没有上一级可返回，不显示返回箭头
        showBack: false,
        trailing: (): void => {
          this.NavTrailing();
        },
      })

      this.FilterBar()

      // 自定义组件后面不能直接挂 layoutWeight，用一层 Column 承担剩余高度
      Column() {
        RefreshContainer({
          refreshing: $isRefreshing,
          onRefresh: (): void => {
            hapticService.selection();
            this.lastSignature = '';
            this.reload();
            this.isRefreshing = false;
          },
        }) {
          this.Content()
        }
      }
      .layoutWeight(1)
      .width('100%')
      // 大屏内容列居中（任务卡在 PC 上不该拉满整屏）
      .padding({
        left: Breakpoints.contentInset(this.windowWidthVp),
        right: Breakpoints.contentInset(this.windowWidthVp),
      })

      if (this.isSelectMode) {
        DownloadSelectionBar({
          selectedCount: this.selectedTasks.size,
          allSelected: this.allScopeSelected(),
          hasDownloading: this.hasSelectedStatus((status: DownloadStatus): boolean =>
            status === DownloadStatus.DOWNLOADING),
          hasResumable: this.hasSelectedStatus((status: DownloadStatus): boolean =>
            isActiveStatus(status) && status !== DownloadStatus.DOWNLOADING),
          onToggleSelectAll: (): void => this.toggleSelectAll(),
          onPauseAll: (): void => {
            void this.pauseSelected();
          },
          onResumeAll: (): void => {
            void this.resumeSelected();
          },
          onDeleteAll: (): void => {
            void this.deleteSelected();
          },
        })
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }
}
