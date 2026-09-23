/**
 * 下载模块门面（外部唯一入口）
 *
 * 991 行 → 门面 + 四个各司其职的模块（core/music/download/）：
 * - `DownloadTypes`   类型与状态枚举（页面、备份服务、队列共用）
 * - `DownloadContext` UIAbilityContext 持有者（文件层与队列层都要用）
 * - `DownloadFiles`   路径规则、文件搬运、系统下载能力、歌词/封面落盘
 * - `DownloadStorage` 下载历史持久化与备份导入导出
 * - `DownloadQueue`   任务状态机与并发控制（唯一持有任务表的地方）
 *
 * 这里只做转发：所有既有 import 路径（`MusicFeatureEntry`、`BackupService`、
 * 下载页等）保持不变，外部无需感知拆分。
 */
import { setDownloadContext } from './download/DownloadContext';
import {
  repairPlayablePath,
  getDefaultDownloadPath,
  getLyricSavePath,
  getPicSavePath,
  downloadLyric,
  downloadPic,
} from './download/DownloadFiles';
import {
  batchDownload,
  cancelDownload,
  clearAllTasks,
  clearCompletedTasks,
  createDownloadTask,
  exportDownloadTasksForBackup,
  getAllDownloadTasks,
  getDownloadTask,
  getDownloadingTasks,
  initDownloadService,
  onDownloadTasksChanged,
  pauseDownload,
  restoreDownloadTasksFromBackup,
  resumeDownload,
  setMaxConcurrentDownloads,
  startDownload,
  startPendingDownloads,
  persistDownloadTasks,
} from './download/DownloadQueue';
import {
  DownloadStatus,
  type BatchDownloadParams,
  type DownloadLyricParams,
  type DownloadPicParams,
  type DownloadTask,
  type StartDownloadParams,
} from './download/DownloadTypes';
import type { MusicInfo, Quality } from '../../types/MusicTypes';

export {
  initDownloadService,
  createDownloadTask,
  startDownload,
  batchDownload,
  startPendingDownloads,
  setMaxConcurrentDownloads,
  setDownloadContext,
  pauseDownload,
  resumeDownload,
  cancelDownload,
  getDownloadTask,
  getAllDownloadTasks,
  getDownloadingTasks,
  exportDownloadTasksForBackup,
  restoreDownloadTasksFromBackup,
  clearCompletedTasks,
  clearAllTasks,
  onDownloadTasksChanged,
  downloadLyric,
  downloadPic,
  getDefaultDownloadPath,
  getLyricSavePath,
  getPicSavePath,
  DownloadStatus,
};

export type {
  DownloadTask,
  StartDownloadParams,
  DownloadLyricParams,
  DownloadPicParams,
  BatchDownloadParams,
};

/** 下载模块接口（给 `download` 命名对象用） */
interface DownloadModule {
  initDownloadService: () => Promise<void>;
  createDownloadTask: (musicInfo: MusicInfo, quality: Quality) => Promise<DownloadTask>;
  startDownload: (params: StartDownloadParams) => Promise<string>;
  pauseDownload: (taskId: string) => Promise<boolean>;
  resumeDownload: (taskId: string) => Promise<boolean>;
  cancelDownload: (taskId: string) => Promise<boolean>;
  getDownloadTask: (taskId: string) => DownloadTask | null;
  getAllDownloadTasks: () => DownloadTask[];
  getDownloadingTasks: () => DownloadTask[];
  downloadLyric: (params: DownloadLyricParams) => Promise<string | null>;
  downloadPic: (params: DownloadPicParams) => Promise<string | null>;
  batchDownload: (params: BatchDownloadParams) => Promise<string[]>;
  clearCompletedTasks: () => Promise<void>;
  clearAllTasks: () => Promise<void>;
  /** 订阅任务变化：状态/进度一变立即通知（下载页即时刷新） */
  onDownloadTasksChanged: (listener: () => void) => () => void;
  /** 把当前任务表写回历史（播放路径修复后调用） */
  persistDownloadTasks: () => Promise<void>;
  getDefaultDownloadPath: (musicInfo: MusicInfo) => string;
  getLyricSavePath: (musicInfo: MusicInfo) => string;
  getPicSavePath: (musicInfo: MusicInfo) => string;
  setMaxConcurrentDownloads: (max: number) => void;
  startPendingDownloads: () => void;
}

/** 命名对象：供「高级用法」一次性拿到整组能力 */
export const download: DownloadModule = {
  initDownloadService,
  createDownloadTask,
  startDownload,
  pauseDownload,
  resumeDownload,
  cancelDownload,
  getDownloadTask,
  getAllDownloadTasks,
  getDownloadingTasks,
  downloadLyric,
  downloadPic,
  batchDownload,
  clearCompletedTasks,
  clearAllTasks,
  onDownloadTasksChanged,
  persistDownloadTasks,
  getDefaultDownloadPath,
  getLyricSavePath,
  getPicSavePath,
  setMaxConcurrentDownloads,
  startPendingDownloads,
};
