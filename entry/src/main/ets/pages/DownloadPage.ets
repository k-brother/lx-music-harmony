// 下载管理页面
// 对应安卓版的下载管理功能

import hilog from '@ohos.hilog';
import { BusinessError } from '@kit.BasicServicesKit';
import { DownloadTask, DownloadStatus, download, setDownloadContext } from '../core/music/MusicFeatureEntry';
import { common } from '@kit.AbilityKit';
import { DesignTokens } from '../theme/DesignTokens';

const DOMAIN: number = 0x0001;
const TAG: string = 'DownloadPage';

interface PromptPickResult {
  index: number;
}

@Component
export struct DownloadPage {
  @StorageProp('theme') theme: string = 'light';
  @State downloadTasks: DownloadTask[] = [];
  @State selectedTasks: Set<string> = new Set();
  @State isSelectMode: boolean = false;
  /** 0 全部 1 进行中 2 已完成 3 失败 */
  @State filterTabIndex: number = 0;

  private refreshInterval: number | null = null;

  /** 当前 Tab 下要展示的任务 */
  getFilteredTasks(): DownloadTask[] {
    const all: DownloadTask[] = this.downloadTasks;
    if (this.filterTabIndex === 0) {
      return all;
    }
    if (this.filterTabIndex === 1) {
      return all.filter((t: DownloadTask) =>
        t.status === DownloadStatus.PENDING ||
        t.status === DownloadStatus.DOWNLOADING ||
        t.status === DownloadStatus.PAUSED);
    }
    if (this.filterTabIndex === 2) {
      return all.filter((t: DownloadTask) => t.status === DownloadStatus.COMPLETED);
    }
    if (this.filterTabIndex === 3) {
      return all.filter((t: DownloadTask) => t.status === DownloadStatus.FAILED);
    }
    return [];
  }

  /** 多选作用域：当前列表 Tab 下的可见任务 */
  getTasksForSelectScope(): DownloadTask[] {
    return this.getFilteredTasks();
  }

  private countActiveTasks(): number {
    let n = 0;
    for (let i = 0; i < this.downloadTasks.length; i++) {
      const t = this.downloadTasks[i];
      if (t.status === DownloadStatus.PENDING ||
        t.status === DownloadStatus.DOWNLOADING ||
        t.status === DownloadStatus.PAUSED) {
        n++;
      }
    }
    return n;
  }

  private countCompletedTasks(): number {
    let n = 0;
    for (let i = 0; i < this.downloadTasks.length; i++) {
      if (this.downloadTasks[i].status === DownloadStatus.COMPLETED) {
        n++;
      }
    }
    return n;
  }

  private countFailedTasks(): number {
    let n = 0;
    for (let i = 0; i < this.downloadTasks.length; i++) {
      if (this.downloadTasks[i].status === DownloadStatus.FAILED) {
        n++;
      }
    }
    return n;
  }

