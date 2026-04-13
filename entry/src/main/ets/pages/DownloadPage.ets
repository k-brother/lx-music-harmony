// 下载管理页面
// 对应安卓版的下载管理功能

import hilog from '@ohos.hilog';
import { navigationService, RouteName } from '../service/NavigationService';
import { DownloadTask, DownloadStatus, download, setDownloadContext } from '../core/music/MusicFeatureEntry';
import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'DownloadPage';

@Component
export struct DownloadPage {
  @StorageProp('theme') theme: string = 'light';
  @State downloadTasks: DownloadTask[] = [];
  @State selectedTasks: Set<string> = new Set();
  @State isSelectMode: boolean = false;
  @State downloadPath: string = '/storage/emulated/0/Download/LxMusic';
  @State autoStartDownload: boolean = true;
  @State maxConcurrentDownloads: number = 3;
  /** 0 全部 1 进行中 2 已完成 3 失败 4 设置 */
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
    if (this.filterTabIndex === 4) {
      return [];
    }
    return this.getFilteredTasks();
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
    this.loadDownloadSettings();
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

  async loadDownloadSettings() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'download_settings');
      
      this.downloadPath = await pref.get('downloadPath', '/storage/emulated/0/Download/LxMusic') as string;
      this.autoStartDownload = await pref.get('autoStartDownload', true) as boolean;
      this.maxConcurrentDownloads = await pref.get('maxConcurrentDownloads', 3) as number;
      
      hilog.info(DOMAIN, TAG, 'Download settings loaded');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to load download settings: %{public}s', JSON.stringify(err));
    }
  }

  async saveDownloadSettings() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'download_settings');
      
      await pref.put('downloadPath', this.downloadPath);
      await pref.put('autoStartDownload', this.autoStartDownload);
      await pref.put('maxConcurrentDownloads', this.maxConcurrentDownloads);
      
      await pref.flush();
      hilog.info(DOMAIN, TAG, 'Download settings saved');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save download settings: %{public}s', JSON.stringify(err));
    }
  }

  refreshDownloadTasks() {
    this.downloadTasks = download.getAllDownloadTasks();
  }

  toggleSelectMode() {
    if (this.filterTabIndex === 4) {
      this.filterTabIndex = 0;
    }
    this.isSelectMode = !this.isSelectMode;
    if (!this.isSelectMode) {
      this.selectedTasks.clear();
    }
  }

  toggleTaskSelection(taskId: string) {
    if (this.selectedTasks.has(taskId)) {
      this.selectedTasks.delete(taskId);
    } else {
      this.selectedTasks.add(taskId);
    }
  }

  selectAllTasks() {
    const scope: DownloadTask[] = this.getTasksForSelectScope();
    if (scope.length === 0) {
      return;
    }
    if (this.isAllScopeSelected()) {
      scope.forEach((task: DownloadTask) => {
        this.selectedTasks.delete(task.id);
      });
    } else {
      scope.forEach((task: DownloadTask) => {
        this.selectedTasks.add(task.id);
      });
    }
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
    this.selectedTasks.clear();
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

  @Builder
  buildHeader() {
    Row() {
      if (this.isSelectMode) {
        // 选择模式下的头部
        Text(`已选择 ${this.selectedTasks.size} 项`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .layoutWeight(1)
        
        Text('取消')
          .fontSize(14)
          .fontColor(this.theme === 'dark' ? '#AAAAAA' : '#666666')
          .onClick(() => {
            this.toggleSelectMode();
          })
      } else {
        // 正常模式下的头部
        Text('下载中心')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#1A1A1A')
          .layoutWeight(1)

        Text('多选')
          .fontSize(14)
          .fontColor(this.filterTabIndex === 4 ? '#999999' : '#E63946')
          .opacity(this.filterTabIndex === 4 ? 0.45 : 1)
          .onClick(() => {
            if (this.filterTabIndex !== 4) {
              this.toggleSelectMode();
            }
          })
      }
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  FilterChip(index: number, label: string) {
    Text(label)
      .fontSize(14)
      .fontWeight(this.filterTabIndex === index ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.filterTabIndex === index ? '#E63946' : (this.theme === 'dark' ? '#AAAAAA' : '#666666'))
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor(this.filterTabIndex === index ?
        (this.theme === 'dark' ? '#2D2224' : '#FFE8EB') :
        (this.theme === 'dark' ? '#252525' : '#EEEEEE'))
      .borderRadius(20)
      .margin({ right: 8 })
      .onClick(() => {
        if (index === 4) {
          this.isSelectMode = false;
          this.selectedTasks.clear();
        }
        this.filterTabIndex = index;
      })
  }

  @Builder
  buildFilterTabs() {
    Scroll() {
      Row() {
        this.FilterChip(0, '全部')
        this.FilterChip(1, '进行中')
        this.FilterChip(2, '已完成')
        this.FilterChip(3, '失败')
        this.FilterChip(4, '设置')
      }
      .padding({ left: 8, right: 8, top: 4, bottom: 8 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
  }

  @Builder
  buildToolbar() {
    if (this.isSelectMode && this.selectedTasks.size > 0) {
      Row() {
        // 全选按钮
        Image(this.isAllScopeSelected() ?
          $r('sys.symbol.checkmark_square_fill') : $r('sys.symbol.square'))
          .width(20)
          .height(20)
          .fillColor('#E63946')
          .onClick(() => {
            this.selectAllTasks();
          })
        
        Text('全选')
          .fontSize(14)
          .fontColor('#E63946')
          .margin({ left: 8 })
          .onClick(() => {
            this.selectAllTasks();
          })
        
        Blank()
        
        // 操作按钮
        if (this.hasSelectedTasksWithStatus(DownloadStatus.DOWNLOADING)) {
          Image($r('sys.symbol.pause'))
            .width(20)
            .height(20)
            .fillColor('#E63946')
            .margin({ right: 16 })
            .onClick(() => {
              this.pauseSelectedTasks();
            })
        }

        if (this.hasSelectedTasksWithStatus(DownloadStatus.PAUSED)) {
          Image($r('sys.symbol.play'))
            .width(20)
            .height(20)
            .fillColor('#E63946')
            .margin({ right: 16 })
            .onClick(() => {
              this.resumeSelectedTasks();
            })
        }

        Image($r('sys.symbol.xmark'))
          .width(20)
          .height(20)
          .fillColor('#F44336')
          .onClick(() => {
            this.cancelSelectedTasks();
          })
      }
      .width('100%')
      .height(48)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.theme === 'dark' ? '#2C2C2C' : '#F5F5F5')
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  buildTaskItem(task: DownloadTask, isLast: boolean) {
    Column() {
      Row() {
        if (this.isSelectMode) {
          // 选择框
          Image(this.selectedTasks.has(task.id) ? 
            $r('sys.symbol.checkmark_square_fill') : $r('sys.symbol.square'))
            .width(20)
            .height(20)
            .fillColor('#E63946')
            .margin({ right: 12 })
        }

        Column() {
          // 歌曲信息
          Text(task.musicInfo.name)
            .fontSize(15)
            .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
            .maxLines(1)
          
          Text(`${task.musicInfo.singer} - ${task.musicInfo.album || '未知专辑'}`)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 2 })
            .maxLines(1)
          
          // 下载信息
          Row() {
            Text(this.getStatusText(task.status))
              .fontSize(11)
              .fontColor(this.getStatusColor(task.status))
            
            Text(` · ${task.quality}`)
              .fontSize(11)
              .fontColor('#999999')
              .margin({ left: 4 })
            
            Text(` · ${this.formatFileSize(task.downloadedSize)}/${this.formatFileSize(task.totalSize)}`)
              .fontSize(11)
              .fontColor('#999999')
              .margin({ left: 4 })
          }
          .margin({ top: 4 })
          
          // 进度条
          if (task.status === DownloadStatus.DOWNLOADING || task.status === DownloadStatus.PAUSED) {
            Progress({
              value: task.progress,
              total: 100
            })
              .width('100%')
              .height(4)
              .color(this.getStatusColor(task.status))
              .backgroundColor('#E0E0E0')
              .margin({ top: 8 })
          }
          
          // 错误信息
          if (task.status === DownloadStatus.FAILED && task.error) {
            Text(`错误: ${task.error}`)
              .fontSize(11)
              .fontColor('#F44336')
              .margin({ top: 4 })
              .maxLines(2)
          }
        }
        .layoutWeight(1)
        
        // 操作按钮
        if (!this.isSelectMode) {
          if (task.status === DownloadStatus.DOWNLOADING) {
            Image($r('sys.symbol.pause'))
              .width(20)
              .height(20)
              .fillColor('#E63946')
              .onClick(() => {
                download.pauseDownload(task.id);
              })
          } else if (task.status === DownloadStatus.PAUSED) {
            Image($r('sys.symbol.play'))
              .width(20)
              .height(20)
              .fillColor('#E63946')
              .onClick(() => {
                download.resumeDownload(task.id);
              })
           } else if (task.status === DownloadStatus.FAILED) {
            Image($r('sys.symbol.arrow_clockwise'))
              .width(20)
              .height(20)
              .fillColor('#E63946')
              .onClick(() => {
                // 重新下载
                this.retryDownload(task.id);
              })
          }
          
          if (task.status !== DownloadStatus.COMPLETED) {
            Image($r('sys.symbol.xmark'))
              .width(20)
              .height(20)
              .fillColor('#F44336')
              .margin({ left: 12 })
              .onClick(() => {
                download.cancelDownload(task.id);
              })
          }
        }
      }
      .width('100%')
      .padding({ top: 12, bottom: 12, left: 16, right: 16 })

      if (!isLast) {
        Divider()
          .strokeWidth(0.5)
          .color(this.theme === 'dark' ? '#333333' : '#E8E8E8')
          .margin({ left: this.isSelectMode ? 48 : 16, right: 16 })
      }
    }
    .width('100%')
    .margin({ left: 12, right: 12, top: 6 })
    .borderRadius(12)
    .clip(true)
    .backgroundColor(this.theme === 'dark' ? '#252525' : '#FFFFFF')
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

  @Builder
  buildSettings() {
    Column() {
      Text('下载设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
        .padding({ left: 16, top: 16, bottom: 12 })
        .width('100%')
      
      // 下载路径设置
      Row() {
        Column() {
          Text('下载路径')
            .fontSize(14)
            .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          Text(this.downloadPath)
            .fontSize(12)
            .fontColor('#999999')
            .margin({ top: 2 })
            .maxLines(1)
        }
        .layoutWeight(1)
        
        Image($r('sys.symbol.chevron_right'))
          .width(16)
          .height(16)
          .fillColor('#999999')
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
       .onClick(() => {
        // 选择下载路径
        this.selectDownloadPath();
      })
      
      Divider()
        .strokeWidth(0.5)
        .color(this.theme === 'dark' ? '#2C2C2C' : '#E8E8E8')
        .margin({ left: 16, right: 16 })
      
      // 自动开始下载
      Row() {
        Text('自动开始下载')
          .fontSize(14)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .layoutWeight(1)
        
        Toggle({ type: ToggleType.Switch, isOn: this.autoStartDownload })
          .onChange((isOn: boolean) => {
            this.autoStartDownload = isOn;
            this.saveDownloadSettings();
          })
      }
      .width('100%')
      .height(50)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
      
      Divider()
        .strokeWidth(0.5)
        .color(this.theme === 'dark' ? '#2C2C2C' : '#E8E8E8')
        .margin({ left: 16, right: 16 })
      
      // 同时下载数量
      Row() {
        Text('同时下载数量')
          .fontSize(14)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .layoutWeight(1)
        
        Text(this.maxConcurrentDownloads.toString())
          .fontSize(14)
          .fontColor('#999999')
          .margin({ right: 8 })
        
        Image($r('sys.symbol.chevron_right'))
          .width(16)
          .height(16)
          .fillColor('#999999')
      }
      .width('100%')
      .height(50)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
       .onClick(() => {
        // 选择同时下载数量
        this.selectMaxConcurrentDownloads();
      })
    }
    .width('100%')
    .margin({ top: 8 })
    .padding({ bottom: 24 })
  }

  build() {
    Column() {
      this.buildHeader()
      this.buildToolbar()
      this.buildFilterTabs()

      if (this.filterTabIndex === 4) {
        Scroll() {
          Column() {
            this.buildSettings()
          }
          .width('100%')
        }
        .layoutWeight(1)
        .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
      } else {
        Scroll() {
          Column() {
            if (this.getFilteredTasks().length === 0) {
              this.buildEmptyForFilter()
            } else {
              ForEach(this.getFilteredTasks(), (task: DownloadTask, index: number) => {
                this.buildTaskItem(task, index === this.getFilteredTasks().length - 1);
              }, (task: DownloadTask) => task.id)
            }

            if (this.hasAnyCompleted() && (this.filterTabIndex === 0 || this.filterTabIndex === 2)) {
              Row() {
                Text('清理所有已完成')
                  .fontSize(14)
                  .fontColor('#E63946')
                  .layoutWeight(1)
                  .textAlign(TextAlign.Center)
              }
              .width('100%')
              .height(48)
              .margin({ left: 12, right: 12, top: 12 })
              .borderRadius(12)
              .backgroundColor(this.theme === 'dark' ? '#252525' : '#FFFFFF')
              .onClick(() => {
                this.clearCompletedTasks();
              })
            }
          }
          .width('100%')
          .padding({ top: 8, bottom: 24 })
        }
        .layoutWeight(1)
        .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
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

  // 显示确认对话框
  private async showConfirmDialog(title: string, message: string): Promise<boolean> {
    // 在实际应用中，这里应该显示一个确认对话框
    // 暂时返回true（用户确认）
    hilog.info(DOMAIN, TAG, 'Confirm dialog: %{public}s - %{public}s', title, message);
    return true;
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

  // 选择下载路径
  private async selectDownloadPath(): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, 'Selecting download path');
      
      // 在实际应用中，这里应该使用文件选择器选择目录
      // 暂时使用固定路径选择对话框
      
      const pathOptions = [
        '/storage/emulated/0/Download/LxMusic',
        '/storage/emulated/0/Music/LxMusic',
        '/storage/emulated/0/DCIM/LxMusic'
      ];
      
      // 显示路径选择对话框
      const selectedPath = await this.showPathSelector('选择下载路径', pathOptions);
      
      if (selectedPath) {
        this.downloadPath = selectedPath;
        await this.saveDownloadSettings();
        this.showToast('下载路径已更新: ' + selectedPath);
      } else {
        this.showToast('已取消选择');
      }
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to select download path: %{public}s', errorMsg);
      this.showToast('选择下载路径失败: ' + errorMsg);
    }
  }

  // 显示路径选择器
  private async showPathSelector(title: string, options: string[]): Promise<string | null> {
    // 在实际应用中，这里应该显示一个路径选择对话框
    // 暂时选择第一个选项作为示例
    hilog.info(DOMAIN, TAG, 'Path selector: %{public}s', title);
    for (const option of options) {
      hilog.info(DOMAIN, TAG, '  - %{public}s', option);
    }
    
    if (options.length > 0) {
      return options[0];
    }
    
    return null;
  }

  // 选择同时下载数量
  private async selectMaxConcurrentDownloads(): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, 'Selecting max concurrent downloads');
      
      // 可选的下载数量
      const countOptions = [1, 2, 3, 5, 10];
      
      // 显示数量选择对话框
      const selectedCount = await this.showCountSelector('选择同时下载数量', countOptions);
      
      if (selectedCount !== null) {
        this.maxConcurrentDownloads = selectedCount;
        await this.saveDownloadSettings();
        
        // 更新下载服务的并发数量
        await this.updateDownloadConcurrency(selectedCount);
        
        this.showToast(`同时下载数量已设置为: ${selectedCount}`);
      } else {
        this.showToast('已取消选择');
      }
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to select max concurrent downloads: %{public}s', errorMsg);
      this.showToast('设置同时下载数量失败: ' + errorMsg);
    }
  }

  // 显示数量选择器
  private async showCountSelector(title: string, options: number[]): Promise<number | null> {
    // 在实际应用中，这里应该显示一个数量选择对话框
    // 暂时选择当前值或第一个选项
    hilog.info(DOMAIN, TAG, 'Count selector: %{public}s', title);
    for (const option of options) {
      hilog.info(DOMAIN, TAG, '  - %{public}d', option);
    }
    
    // 如果当前值在选项中，返回当前值，否则返回第一个选项
    if (options.includes(this.maxConcurrentDownloads)) {
      return this.maxConcurrentDownloads;
    } else if (options.length > 0) {
      return options[0];
    }
    
    return null;
  }

  // 更新下载并发数量
  private async updateDownloadConcurrency(maxConcurrent: number): Promise<void> {
    try {
      // 在实际应用中，这里应该更新下载服务的并发设置
      // 暂时只记录日志
      hilog.info(DOMAIN, TAG, 'Updated download concurrency to: %{public}d', maxConcurrent);
      
      // 如果有正在下载的任务超过并发数，暂停部分任务
      const downloadingTasks = this.downloadTasks.filter(task => 
        task.status === DownloadStatus.DOWNLOADING
      );
      
      if (downloadingTasks.length > maxConcurrent) {
        // 暂停超出并发数的任务
        const tasksToPause = downloadingTasks.slice(maxConcurrent);
        for (const task of tasksToPause) {
          await download.pauseDownload(task.id);
          hilog.info(DOMAIN, TAG, 'Paused task to maintain concurrency limit: %{public}s', task.id);
        }
      }
      
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to update download concurrency: %{public}s', JSON.stringify(err));
    }
  }

  // 显示提示
  private showToast(message: string): void {
    // 在实际应用中，这里应该显示一个Toast提示
    // 暂时使用日志输出
    hilog.info(DOMAIN, TAG, 'Toast: %{public}s', message);
  }
}