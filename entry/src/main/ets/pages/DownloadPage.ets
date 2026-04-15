// 下载管理页面
// 对应安卓版的下载管理功能

import hilog from '@ohos.hilog';
import { BusinessError } from '@kit.BasicServicesKit';
import { DownloadTask, DownloadStatus, download, setDownloadContext } from '../core/music/MusicFeatureEntry';
import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { DesignTokens } from '../theme/DesignTokens';
import { NavBackButton } from '../components/common/NavBackButton';

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
  @State downloadPath: string = '/storage/emulated/0/Download/LxMusic';
  @State autoStartDownload: boolean = true;
  @State maxConcurrentDownloads: number = 3;
  /** 0 全部 1 进行中 2 已完成 3 失败 */
  @State filterTabIndex: number = 0;
  @State showDownloadSettings: boolean = false;

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
    if (this.showDownloadSettings) {
      this.showDownloadSettings = false;
    }
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
      if (this.showDownloadSettings) {
        Row() {
          Stack() {
            Circle({ width: 34, height: 34 })
              .fill(DesignTokens.mutedFill(this.theme))
            Image($r('app.media.ic_pd_back'))
              .width(16)
              .height(16)
              .fillColor(DesignTokens.labelPrimary(this.theme))
          }
          .margin({ right: 8 })
          .onClick(() => {
            this.showDownloadSettings = false;
          })
          Text('下载设置')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.labelPrimary(this.theme))
          Blank()
            .layoutWeight(1)
        }
        .width('100%')
        .height(60)
        .padding({ left: 12, right: 16, top: 8, bottom: 4 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(DesignTokens.chromeBar(this.theme))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      } else if (this.isSelectMode) {
        Row() {
          Text(`已选 ${this.selectedTasks.size} 项`)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .layoutWeight(1)
          Text('完成')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.accent())
            .onClick(() => {
              this.toggleSelectMode();
            })
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
      } else {
        Column() {
          Row() {
            Column() {
              Text('下载')
                .fontSize(34)
                .fontWeight(FontWeight.Bold)
                .fontColor(DesignTokens.labelPrimary(this.theme))
              Text('传输与缓存')
                .fontSize(14)
                .fontColor(DesignTokens.labelTertiary(this.theme))
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Stack() {
              Circle({ width: 34, height: 34 })
                .fill(DesignTokens.mutedFill(this.theme))
              Image($r('sys.symbol.gearshape'))
                .width(18)
                .height(18)
                .fillColor(DesignTokens.labelSecondary(this.theme))
            }
            .onClick(() => {
              this.isSelectMode = false;
              this.selectedTasks = new Set();
              this.showDownloadSettings = true;
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 10, bottom: 6 })
          .alignItems(VerticalAlign.Center)

          Text('传输队列')
            .fontSize(13)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .width('100%')
            .padding({ left: 16, right: 16, top: 2, bottom: 6 })

          Column() {
            this.buildSegmentStrip()
          }
          .width('100%')
          .backgroundColor(DesignTokens.card(this.theme))
          .borderRadius(DesignTokens.radiusCard())
          .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
          .margin({ left: 12, right: 12, bottom: 4 })

          Row() {
            Blank()
              .layoutWeight(1)
            Row({ space: 4 }) {
              Image($r('sys.symbol.checkmark_square'))
                .width(15)
                .height(15)
                .fillColor(DesignTokens.accent())
              Text('多选')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(DesignTokens.accent())
            }
            .padding({ top: 8, bottom: 8, left: 12, right: 12 })
            .backgroundColor(DesignTokens.accentSoft(this.theme))
            .borderRadius(16)
              .onClick(() => {
                this.toggleSelectMode();
              })
          }
          .width('100%')
          .padding({ left: 8, right: 12, top: 2, bottom: 8 })
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
      }
    }
    .width('100%')
    .backgroundColor(DesignTokens.chromeBar(this.theme))
  }

  @Builder
  buildSegmentStrip() {
    Row() {
      this.SegmentCell(0, '全部', this.downloadTasks.length)
      Column()
        .width(0.5)
        .height(36)
        .backgroundColor(DesignTokens.cardBorder(this.theme))
      this.SegmentCell(1, '进行中', this.countActiveTasks())
      Column()
        .width(0.5)
        .height(36)
        .backgroundColor(DesignTokens.cardBorder(this.theme))
      this.SegmentCell(2, '已完成', this.countCompletedTasks())
      Column()
        .width(0.5)
        .height(36)
        .backgroundColor(DesignTokens.cardBorder(this.theme))
      this.SegmentCell(3, '失败', this.countFailedTasks())
    }
    .width('100%')
    .padding({ left: 12, right: 12, bottom: 4 })
    .justifyContent(FlexAlign.SpaceEvenly)
  }

  @Builder
  SegmentCell(index: number, label: string, count: number) {
    Column() {
      Text(count.toString())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.filterTabIndex === index ? DesignTokens.accent() : DesignTokens.labelPrimary(this.theme))
      Text(label)
        .fontSize(11)
        .fontColor(DesignTokens.labelSecondary(this.theme))
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .padding({ top: 10, bottom: 10 })
    .backgroundColor(this.filterTabIndex === index ? DesignTokens.accentSoft(this.theme) : 'rgba(0,0,0,0)')
    .borderRadius(12)
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

  @Builder
  buildSettings() {
    Column() {
      Column() {
        Row() {
          Column() {
            Text('保存位置')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor(DesignTokens.labelPrimary(this.theme))
            Text(this.downloadPath)
              .fontSize(12)
              .fontColor(DesignTokens.labelTertiary(this.theme))
              .margin({ top: 6 })
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)

          Image($r('sys.symbol.folder'))
            .width(20)
            .height(20)
            .fillColor(DesignTokens.labelTertiary(this.theme))
        }
        .width('100%')
        .padding({ left: 16, right: 14, top: 14, bottom: 14 })
        .onClick(() => {
          this.selectDownloadPath();
        })

        Divider()
          .strokeWidth(0.5)
          .color(DesignTokens.cardBorder(this.theme))
          .margin({ left: 16, right: 16 })

        Row() {
          Text('自动开始下载')
            .fontSize(15)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.autoStartDownload })
            .onChange((isOn: boolean) => {
              this.autoStartDownload = isOn;
              this.saveDownloadSettings();
            })
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 14 })

        Divider()
          .strokeWidth(0.5)
          .color(DesignTokens.cardBorder(this.theme))
          .margin({ left: 16, right: 16 })

        Row() {
          Text('同时下载数量')
            .fontSize(15)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .layoutWeight(1)

          Text(this.maxConcurrentDownloads.toString())
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .margin({ right: 6 })

          Image($r('sys.symbol.chevron_right'))
            .width(14)
            .height(14)
            .fillColor(DesignTokens.labelTertiary(this.theme))
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 14 })
        .onClick(() => {
          this.selectMaxConcurrentDownloads();
        })
      }
      .width('100%')
      .borderRadius(DesignTokens.radiusCard())
      .backgroundColor(DesignTokens.card(this.theme))
      .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
      .clip(true)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 24 })
  }

  build() {
    Column() {
      this.buildTopChrome()
      this.buildToolbar()

      if (this.showDownloadSettings) {
        Scroll() {
          Column() {
            this.buildSettings()
          }
          .width('100%')
        }
        .layoutWeight(1)
        .backgroundColor(DesignTokens.pageBg(this.theme))
      } else {
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

  private showPathSelector(title: string, options: string[]): Promise<string | null> {
    const shortLabel = (opt: string): string => {
      return opt.length > 36 ? opt.substring(0, 33) + '…' : opt;
    };
    const c1 = DesignTokens.labelPrimary(this.theme);
    const c2 = DesignTokens.labelTertiary(this.theme);
    return new Promise((resolve: (v: string | null) => void) => {
      this.getUIContext().getPromptAction().showActionMenu({
        title: title,
        buttons: [
          { text: shortLabel(options[0]), color: c1 },
          { text: shortLabel(options[1]), color: c1 },
          { text: shortLabel(options[2]), color: c1 },
          { text: '取消', color: c2 },
        ],
      }, (err: BusinessError, data: PromptPickResult) => {
        if (err) {
          resolve(null);
          return;
        }
        const ix = data.index;
        if (ix >= 0 && ix < options.length) {
          resolve(options[ix]);
        } else {
          resolve(null);
        }
      });
    });
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

  private showCountSelector(title: string, options: number[]): Promise<number | null> {
    const c1 = DesignTokens.labelPrimary(this.theme);
    const c2 = DesignTokens.labelTertiary(this.theme);
    return new Promise((resolve: (v: number | null) => void) => {
      this.getUIContext().getPromptAction().showActionMenu({
        title: title,
        buttons: [
          { text: `${options[0]} 个`, color: c1 },
          { text: `${options[1]} 个`, color: c1 },
          { text: `${options[2]} 个`, color: c1 },
          { text: `${options[3]} 个`, color: c1 },
          { text: `${options[4]} 个`, color: c1 },
          { text: '取消', color: c2 },
        ],
      }, (err: BusinessError, data: PromptPickResult) => {
        if (err) {
          resolve(null);
          return;
        }
        const ix = data.index;
        if (ix >= 0 && ix < options.length) {
          resolve(options[ix]);
        } else {
          resolve(null);
        }
      });
    });
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