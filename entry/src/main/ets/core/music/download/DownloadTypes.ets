/**
 * 下载域的公共类型
 *
 * 从 RunMusicDownloads 拆出：这些类型被页面（下载页行模型）、服务层（备份/恢复）
 * 和下载队列共同引用，单独成文件后三个模块不必互相 import。
 */
import type { common } from '@kit.AbilityKit';
import type { MusicInfo, Quality } from '../../../types/MusicTypes';

/** 下载状态 */
export enum DownloadStatus {
  PENDING = 'pending',
  DOWNLOADING = 'downloading',
  PAUSED = 'paused',
  CANCELLED = 'cancelled',
  COMPLETED = 'completed',
  FAILED = 'failed',
}

/** 下载任务 */
export interface DownloadTask {
  id: string;
  musicInfo: MusicInfo;
  quality: Quality;
  status: DownloadStatus;
  progress: number;
  downloadedSize: number;
  totalSize: number;
  filePath?: string;
  error?: string;
  /** 系统下载任务 ID */
  downloadId?: number;
  /** 下载操作所需上下文 */
  context?: common.UIAbilityContext;
}

/** 单个任务进度回调 */
export type DownloadProgressCallback = (task: DownloadTask) => void;

/** 批量下载进度回调 */
export type BatchProgressCallback = (completed: number, total: number, task: DownloadTask) => void;

/** 开始下载参数 */
export interface StartDownloadParams {
  musicInfo: MusicInfo;
  quality?: Quality;
  savePath?: string;
  onProgress?: DownloadProgressCallback;
}

/** 下载歌词参数 */
export interface DownloadLyricParams {
  musicInfo: MusicInfo;
  savePath?: string;
}

/** 下载封面参数 */
export interface DownloadPicParams {
  musicInfo: MusicInfo;
  savePath?: string;
}

/** 批量下载参数 */
export interface BatchDownloadParams {
  musicList: MusicInfo[];
  quality?: Quality;
  onProgress?: BatchProgressCallback;
}

/** 传输层回调：只报告「字节进度 / 完成」，任务状态由队列层决定 */
export interface TransferCallbacks {
  onBytes?: (size: number, total: number) => void;
}