  isAllScopeSelected(): boolean {
    const scope: DownloadTask[] = this.getTasksForSelectScope();
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

  hasAnyCompleted(): boolean {
    return this.downloadTasks.some((t: DownloadTask) => t.status === DownloadStatus.COMPLETED);
  }

  aboutToAppear() {
    this.setDownloadContext();
    this.refreshDownloadTasks();
    
    // 定时刷新下载任务状态
    this.refreshInterval = setInterval(() => {
      this.refreshDownloadTasks();
    }, 1000);
  }

  // 设置下载上下文
  setDownloadContext() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      setDownloadContext(context);
      hilog.info(DOMAIN, TAG, 'Download context set successfully');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to set download context: %{public}s', JSON.stringify(err));
    }
  }

  aboutToDisappear() {
    if (this.refreshInterval) {
      clearInterval(this.refreshInterval);
      this.refreshInterval = null;
    }
  }

  refreshDownloadTasks() {
    this.downloadTasks = download.getAllDownloadTasks();
  }

  toggleSelectMode() {
    this.isSelectMode = !this.isSelectMode;
    if (!this.isSelectMode) {
      this.selectedTasks = new Set();
    }
  }

  toggleTaskSelection(taskId: string) {
    const next: Set<string> = new Set(this.selectedTasks);
    if (next.has(taskId)) {
      next.delete(taskId);
    } else {
      next.add(taskId);
    }
    this.selectedTasks = next;
  }

  selectAllTasks() {
    const scope: DownloadTask[] = this.getTasksForSelectScope();
    if (scope.length === 0) {
      return;
    }
    const next: Set<string> = new Set(this.selectedTasks);
    if (this.isAllScopeSelected()) {
      scope.forEach((task: DownloadTask) => {
        next.delete(task.id);
      });
    } else {
      scope.forEach((task: DownloadTask) => {
        next.add(task.id);
      });
    }
    this.selectedTasks = next;
  }

  async pauseSelectedTasks() {
    for (const taskId of this.selectedTasks) {
      download.pauseDownload(taskId);
    }
    this.refreshDownloadTasks();
  }

  async resumeSelectedTasks() {
    for (const taskId of this.selectedTasks) {
      await download.resumeDownload(taskId);
    }
    this.refreshDownloadTasks();
  }

  async cancelSelectedTasks() {
    for (const taskId of this.selectedTasks) {
      download.cancelDownload(taskId);
    }
    this.selectedTasks = new Set();
    this.refreshDownloadTasks();
  }

  clearCompletedTasks() {
    download.clearCompletedTasks();
    this.refreshDownloadTasks();
    hilog.info(DOMAIN, TAG, '已清理已完成的任务');
  }

  getStatusText(status: DownloadStatus): string {
    switch (status) {
      case DownloadStatus.PENDING: return '等待中';
      case DownloadStatus.DOWNLOADING: return '下载中';
      case DownloadStatus.PAUSED: return '已暂停';
      case DownloadStatus.COMPLETED: return '已完成';
      case DownloadStatus.FAILED: return '失败';
      default: return '未知';
    }
  }

  getStatusColor(status: DownloadStatus): string {
    switch (status) {
      case DownloadStatus.PENDING: return '#FFA500';
      case DownloadStatus.DOWNLOADING: return '#4CAF50';
      case DownloadStatus.PAUSED: return '#FF9800';
      case DownloadStatus.COMPLETED: return '#1565C0';
      case DownloadStatus.FAILED: return '#F44336';
      default: return '#9E9E9E';
    }
  }

  /** 顶区：设置返回 / 多选栏 / 或「统计分段 + 操作」 */
  @Builder
  buildTopChrome() {
    Column() {
      Row() {
        if (this.isSelectMode) {
          Row({ space: 6 }) {
            Text('✕')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(DesignTokens.labelPrimary(this.theme))
            Text('取消')
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(DesignTokens.labelPrimary(this.theme))
          }
          .padding({ left: 2, right: 8, top: 8, bottom: 8 })
          .onClick(() => {
            this.toggleSelectMode();
          })
        } else {
          Text('下载')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(DesignTokens.labelPrimary(this.theme))
        }

        Blank()
          .layoutWeight(1)

        Row({ space: 4 }) {
          Image($r('app.media.ic_common_multiselect'))
            .width(14)
            .height(14)
            .fillColor(DesignTokens.accent())
          Text(this.isSelectMode ? (this.isAllScopeSelected() ? '取消全选' : '全选') : '多选')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.accent())
        }
        .padding({ top: 8, bottom: 8, left: 12, right: 12 })
        .backgroundColor(DesignTokens.accentSoft(this.theme))
        .borderRadius(16)
        .onClick(() => {
          if (this.isSelectMode) {
            this.selectAllTasks();
          } else {
            this.toggleSelectMode();
          }
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14, bottom: 8 })
      .alignItems(VerticalAlign.Center)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

      Column() {
        this.buildSegmentStrip()
      }
      .width('100%')
      .backgroundColor(DesignTokens.card(this.theme))
      .borderRadius(DesignTokens.radiusCard())
      .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
      .margin({ left: 12, right: 12, bottom: 8 })
    }
    .width('100%')
    .backgroundColor(DesignTokens.chromeBar(this.theme))
  }

  @Builder
  buildSegmentStrip() {
    Row({ space: 8 }) {
      this.FilterTabButton(0, `全部 (${this.downloadTasks.length})`)
      this.FilterTabButton(1, `进行中 (${this.countActiveTasks()})`)
      this.FilterTabButton(2, `已完成 (${this.countCompletedTasks()})`)
      this.FilterTabButton(3, `失败 (${this.countFailedTasks()})`)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
  }

  @Builder
  FilterTabButton(index: number, text: string) {
    Row() {
      Text(text)
        .fontSize(13)
        .fontWeight(this.filterTabIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.filterTabIndex === index ? DesignTokens.accent() : DesignTokens.labelSecondary(this.theme))
    }
    .layoutWeight(1)
    .height(36)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.filterTabIndex === index ? DesignTokens.accentSoft(this.theme) : 'rgba(0,0,0,0)')
    .border({ width: 0.5, color: this.filterTabIndex === index ? DesignTokens.accentSoft(this.theme) : DesignTokens.cardBorder(this.theme) })
    .borderRadius(10)
    .onClick(() => {
      this.filterTabIndex = index;
    })
  }

  @Builder
  buildToolbar() {
    if (this.isSelectMode) {
      Row() {
        Image(this.isAllScopeSelected() ?
          $r('sys.symbol.checkmark_square_fill') : $r('sys.symbol.square'))
          .width(22)
          .height(22)
          .fillColor(DesignTokens.accent())
          .onClick(() => {
            this.selectAllTasks();
          })

        Text('全选')
          .fontSize(15)
          .fontColor(DesignTokens.accent())
          .margin({ left: 8 })
          .fontWeight(FontWeight.Medium)
          .onClick(() => {
            this.selectAllTasks();
          })

        if (this.selectedTasks.size === 0) {
          Text('轻触列表项进行选择')
            .fontSize(12)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .margin({ left: 12 })
            .layoutWeight(1)
        } else {
          Blank()
            .layoutWeight(1)
        }

        if (this.selectedTasks.size > 0 && this.hasSelectedTasksWithStatus(DownloadStatus.DOWNLOADING)) {
          Image($r('sys.symbol.pause'))
            .width(22)
            .height(22)
            .fillColor(DesignTokens.accent())
            .margin({ right: 14 })
            .onClick(() => {
              void this.pauseSelectedTasks();
            })
        }

        if (this.selectedTasks.size > 0 && this.hasSelectedTasksWithStatus(DownloadStatus.PAUSED)) {
          Image($r('sys.symbol.play'))
            .width(22)
            .height(22)
            .fillColor(DesignTokens.accent())
            .margin({ right: 14 })
            .onClick(() => {
              void this.resumeSelectedTasks();
            })
        }

        if (this.selectedTasks.size > 0) {
          Image($r('sys.symbol.xmark'))
            .width(22)
            .height(22)
            .fillColor('#F44336')
            .onClick(() => {
              void this.cancelSelectedTasks();
            })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: 48 })
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(DesignTokens.mutedFill(this.theme))
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  buildTaskItem(task: DownloadTask) {
    Row() {
      Column()
        .width(4)
        .constraintSize({ minHeight: 88 })
        .backgroundColor(this.getStatusColor(task.status))
        .borderRadius({ topLeft: 12, bottomLeft: 12 })

      Row() {
        if (this.isSelectMode) {
          Image(this.selectedTasks.has(task.id) ?
            $r('sys.symbol.checkmark_square_fill') : $r('sys.symbol.square'))
            .width(22)
            .height(22)
            .fillColor(DesignTokens.accent())
            .margin({ right: 12 })
        }

        Column() {
          Text(task.musicInfo.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(`${task.musicInfo.singer} · ${task.musicInfo.album || '未知专辑'}`)
            .fontSize(13)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Row() {
            Text(this.getStatusText(task.status))
              .fontSize(11)
              .fontColor(this.getStatusColor(task.status))
              .fontWeight(FontWeight.Medium)
            Text(` · ${task.quality}`)
              .fontSize(11)
              .fontColor(DesignTokens.labelTertiary(this.theme))
              .margin({ left: 4 })
            Text(` · ${this.formatFileSize(task.downloadedSize)}/${this.formatFileSize(task.totalSize)}`)
              .fontSize(11)
              .fontColor(DesignTokens.labelTertiary(this.theme))
              .margin({ left: 4 })
          }
          .margin({ top: 8 })

          if (task.status === DownloadStatus.DOWNLOADING || task.status === DownloadStatus.PAUSED) {
            Progress({
              value: task.progress,
              total: 100
            })
              .width('100%')
              .height(4)
              .color(this.getStatusColor(task.status))
              .backgroundColor(DesignTokens.mutedFill(this.theme))
              .margin({ top: 10 })
          }

          if (task.status === DownloadStatus.FAILED && task.error) {
            Text(task.error)
              .fontSize(11)
              .fontColor('#F44336')
              .margin({ top: 6 })
              .maxLines(2)
          }
        }
        .layoutWeight(1)

        if (!this.isSelectMode) {
          Column() {
            if (task.status === DownloadStatus.DOWNLOADING) {
              Image($r('sys.symbol.pause'))
                .width(22)
                .height(22)
                .fillColor(DesignTokens.accent())
                .onClick(() => {
                  download.pauseDownload(task.id);
                })
            } else if (task.status === DownloadStatus.PAUSED) {
              Image($r('sys.symbol.play'))
                .width(22)
                .height(22)
                .fillColor(DesignTokens.accent())
                .onClick(() => {
                  void download.resumeDownload(task.id);
                })
            } else if (task.status === DownloadStatus.FAILED) {
              Image($r('sys.symbol.arrow_clockwise'))
                .width(22)
                .height(22)
                .fillColor(DesignTokens.accent())
                .onClick(() => {
                  void this.retryDownload(task.id);
                })
            }

            if (task.status !== DownloadStatus.COMPLETED) {
              Image($r('sys.symbol.xmark'))
                .width(22)
                .height(22)
                .fillColor('#F44336')
                .margin({ top: 14 })
                .onClick(() => {
                  download.cancelDownload(task.id);
                })
            }
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 8 })
        }
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
      .padding({ top: 14, bottom: 14, left: 12, right: 14 })
    }
    .width('100%')
    .margin({ left: 12, right: 12, top: 8 })
    .borderRadius(DesignTokens.radiusCard())
    .clip(true)
    .backgroundColor(DesignTokens.card(this.theme))
    .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (this.isSelectMode) {
        this.toggleTaskSelection(task.id);
      }
    })
  }

  @Builder
  buildEmptyState() {
    Column() {
      Image($r('sys.symbol.arrow_down_circle'))
        .width(64)
        .height(64)
        .fillColor('#CCCCCC')
        .margin({ bottom: 16 })

      Text('暂无下载任务')
        .fontSize(16)
        .fontColor(this.theme === 'dark' ? '#AAAAAA' : '#666666')
        .margin({ bottom: 8 })

      Text('在歌单、排行榜或搜索结果中发起下载后，将显示在此处')
        .fontSize(13)
        .fontColor('#999999')
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
    }
    .width('100%')
    .constraintSize({ minHeight: 280 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  buildEmptyForFilter() {
    Column() {
      Image($r('sys.symbol.arrow_down_circle'))
        .width(56)
        .height(56)
        .fillColor('#CCCCCC')
        .margin({ bottom: 14 })

      if (this.filterTabIndex === 1) {
        Text('没有进行中的任务')
          .fontSize(16)
          .fontColor(this.theme === 'dark' ? '#AAAAAA' : '#666666')
        Text('等待、下载中与暂停的任务会出现在「进行中」')
          .fontSize(13)
          .fontColor('#999999')
          .margin({ top: 8 })
          .textAlign(TextAlign.Center)
          .padding({ left: 28, right: 28 })
      } else if (this.filterTabIndex === 2) {
        Text('还没有已完成的下载')
          .fontSize(16)
          .fontColor(this.theme === 'dark' ? '#AAAAAA' : '#666666')
        Text('完成后可在「已完成」中查看或清理')
          .fontSize(13)
          .fontColor('#999999')
          .margin({ top: 8 })
          .textAlign(TextAlign.Center)
          .padding({ left: 28, right: 28 })
      } else if (this.filterTabIndex === 3) {
        Text('没有失败记录')
          .fontSize(16)
          .fontColor(this.theme === 'dark' ? '#AAAAAA' : '#666666')
        Text('失败任务可在此重试或删除')
          .fontSize(13)
          .fontColor('#999999')
          .margin({ top: 8 })
          .textAlign(TextAlign.Center)
          .padding({ left: 28, right: 28 })
      } else {
        this.buildEmptyState()
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 280 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Column() {
      this.buildTopChrome()
      Scroll() {
        Column() {
          if (this.getFilteredTasks().length === 0) {
            this.buildEmptyForFilter()
          } else {
            ForEach(this.getFilteredTasks(), (task: DownloadTask, index: number) => {
              this.buildTaskItem(task);
            }, (task: DownloadTask) => task.id)
          }

          if (this.hasAnyCompleted() && (this.filterTabIndex === 0 || this.filterTabIndex === 2)) {
            Row() {
              Text('清理所有已完成')
                .fontSize(14)
                .fontColor(DesignTokens.accent())
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .height(48)
            .margin({ left: 12, right: 12, top: 12 })
            .borderRadius(DesignTokens.radiusCard())
            .backgroundColor(DesignTokens.card(this.theme))
            .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
            .onClick(() => {
              this.clearCompletedTasks();
            })
          }
        }
        .width('100%')
        .padding({ top: 8, bottom: 24 })
      }
      .layoutWeight(1)
      .backgroundColor(DesignTokens.pageBg(this.theme))
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }

  private hasSelectedTasksWithStatus(status: DownloadStatus): boolean {
    for (const taskId of this.selectedTasks) {
      const task: DownloadTask | undefined = this.downloadTasks.find((t: DownloadTask) => t.id === taskId);
      if (task && task.status === status) {
        return true;
      }
    }
    return false;
  }

   private formatFileSize(bytes: number): string {
    if (bytes === 0) return '0 B';
    
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
  }

  // 重新下载失败的任务
  private async retryDownload(taskId: string): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, 'Retrying download: %{public}s', taskId);
      
      // 查找任务
      const task = this.downloadTasks.find((t: DownloadTask) => t.id === taskId);
      if (!task) {
        this.showToast('任务不存在');
        return;
      }
      
      // 显示确认对话框
      const confirmed = await this.showConfirmDialog(
        '重新下载',
        `确定要重新下载 "${task.musicInfo.name}" 吗？`
      );
      
      if (!confirmed) {
        return;
      }
      
      // 对于失败的任务，需要重新创建下载任务
      // 首先取消当前任务
      await download.cancelDownload(taskId);
      
      // 重新创建下载任务
      const newTaskId = await this.recreateDownloadTask(task);
      
      if (newTaskId) {
        this.showToast('已开始重新下载');
        hilog.info(DOMAIN, TAG, 'Retry download started with new task: %{public}s', newTaskId);
      } else {
        this.showToast('重新下载失败');
        hilog.error(DOMAIN, TAG, 'Failed to recreate download task: %{public}s', taskId);
      }
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to retry download: %{public}s', errorMsg);
      this.showToast('重新下载失败: ' + errorMsg);
    }
  }

  private showConfirmDialog(title: string, message: string): Promise<boolean> {
    return new Promise((resolve: (v: boolean) => void) => {
      this.getUIContext().getPromptAction().showDialog({
        title: title,
        message: message,
        buttons: [
          { text: '取消', color: DesignTokens.labelSecondary(this.theme) },
          { text: '确定', color: DesignTokens.accent() },
        ],
      }, (err: BusinessError, data: PromptPickResult) => {
        if (err) {
          resolve(false);
          return;
        }
        resolve(data.index === 1);
      });
    });
  }

  // 重新创建下载任务
  private async recreateDownloadTask(task: DownloadTask): Promise<string | null> {
    try {
      // 创建新的下载任务
      const newTaskId = await download.startDownload({
        musicInfo: task.musicInfo,
        quality: task.quality
      });
      
      return newTaskId;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to recreate download task: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2200,
      });
    } catch (_e) {
      hilog.info(DOMAIN, TAG, 'Toast fallback: %{public}s', message);
    }
  }
}