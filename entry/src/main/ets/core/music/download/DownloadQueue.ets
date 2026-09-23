/**
 * 下载队列层：任务状态机 + 并发控制
 *
 * 唯一持有任务表与等待队列的地方（文件层与持久化层都不持有状态），
 * 所以「同时下载几首、谁能开始、暂停算哪种状态」只有这一处定义。
 *
 * 并发规则：
 * - 并发数由设置决定（1-3），超过就进等待队列；
 * - 「自动开始下载」关闭时，新任务一律进等待队列，等用户手动开始（`startPendingDownloads`）；
 * - 一个任务结束后自动拉下一个（`processQueue`）。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { appLog as hilog } from '../../log/AppLogger';
import { settingsService } from '../../../service/SettingsService';
import { requireDownloadContext } from './DownloadContext';
import {
  ensureParentDir,
  dropActiveRequestTask,
  getActiveRequestTask,
  getDefaultDownloadPath,
  getSandboxDownloadPath,
  resolveMusicUrl,
  saveSandboxFileToPublicDownload,
  transferToPath,
  downloadLyric,
  downloadPic,
} from './DownloadFiles';
import {
  exportTasksForBackup,
  loadDownloadHistory,
  saveDownloadHistory,
} from './DownloadStorage';
import {
  DownloadStatus,
  type BatchDownloadParams,
  type DownloadLyricParams,
  type DownloadPicParams,
  type DownloadProgressCallback,
  type DownloadTask,
  type StartDownloadParams,
} from './DownloadTypes';
import type { MusicInfo, Quality } from '../../../types/MusicTypes';

const TAG = 'DOWNLOAD';
const DOMAIN = 0x0003;

/** 任务表：id → 任务（内存唯一来源） */
const downloadTasks: Map<string, DownloadTask> = new Map();
/** 等待队列（未开始的任务 id，先进先出） */
const pendingQueue: string[] = [];
/** 最大并发下载数（默认 1，设置里可改） */
let maxConcurrentDownloads: number = 1;

function getDownloadingCount(): number {
  let count = 0;
  downloadTasks.forEach((task: DownloadTask): void => {
    if (task.status === DownloadStatus.DOWNLOADING) {
      count++;
    }
  });
  return count;
}

/** 「自动开始下载」设置：关闭时新任务只入队等待 */
function isAutoStartDownloadEnabled(): boolean {
  return settingsService.get().autoStartDownload;
}

/** 生成任务 ID（同一首歌重复下载会覆盖同一条记录） */
function generateTaskId(musicInfo: MusicInfo): string {
  const key = (musicInfo.songmid && musicInfo.songmid.length > 0) ? musicInfo.songmid :
    ((musicInfo.id && musicInfo.id.length > 0) ? musicInfo.id : 'unknown');
  return `dl_${musicInfo.source}_${key}_${Date.now()}`;
}

/** 处理等待队列：有空位就拉起下一个任务 */
export async function processQueue(force: boolean = false): Promise<void> {
  if (!force && !isAutoStartDownloadEnabled()) {
    return;
  }
  while (getDownloadingCount() < maxConcurrentDownloads && pendingQueue.length > 0) {
    const taskId = pendingQueue.shift();
    if (!taskId) {
      continue;
    }
    const task = downloadTasks.get(taskId);
    if (task && task.status === DownloadStatus.PENDING) {
      try {
        const downloadId = await startActualDownload(task);
        task.downloadId = downloadId;
      } catch (err) {
        task.status = DownloadStatus.FAILED;
        task.error = err instanceof Error ? err.message : String(err);
      }
    }
  }
}

/** 手动开始所有等待中的下载（下载页「全部继续」） */
export function startPendingDownloads(): void {
  void processQueue(true);
}

export function setMaxConcurrentDownloads(max: number): void {
  maxConcurrentDownloads = Math.min(Math.max(1, max), 3);
  hilog.info(DOMAIN, TAG, 'Max concurrent downloads set to: %{public}d', maxConcurrentDownloads);
}

export async function initDownloadService(): Promise<void> {
  const history = await loadDownloadHistory();
  for (let i = 0; i < history.length; i++) {
    downloadTasks.set(history[i].id, history[i]);
  }
}

