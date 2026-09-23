/**
 * 下载管理页的纯逻辑层（不含任何 UI）
 *
 * 从 DownloadPage 里抽出来的原因：
 * - 原来「统计数量」写了三个几乎一样的 for 循环，「状态文案/颜色」用 switch 写死十六进制色，
 *   「筛选」又是四个分支返回不同数组，页面里混着数据加工与 UI；
 * - 抽成纯函数后，筛选/计数/文案可以在不改 UI 的情况下被复用与核对，
 *   页面只负责「把任务映射成行模型」。
 *
 * 状态色统一走 DesignTokens 的语义色（success / warning / info / danger），
 * 不再在页面里写 `#FFA500` 这类魔法值。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import type { DownloadTask } from '../../core/music/MusicFeatureEntry';
import { DownloadStatus } from '../../core/music/MusicFeatureEntry';
import { formatBytes } from '../../utils/FormatTools';

/** 下载页筛选 Tab（与设置里的顺序一致） */
export enum DownloadFilter {
  ALL = 0,
  ACTIVE = 1,
  COMPLETED = 2,
  FAILED = 3,
}

/** 各状态数量（一次遍历得出，避免多次扫描） */
export interface DownloadCounts {
  all: number;
  active: number;
  completed: number;
  failed: number;
}

/** 任务行右侧主操作类型 */
export type DownloadActionKind = 'start' | 'pause' | 'retry' | 'play' | 'none';

/** 任务行模型：UI 只认这个结构，不再直接读 DownloadTask */
export interface DownloadRowModel {
  id: string;
  title: string;
  subtitle: string;
  metaText: string;
  statusText: string;
  statusColor: string;
  progress: number;
  errorText: string;
  selected: boolean;
  selectMode: boolean;
  actionKind: DownloadActionKind;
  /** 是否显示删除按钮（完成/失败/暂停都可以删） */
  canDelete: boolean;
  /** 是否显示进度条 */
  showProgress: boolean;
}

/** 进行中（等待 / 下载中 / 已暂停）——筛选与「是否还在跑」共用同一判定 */
export function isActiveStatus(status: DownloadStatus): boolean {
  return status === DownloadStatus.PENDING ||
    status === DownloadStatus.DOWNLOADING ||
    status === DownloadStatus.PAUSED;
}

/** 一次遍历统计各状态数量 */
export function countDownloadTasks(tasks: DownloadTask[]): DownloadCounts {
  const counts: DownloadCounts = { all: tasks.length, active: 0, completed: 0, failed: 0 };
  for (let i = 0; i < tasks.length; i++) {
    const status = tasks[i].status;
    if (isActiveStatus(status)) {
      counts.active++;
    } else if (status === DownloadStatus.COMPLETED) {
      counts.completed++;
    } else if (status === DownloadStatus.FAILED) {
      counts.failed++;
    }
  }
  return counts;
}

/** 按筛选 Tab 过滤任务 */
export function filterDownloadTasks(tasks: DownloadTask[], filter: DownloadFilter): DownloadTask[] {
  if (filter === DownloadFilter.ALL) {
    return tasks;
  }
  if (filter === DownloadFilter.ACTIVE) {
    return tasks.filter((task: DownloadTask): boolean => isActiveStatus(task.status));
  }
  if (filter === DownloadFilter.COMPLETED) {
    return tasks.filter((task: DownloadTask): boolean => task.status === DownloadStatus.COMPLETED);
  }
  return tasks.filter((task: DownloadTask): boolean => task.status === DownloadStatus.FAILED);
}

/** 状态文案：暂停与下载中是两种状态，文案必须分开（此前暂停也显示「下载中」） */
export function downloadStatusLabel(status: DownloadStatus): string {
  switch (status) {
    case DownloadStatus.PENDING:
      return t('download_pending');
    case DownloadStatus.DOWNLOADING:
      return t('download_active');
    case DownloadStatus.PAUSED:
      return t('download_paused');
    case DownloadStatus.COMPLETED:
      return t('download_completed');
    case DownloadStatus.FAILED:
      return t('download_failed');
    default:
      return t('no_data');
  }
}

/** 状态语义色（统一走 token） */
export function downloadStatusColor(status: DownloadStatus): string {
  switch (status) {
    case DownloadStatus.PENDING:
      return DesignTokens.warning();
    case DownloadStatus.DOWNLOADING:
      return DesignTokens.success();
    case DownloadStatus.PAUSED:
      return DesignTokens.warning();
    case DownloadStatus.COMPLETED:
      return DesignTokens.info();
    case DownloadStatus.FAILED:
      return DesignTokens.danger();
    default:
      return DesignTokens.labelTertiary('light');
  }
}

/** 右侧主操作：等待/暂停 → 开始，下载中 → 暂停，失败 → 重试，完成 → 播放 */
export function downloadActionKind(status: DownloadStatus): DownloadActionKind {
  switch (status) {
    case DownloadStatus.PENDING:
    case DownloadStatus.PAUSED:
      return 'start';
    case DownloadStatus.DOWNLOADING:
      return 'pause';
    case DownloadStatus.FAILED:
      return 'retry';
    case DownloadStatus.COMPLETED:
      return 'play';
    default:
      return 'none';
  }
}

/**
 * 任务集合指纹：定时轮询用它判断"是否需要刷新 UI"。
 * 之前每秒无脑赋值新数组，进度没变也会让整个列表重建一次。
 */
export function downloadTasksSignature(tasks: DownloadTask[]): string {
  let signature = '';
  for (let i = 0; i < tasks.length; i++) {
    const task = tasks[i];
    signature += `${task.id}:${task.status}:${Math.floor(task.progress)}:${task.downloadedSize}|`;
  }
  return signature;
}

/** 任务 → 行模型（页面唯一的映射入口） */
export function toDownloadRowModel(
  task: DownloadTask, selected: boolean, selectMode: boolean): DownloadRowModel {
  const info = task.musicInfo;
  const album = info.albumName || info.album || t('unknown_album');
  const subtitle = `${info.singer || t('unknown_artist')} · ${album}`;
  const percentages = Math.max(0, Math.min(100, Math.round(task.progress)));
  const showProgress = task.status === DownloadStatus.DOWNLOADING || task.status === DownloadStatus.PAUSED;
  return {
    id: task.id,
    title: info.name,
    subtitle: subtitle,
    metaText: `${task.quality} · ${formatBytes(task.downloadedSize)}/${formatBytes(task.totalSize)}`,
    statusText: downloadStatusLabel(task.status),
    statusColor: downloadStatusColor(task.status),
    progress: percentages,
    errorText: task.status === DownloadStatus.FAILED ? (task.error ?? '') : '',
    selected: selected,
    selectMode: selectMode,
    actionKind: downloadActionKind(task.status),
    canDelete: task.status !== DownloadStatus.DOWNLOADING,
    showProgress: showProgress,
  };
}
