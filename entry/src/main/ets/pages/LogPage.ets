// 运行日志页 - 对应安卓版 设置 → 其他 → 日志
// 展示应用运行日志（WARN/ERROR 默认记录，可选详细日志），支持筛选、复制、导出、清空

import hilog from '@ohos.hilog';
import { showAppToast, TOAST_DURATION_DEFAULT } from '../utils/Toast';
import { DesignTokens } from '../theme/DesignTokens';
import { logService } from '../service/LogService';
import { EmptyView } from '../components/common/EmptyView';
import { NavBackButton } from '../components/common/NavBackButton';
import { SegmentedBar } from '../components/ui/SegmentedBar';
import { t, tf } from '../service/LocalizationService';
import type { LogRecord } from '../core/log/LogStore';

const DOMAIN = 0x0001;
const TAG = 'LogPage';

interface LogFilterOption {
  id: string;
  label: string;
}

@Component
export struct LogPage {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('langVersion') langVersion: number = 0;
  @State filter: string = 'ALL';
  @State records: LogRecord[] = [];
  @State totalCount: number = 0;
  @State isLoading: boolean = true;

  aboutToAppear() {
    this.refresh();
  }

  private refresh(): void {
    try {
      this.records = logService.getRecords(this.filter);
      this.totalCount = logService.count();
    } catch (err) {
      this.records = [];
      this.totalCount = 0;
    }
    this.isLoading = false;
  }

  private toast(message: string): void {
    showAppToast(this.getUIContext(), message, TOAST_DURATION_DEFAULT);
  }

  private levelColor(level: string): string {
    if (level === 'ERROR' || level === 'FATAL') {
      return DesignTokens.danger();
    }
    if (level === 'WARN') {
      return '#FF9500';
    }
    return DesignTokens.labelTertiary(this.theme);
  }

  private levelShort(level: string): string {
    if (level === 'ERROR') {
      return 'E';
    }
    if (level === 'FATAL') {
      return 'F';
    }
    if (level === 'WARN') {
      return 'W';
    }
    if (level === 'INFO') {
      return 'I';
    }
    return 'D';
  }

  private formatTime(ms: number): string {
    const date = new Date(ms);
    const pad = (value: number): string => (value < 10 ? `0${value}` : `${value}`);
    return `${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
      `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
  }

  private async copyLogs(): Promise<void> {
    const text = logService.getLogText(this.filter);
    if (text.length === 0) {
      this.toast(t('logs_empty'));
      return;
    }
    if (logService.copyText(text)) {
      this.toast(t('logs_copied'));
    } else {
      this.toast(t('logs_copy_failed'));
    }
  }

  private async exportLogs(): Promise<void> {
    const path = logService.exportToFile();
    if (path.length > 0) {
      this.toast(tf('logs_exported', [path]));
    } else {
      this.toast(t('logs_export_failed'));
    }
  }

  private async clearLogs(): Promise<void> {
    try {
      const confirmed = await new Promise<boolean>((resolve: (value: boolean) => void) => {
        this.getUIContext().getPromptAction().showDialog({
          title: t('logs_clear'),
          message: t('confirm_clear_logs'),
          buttons: [
            { text: t('cancel'), color: DesignTokens.labelSecondary(this.theme) },
            { text: t('confirm'), color: DesignTokens.danger() },
          ],
        }, (err: object, data: PromptActionResultLike) => {
          resolve(!err && data.index === 1);
        });
      });
      if (!confirmed) {
        return;
      }
      logService.clear();
      this.refresh();
      this.toast(t('logs_cleared'));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clear logs failed: %{public}s', JSON.stringify(err));
      this.toast(t('toast_clear_failed'));
    }
  }

  private filterOptions(): LogFilterOption[] {
    return [
      { id: 'ALL', label: t('logs_filter_all') },
      { id: 'WARN', label: t('logs_filter_warn') },
      { id: 'ERROR', label: t('logs_filter_error') },
    ];
  }

  @Builder
  private Header() {
    Row() {
      NavBackButton()

      Text(t('logs_title'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .margin({ left: 12 })
        .layoutWeight(1)

      if (this.totalCount > 0) {
        Row({ space: 4 }) {
          Text(t('logs_copy'))
            .fontSize(14)
            .fontColor(DesignTokens.accent())
            .padding({ left: 8, right: 8, top: 6, bottom: 6 })
            .onClick(() => {
              void this.copyLogs();
            })
          Text(t('logs_clear'))
            .fontSize(14)
            .fontColor(DesignTokens.danger())
            .padding({ left: 8, right: 4, top: 6, bottom: 6 })
            .onClick(() => {
              void this.clearLogs();
            })
        }
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .backgroundColor(DesignTokens.chromeBar(this.theme))
  }

  @Builder
  private FilterBar() {
    Row() {
      SegmentedBar({
        options: this.filterOptions(),
        activeId: this.filter,
        fillWidth: false,
        onSelect: (id: string): void => {
          this.filter = id;
          this.refresh();
        },
      })

      Blank()

      Text(tf('logs_count', [this.records.length.toString()]))
        .fontSize(12)
        .fontColor(DesignTokens.labelTertiary(this.theme))

      Text(t('logs_export'))
        .fontSize(13)
        .fontColor(DesignTokens.accent())
        .margin({ left: 12 })
        .onClick(() => {
          void this.exportLogs();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private LogRow(record: LogRecord) {
    Column() {
      Row() {
        Text(this.levelShort(record.level))
          .fontSize(11)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .width(18)
          .height(18)
          .textAlign(TextAlign.Center)
          .borderRadius(4)
          .backgroundColor(this.levelColor(record.level))

        Text(record.tag)
          .fontSize(12)
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .margin({ left: 8 })
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.formatTime(record.time))
          .fontSize(11)
          .fontColor(DesignTokens.labelTertiary(this.theme))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(record.message)
        .fontSize(12)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .width('100%')
        .margin({ top: 6 })
        .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      this.Header()
      this.FilterBar()

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(DesignTokens.accent())
          Text(t('loading'))
            .fontSize(14)
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .margin({ top: 12 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.records.length === 0) {
        EmptyView({ iconRes: $r('sys.symbol.doc_text'), message: t('logs_empty') })
          .layoutWeight(1)
          .width('100%')
      } else {
        List({ space: 8 }) {
          ForEach(this.records.slice().reverse(), (record: LogRecord, index: number) => {
            ListItem() {
              this.LogRow(record)
            }
            .padding({ left: 16, right: 16 })
          }, (record: LogRecord, index: number) => `${record.time}_${record.tag}_${index}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ top: 4, bottom: 20 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }
}

interface PromptActionResultLike {
  index: number;
}