/**
 * 实际下载一个任务：取链 → 落沙箱 → 转存到用户目录 → 标记完成。
 * 失败时把任务标成 FAILED 并记错误信息（下载页据此显示与重试）。
 */
async function startActualDownload(
  task: DownloadTask, onProgress?: DownloadProgressCallback): Promise<number> {
  let sandboxPath = '';
  try {
    const musicUrl = await resolveMusicUrl(task.musicInfo);
    sandboxPath = getSandboxDownloadPath(task.musicInfo);
    ensureParentDir(sandboxPath);

    task.status = DownloadStatus.DOWNLOADING;
    task.progress = 0;
    task.filePath = sandboxPath;
    if (onProgress) {
      onProgress(task);
    }

    await transferToPath(task.id, musicUrl, sandboxPath, {
      onBytes: (size: number, total: number): void => {
        task.downloadedSize = size;
        task.totalSize = total;
        if (total > 0) {
          task.progress = Math.floor((size / total) * 100);
        }
        if (onProgress) {
          onProgress(task);
        }
      },
    });

    // 转存到公共目录（写不进去时按设置回退，见 DownloadFiles）
    task.progress = 95;
    if (onProgress) {
      onProgress(task);
    }
    const fileName = sandboxPath.substring(sandboxPath.lastIndexOf('/') + 1);
    const savedPath = await saveSandboxFileToPublicDownload(sandboxPath, fileName);
    hilog.info(DOMAIN, TAG, '下载落盘位置: %{public}s', savedPath);

    task.status = DownloadStatus.COMPLETED;
    task.progress = 100;
    // 记真实保存位置而不是设置里的目录：用户在选择器里换过目录也能播
    task.filePath = savedPath;
    if (onProgress) {
      onProgress(task);
    }
    hilog.info(DOMAIN, TAG, '下载完成: %{public}s', task.musicInfo.name);
    void processQueue();
    void saveDownloadHistory(Array.from(downloadTasks.values()));
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : JSON.stringify(err);
    hilog.error(DOMAIN, TAG, '下载失败: %{public}s - %{public}s', task.musicInfo.name, errMsg);
    task.status = DownloadStatus.FAILED;
    task.error = errMsg;
    if (sandboxPath.length > 0) {
      task.filePath = sandboxPath;
    }
    void saveDownloadHistory(Array.from(downloadTasks.values()));
    throw new Error(errMsg);
  }

  const downloadId = Date.now();
  task.downloadId = downloadId;
  hilog.info(DOMAIN, TAG, '开始下载: %{public}s, ID: %{public}d', task.musicInfo.name, downloadId);
  return downloadId;
}

/** 新建任务（只登记，不开始） */
export async function createDownloadTask(musicInfo: MusicInfo, quality: Quality): Promise<DownloadTask> {
  const task: DownloadTask = {
    id: generateTaskId(musicInfo),
    musicInfo: musicInfo,
    quality: quality,
    status: DownloadStatus.PENDING,
    progress: 0,
    downloadedSize: 0,
    totalSize: 0,
  };
  downloadTasks.set(task.id, task);
  return task;
}

/** 开始下载：并发满或关闭自动开始时先进等待队列 */
export async function startDownload(params: StartDownloadParams): Promise<string> {
  const musicInfo: MusicInfo = params.musicInfo;
  // 未显式指定音质时跟随「高品质音乐」设置
  const quality: Quality = params.quality ?? settingsService.get().playQuality;
  const taskId: string = generateTaskId(musicInfo);
  const originalOnProgress: DownloadProgressCallback | undefined = params.onProgress;

  const task: DownloadTask = {
    id: taskId,
    musicInfo: musicInfo,
    quality: quality,
    status: DownloadStatus.PENDING,
    progress: 0,
    downloadedSize: 0,
    totalSize: 0,
    filePath: params.savePath ?? getDefaultDownloadPath(musicInfo),
    context: requireDownloadContext(),
  };
  downloadTasks.set(taskId, task);

  const currentDownloading = getDownloadingCount();
  if (currentDownloading >= maxConcurrentDownloads || !isAutoStartDownloadEnabled()) {
    pendingQueue.push(taskId);
    hilog.info(DOMAIN, TAG, '下载任务进入等待队列: %{public}s, 队列长度: %{public}d',
      musicInfo.name, pendingQueue.length);
    if (originalOnProgress) {
      originalOnProgress(task);
    }
    void processQueue();
    return taskId;
  }

  try {
    task.status = DownloadStatus.DOWNLOADING;
    const downloadId = await startActualDownload(task, originalOnProgress);
    task.downloadId = downloadId;
    return taskId;
  } catch (err) {
    const detail =
      err instanceof Error ? err.message : (typeof err === 'string' ? err : JSON.stringify(err));
    const downloadErr: Error = new Error(`Download failed: ${detail}`);
    hilog.error(DOMAIN, TAG, 'Download failed: %{public}s', downloadErr.message);
    task.status = DownloadStatus.FAILED;
    task.error = downloadErr.message;
    if (originalOnProgress) {
      originalOnProgress(task);
    }
    throw downloadErr;
  }
}

/** 批量下载（逐首提交，单首失败不影响后续） */
export async function batchDownload(params: BatchDownloadParams): Promise<string[]> {
  const musicList: MusicInfo[] = params.musicList;
  const quality: Quality = params.quality ?? '128k';
  const onProgress = params.onProgress;
  const taskIds: string[] = [];
  const total = musicList.length;

  for (let i = 0; i < musicList.length; i++) {
    const musicInfo = musicList[i];
    try {
      const taskId = await startDownload({
        musicInfo: musicInfo,
        quality: quality,
        onProgress: (task: DownloadTask): void => {
          if (onProgress) {
            onProgress(i + 1, total, task);
          }
        },
      });
      taskIds.push(taskId);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Batch download failed for: %{public}s', musicInfo.name);
    }
  }
  return taskIds;
}

/** 暂停：真正下载中的用系统句柄暂停，等待中的移出队列 */
export async function pauseDownload(taskId: string): Promise<boolean> {
  const task = downloadTasks.get(taskId);
  if (!task) {
    hilog.warn(DOMAIN, TAG, '暂停失败: 任务不存在 - %{public}s', taskId);
    return false;
  }
  try {
    const requestTask = getActiveRequestTask(taskId);
    if (requestTask) {
      await requestTask.pause();
    } else {
      const queueIndex = pendingQueue.indexOf(taskId);
      if (queueIndex > -1) {
        pendingQueue.splice(queueIndex, 1);
      }
    }
    task.status = DownloadStatus.PAUSED;
    hilog.info(DOMAIN, TAG, '下载暂停: %{public}s', task.musicInfo.name);
    return true;
  } catch (error) {
    const errMsg: string = error instanceof Error ? error.message : 'Unknown error';
    hilog.error(DOMAIN, TAG, '暂停下载失败: %{public}s - %{public}s', task.musicInfo.name, errMsg);
    return false;
  }
}

/** 继续：有句柄走系统恢复，没有句柄（失败/等待过）重新入队 */
export async function resumeDownload(taskId: string): Promise<boolean> {
  const task = downloadTasks.get(taskId);
  if (!task) {
    hilog.warn(DOMAIN, TAG, '恢复失败: 任务不存在 - %{public}s', taskId);
    return false;
  }
  try {
    const requestTask = getActiveRequestTask(taskId);
    if (requestTask) {
      await requestTask.resume();
      task.status = DownloadStatus.DOWNLOADING;
      hilog.info(DOMAIN, TAG, '下载恢复: %{public}s', task.musicInfo.name);
      return true;
    }
    if (task.status === DownloadStatus.COMPLETED) {
      hilog.warn(DOMAIN, TAG, '任务已完成，无需恢复: %{public}s', taskId);
      return false;
    }
    task.status = DownloadStatus.PENDING;
    task.error = undefined;
    if (pendingQueue.indexOf(taskId) < 0) {
      pendingQueue.push(taskId);
    }
    await processQueue(true);
    hilog.info(DOMAIN, TAG, '下载重新入队: %{public}s', task.musicInfo.name);
    return true;
  } catch (error) {
    const errMsg: string = error instanceof Error ? error.message : 'Unknown error';
    hilog.error(DOMAIN, TAG, '恢复下载失败: %{public}s - %{public}s', task.musicInfo.name, errMsg);
    return false;
  }
}

/** 取消/删除任务：连带删掉下到一半的文件 */
export async function cancelDownload(taskId: string): Promise<boolean> {
  const task = downloadTasks.get(taskId);
  if (!task) {
    hilog.warn(DOMAIN, TAG, '取消失败: 任务不存在 - %{public}s', taskId);
    return false;
  }
  try {
    const originalStatus = task.status;
    const requestTask = getActiveRequestTask(taskId);
    if (requestTask) {
      try {
        await requestTask.remove();
      } catch (removeErr) {
        hilog.warn(DOMAIN, TAG, '取消系统下载任务失败: %{public}s',
          removeErr instanceof Error ? removeErr.message : JSON.stringify(removeErr));
      }
      dropActiveRequestTask(taskId);
    }
    const queueIndex = pendingQueue.indexOf(taskId);
    if (queueIndex > -1) {
      pendingQueue.splice(queueIndex, 1);
    }
    task.status = DownloadStatus.CANCELLED;

    if (task.filePath &&
      (originalStatus === DownloadStatus.DOWNLOADING || originalStatus === DownloadStatus.PENDING)) {
      try {
        await fs.access(task.filePath);
        await fs.unlink(task.filePath);
        hilog.info(DOMAIN, TAG, '删除部分下载文件: %{public}s', task.filePath);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, '删除部分下载文件失败（文件可能不存在）: %{public}s', (e as Error)?.message);
      }
    }
    downloadTasks.delete(taskId);
    hilog.info(DOMAIN, TAG, '下载取消: %{public}s', task.musicInfo.name);
    return true;
  } catch (error) {
    const errMsg: string = error instanceof Error ? error.message : 'Unknown error';
    hilog.error(DOMAIN, TAG, '取消下载失败: %{public}s - %{public}s', task.musicInfo.name, errMsg);
    return false;
  }
}

export function getDownloadTask(taskId: string): DownloadTask | null {
  return downloadTasks.get(taskId) ?? null;
}

export function getAllDownloadTasks(): DownloadTask[] {
  return Array.from(downloadTasks.values());
}

export function getDownloadingTasks(): DownloadTask[] {
  return Array.from(downloadTasks.values()).filter((task: DownloadTask): boolean =>
    task.status === DownloadStatus.DOWNLOADING || task.status === DownloadStatus.PENDING);
}

export function exportDownloadTasksForBackup(): DownloadTask[] {
  return exportTasksForBackup(Array.from(downloadTasks.values()));
}

/** 恢复备份中的下载任务（恢复为已完成记录，文件路径沿用备份值） */
export async function restoreDownloadTasksFromBackup(tasks: DownloadTask[]): Promise<number> {
  let restored = 0;
  for (let i = 0; i < tasks.length; i++) {
    const task = tasks[i];
    if (!task || !task.id || !task.musicInfo || downloadTasks.has(task.id)) {
      continue;
    }
    downloadTasks.set(task.id, task);
    restored++;
  }
  if (restored > 0) {
    await saveDownloadHistory(Array.from(downloadTasks.values()));
    hilog.info(DOMAIN, TAG, '下载任务已从备份恢复: %{public}d 条', restored);
  }
  return restored;
}

export function clearCompletedTasks(): void {
  const entries = Array.from(downloadTasks.entries());
  for (let i = 0; i < entries.length; i++) {
    if (entries[i][1].status === DownloadStatus.COMPLETED) {
      downloadTasks.delete(entries[i][0]);
    }
  }
}

export function clearAllTasks(): void {
  downloadTasks.clear();
  pendingQueue.length = 0;
}

// 歌词/封面下载不涉及队列，直接透出文件层能力，保持调用方 import 路径不变
export { downloadLyric, downloadPic };
export type { DownloadLyricParams, DownloadPicParams };
