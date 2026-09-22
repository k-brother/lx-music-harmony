// 下载任务与系统下载 API（原 download.ets）

import type { MusicInfo, Quality } from '../../types/MusicTypes';
import { getMusicUrl as getOnlineMusicUrl } from './MusicFeatureEntry';
import { getPicUrl as getOnlinePicUrl, getLyricInfo as getOnlineLyricInfo } from './ResolvePlayback';
import hilog from '@ohos.hilog';
import fs from '@ohos.file.fs';
import { httpRequest } from '../network/http';
import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import preferences from '@ohos.data.preferences';
import filePicker from '@ohos.file.picker';
import { settingsService } from '../../service/SettingsService';

const TAG = 'DOWNLOAD';
const DOMAIN = 0x0003;
const DEFAULT_DOWNLOAD_DIR = '/storage/Users/currentUser/Download';

// 下载状态
export enum DownloadStatus {
  PENDING = 'pending',
  DOWNLOADING = 'downloading',
  PAUSED = 'paused',
  CANCELLED = 'cancelled',
  COMPLETED = 'completed',
  FAILED = 'failed',
}

// 下载任务信息
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
  downloadId?: number; // 鸿蒙下载任务的ID
  context?: common.UIAbilityContext; // 上下文用于下载操作
}

// 下载进度回调
export type DownloadProgressCallback = (task: DownloadTask) => void;

// 批量下载进度回调
export type BatchProgressCallback = (completed: number, total: number, task: DownloadTask) => void;



// 下载任务Map
const downloadTasks: Map<string, DownloadTask> = new Map();

// 获取UIAbility上下文（需要在组件中设置）
let globalContext: common.UIAbilityContext | null = null;

// 下载队列（等待中的任务）
const pendingQueue: string[] = [];

// 正在进行的系统下载任务句柄（用于暂停/恢复）
const activeRequestTasks: Map<string, request.DownloadTask> = new Map();

// 最大并发下载数（默认1）
let maxConcurrentDownloads: number = 1;

// 获取当前下载中的任务数
function getDownloadingCount(): number {
  let count = 0;
  downloadTasks.forEach(task => {
    if (task.status === DownloadStatus.DOWNLOADING) {
      count++;
    }
  });
  return count;
}

/** "自动开始下载"设置：关闭时新任务只入队等待，由用户手动开始 */
function isAutoStartDownloadEnabled(): boolean {
  return settingsService.get().autoStartDownload;
}

/**
 * 处理下载队列
 * @param force 用户手动触发时忽略"自动开始下载"设置
 */
async function processQueue(force: boolean = false): Promise<void> {
  if (!force && !isAutoStartDownloadEnabled()) {
    return;
  }
  while (getDownloadingCount() < maxConcurrentDownloads && pendingQueue.length > 0) {
    const taskId = pendingQueue.shift();
    if (taskId) {
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
}

/** 手动开始所有等待中的下载（下载页"全部继续"） */
export function startPendingDownloads(): void {
  void processQueue(true);
}

export function setDownloadContext(context: common.UIAbilityContext): void {
  globalContext = context;
  hilog.info(DOMAIN, TAG, 'Download context set');
}

/**
 * 设置最大并发下载数
 */
export function setMaxConcurrentDownloads(max: number): void {
  maxConcurrentDownloads = Math.min(Math.max(1, max), 3);
  hilog.info(DOMAIN, TAG, 'Max concurrent downloads set to: %{public}d', maxConcurrentDownloads);
}

function getContext(): common.UIAbilityContext {
  if (!globalContext) {
    throw new Error('Download context not initialized. Call setDownloadContext first.');
  }
  return globalContext;
}

/**
 * 创建下载任务
 */
export async function createDownloadTask(musicInfo: MusicInfo, quality: Quality): Promise<DownloadTask> {
  const taskId = generateTaskId(musicInfo);

  const task: DownloadTask = {
    id: taskId,
    musicInfo,
    quality,
    status: DownloadStatus.PENDING,
    progress: 0,
    downloadedSize: 0,
    totalSize: 0,
  };

  downloadTasks.set(taskId, task);

  return task;
}

// 下载参数接口
interface StartDownloadParams {
  musicInfo: MusicInfo;
  quality?: Quality;
  savePath?: string;
  onProgress?: DownloadProgressCallback;
}


/**
 * 删除已存在的文件（request.downloadFile 不支持覆盖）
 */
async function removeExistingFile(filePath: string): Promise<void> {
  try {
    await fs.access(filePath);
    // 文件存在，删除它
    await fs.unlink(filePath);
    hilog.info(DOMAIN, TAG, '删除已存在的文件: %{public}s', filePath);
  } catch (e) {
    // 文件不存在，什么都不做
  }
}

/**
 * 把沙箱文件拷贝到目标 URI（documents:// 或 file://）
 */
function copyFileToUri(sandboxFilePath: string, targetUri: string): void {
  let sourceFile: fs.File | null = null;
  let targetFile: fs.File | null = null;
  try {
    sourceFile = fs.openSync(sandboxFilePath, fs.OpenMode.READ_ONLY);
    targetFile = fs.openSync(targetUri, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
    fs.copyFileSync(sourceFile.fd, targetFile.fd);
    fs.fsyncSync(targetFile.fd);
  } finally {
    if (sourceFile !== null) {
      fs.closeSync(sourceFile);
    }
    if (targetFile !== null) {
      fs.closeSync(targetFile);
    }
  }
}

/**
 * 转存到公共下载目录。
 * 优先写入「下载设置 -> 保存位置」配置的目录，失败时回退到系统保存面板。
 */
async function saveSandboxFileToPublicDownload(sandboxFilePath: string, fileName: string): Promise<string> {
  const configuredDir = settingsService.get().downloadPath;
  if (configuredDir && configuredDir.length > 0) {
    const targetUri = `${configuredDir}/${fileName}`;
    try {
      copyFileToUri(sandboxFilePath, targetUri);
      await removeExistingFile(sandboxFilePath);
      hilog.info(DOMAIN, TAG, '已保存到配置的下载目录: %{public}s', targetUri);
      return targetUri;
    } catch (dirErr) {
      const msg = dirErr instanceof Error ? dirErr.message : JSON.stringify(dirErr);
      hilog.warn(DOMAIN, TAG, '写入配置目录失败，回退系统保存面板: %{public}s', msg);
    }
  }

  const context = getContext();
  const picker = new filePicker.DocumentViewPicker(context);
  const saveOptions = new filePicker.DocumentSaveOptions();
  saveOptions.newFileNames = [fileName];

  try {
    const saveUris = await picker.save(saveOptions);
    if (!saveUris || saveUris.length === 0) {
      throw new Error('用户取消保存到公共下载目录');
    }

    const targetUri = saveUris[0];
    try {
      copyFileToUri(sandboxFilePath, targetUri);
    } catch (fileErr) {
      throw new Error('文件写入失败');
    }

    try {
      await removeExistingFile(sandboxFilePath);
    } catch (_cleanupErr) {
      // 清理源文件失败，忽略
    }
    return targetUri;
  } catch (err) {
    let msg = '文件保存失败';
    if (err instanceof Error) {
      msg += ': ' + err.message;
    }
    throw new Error(msg);
  }
}

// 下载历史记录存储键
const DOWNLOAD_HISTORY_KEY = 'download_history';

/**
 * 保存下载历史记录到持久化存储
 */
async function saveDownloadHistory(): Promise<void> {
  try {
    const context = getContext();
    const pref = await preferences.getPreferences(context, 'download_settings');
    const tasks = Array.from(downloadTasks.values());
    // 只保存已完成和失败的任务（取消和正在下载的任务不保存）
    const historyTasks = tasks.filter(t =>
      t.status === DownloadStatus.COMPLETED || t.status === DownloadStatus.FAILED
    );
    await pref.put(DOWNLOAD_HISTORY_KEY, JSON.stringify(historyTasks));
    await pref.flush();
    hilog.info(DOMAIN, TAG, '下载历史已保存: %{public}d 条', historyTasks.length);
  } catch (err) {
    let msg = 'unknown';
    if (err instanceof Error) {
      msg = err.message;
    }
    hilog.warn(DOMAIN, TAG, '保存下载历史失败: %{public}s', msg);
  }
}

/**
 * 从持久化存储加载下载历史记录
 */
async function loadDownloadHistory(): Promise<void> {
  try {
    const context = getContext();
    const pref = await preferences.getPreferences(context, 'download_settings');
    const historyJson = await pref.get(DOWNLOAD_HISTORY_KEY, '') as string;
    if (historyJson && historyJson.length > 0) {
      const historyTasks: DownloadTask[] = JSON.parse(historyJson);
      for (let i = 0; i < historyTasks.length; i++) {
        const task = historyTasks[i];
        downloadTasks.set(task.id, task);
      }
      hilog.info(DOMAIN, TAG, '下载历史已加载: %{public}d 条', historyTasks.length);
    }
  } catch (err) {
    let msg = 'unknown';
    if (err instanceof Error) {
      msg = err.message;
    }
    hilog.warn(DOMAIN, TAG, '加载下载历史失败: %{public}s', msg);
  }
}

/**
 * 初始化下载服务（从存储加载历史）
 */
export async function initDownloadService(): Promise<void> {
  await loadDownloadHistory();
}

/**
 * 暂停下载
 */
export async function pauseDownload(taskId: string): Promise<boolean> {
  const task = downloadTasks.get(taskId);
  if (!task) {
    hilog.warn(DOMAIN, TAG, '暂停失败: 任务不存在 - %{public}s', taskId);
    return false;
  }

  try {
    const requestTask = activeRequestTasks.get(taskId);
    if (requestTask) {
      // request.downloadFile 支持真正的暂停/恢复
      await requestTask.pause();
    } else {
      // 还在队列里等待的任务直接移出队列
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

/**
 * 恢复下载
 */
export async function resumeDownload(taskId: string): Promise<boolean> {
  const task = downloadTasks.get(taskId);
  if (!task) {
    hilog.warn(DOMAIN, TAG, '恢复失败: 任务不存在 - %{public}s', taskId);
    return false;
  }

  try {
    const requestTask = activeRequestTasks.get(taskId);
    if (requestTask) {
      await requestTask.resume();
      task.status = DownloadStatus.DOWNLOADING;
      hilog.info(DOMAIN, TAG, '下载恢复: %{public}s', task.musicInfo.name);
      return true;
    }

    // 没有系统任务句柄（失败/等待中的任务）：重新入队下载
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

/**
 * 取消下载
 */
export async function cancelDownload(taskId: string): Promise<boolean> {
  const task = downloadTasks.get(taskId);
  if (!task) {
    hilog.warn(DOMAIN, TAG, '取消失败: 任务不存在 - %{public}s', taskId);
    return false;
  }

  try {
    // 保存原始状态
    const originalStatus = task.status;

    // 取消系统下载任务（同时删除已写入的部分文件）
    const requestTask = activeRequestTasks.get(taskId);
    if (requestTask) {
      try {
        await requestTask.remove();
      } catch (removeErr) {
        hilog.warn(DOMAIN, TAG, '取消系统下载任务失败: %{public}s',
          removeErr instanceof Error ? removeErr.message : JSON.stringify(removeErr));
      }
      activeRequestTasks.delete(taskId);
    }
    const queueIndex = pendingQueue.indexOf(taskId);
    if (queueIndex > -1) {
      pendingQueue.splice(queueIndex, 1);
    }

    // 标记为已取消
    task.status = DownloadStatus.CANCELLED;

    // 删除部分下载的文件（如果存在且任务正在下载中）
    if (task.filePath && (originalStatus === DownloadStatus.DOWNLOADING || originalStatus === DownloadStatus.PENDING)) {
      try {
        await fs.access(task.filePath);
        await fs.unlink(task.filePath);
        hilog.info(DOMAIN, TAG, '删除部分下载文件: %{public}s', task.filePath);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, '删除部分下载文件失败（文件可能不存在）: %{public}s', (e as Error)?.message);
      }
    }

    // 从任务列表中移除
    downloadTasks.delete(taskId);
    hilog.info(DOMAIN, TAG, '下载取消: %{public}s', task.musicInfo.name);
    return true;
  } catch (error) {
    const errMsg: string = error instanceof Error ? error.message : 'Unknown error';
    hilog.error(DOMAIN, TAG, '取消下载失败: %{public}s - %{public}s', task.musicInfo.name, errMsg);
    return false;
  }
}

/**
 * 使用 request.downloadFile 直接下载到目标路径
 */
async function downloadWithRequestApi(
  task: DownloadTask,
  musicUrl: string,
  targetPath: string,
  onProgress?: DownloadProgressCallback
): Promise<void> {
  const context = getContext();

  // 检查并删除已存在的文件（request.downloadFile 要求文件不存在）
  try {
    const exists = fs.accessSync(targetPath);
    if (exists) {
      hilog.info(DOMAIN, TAG, '文件已存在，删除: %{public}s', targetPath);
      fs.unlinkSync(targetPath);
    }
  } catch (e) {
    // 文件不存在，继续
  }

  // 尝试创建目标目录
  const dirPath = targetPath.substring(0, targetPath.lastIndexOf('/'));
  hilog.info(DOMAIN, TAG, '确保目录存在: %{public}s', dirPath);
  try {
    fs.mkdirSync(dirPath, true);
    hilog.info(DOMAIN, TAG, '目录创建成功或已存在: %{public}s', dirPath);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, '创建目录失败（继续尝试）: %{public}s', (e as Error)?.message);
  }

  hilog.info(DOMAIN, TAG, '直接下载: musicUrl=%{public}s', musicUrl);
  hilog.info(DOMAIN, TAG, '直接下载: targetPath=%{public}s', targetPath);

  return new Promise((resolve, reject) => {
    request.downloadFile(context, {
      url: musicUrl,
      filePath: targetPath,
    }).then((downloadTask) => {
      activeRequestTasks.set(task.id, downloadTask);
      downloadTask.on('progress', (size: number, total: number) => {
        task.downloadedSize = size;
        task.totalSize = total;
        if (total > 0) {
          task.progress = Math.floor((size / total) * 100);
        }
        if (onProgress) {
          onProgress(task);
        }
      });

      downloadTask.on('complete', () => {
        activeRequestTasks.delete(task.id);
        task.progress = 90;
        task.filePath = targetPath;
        hilog.info(DOMAIN, TAG, '沙箱下载完成: %{public}s', targetPath);
        if (onProgress) {
          onProgress(task);
        }
        resolve();
      });

      downloadTask.on('fail', (err: number) => {
        activeRequestTasks.delete(task.id);
        hilog.error(DOMAIN, TAG, '下载失败: %{public}d', err);
        reject(new Error(`Download failed: ${err}`));
      });
    }).catch((err: Error) => {
      activeRequestTasks.delete(task.id);
      hilog.error(DOMAIN, TAG, 'request.downloadFile 失败: %{public}s', err.message);
      reject(err);
    });
  });
}

/**
 * 开始实际下载
 */
async function startActualDownload(task: DownloadTask, onProgress?: DownloadProgressCallback): Promise<number> {
  let savePath = '';
  try {
    // 获取音乐URL（带超时，避免任务长期卡在等待中）
    const musicUrlPromise = getOnlineMusicUrl({
      musicInfo: task.musicInfo,
      isRefresh: false,
    });
    const timeoutPromise = new Promise<null>((_resolve, reject) => {
      setTimeout(() => reject(new Error('获取下载链接超时')), 15000);
    });
    const musicUrl = await Promise.race([musicUrlPromise, timeoutPromise]) as string | null;

    if (!musicUrl) {
      throw new Error('Failed to get music URL');
    }

    const context = getContext();
    const cleanFileName = (task.musicInfo.name + ' - ' + task.musicInfo.singer)
      .replace(/[<>:"/\\|?*]/g, '_')
      .replace(/\s+/g, ' ')
      .trim() + '.mp3';
    const sandboxPath = `${context.filesDir}/downloads/${cleanFileName}`;
    savePath = sandboxPath;
    hilog.info(DOMAIN, TAG, '下载到沙箱: %{public}s', sandboxPath);

    task.status = DownloadStatus.DOWNLOADING;
    task.progress = 0;
    task.filePath = sandboxPath;
    if (onProgress) {
      onProgress(task);
    }

    // Step 1: 先下载到应用沙箱目录。
    try {
      await downloadWithRequestApi(task, musicUrl, sandboxPath, onProgress);

      // Step 2: 拉起系统保存面板，转存到公共 Download 目录。
      task.progress = 95;
      if (onProgress) {
        onProgress(task);
      }
      const publicUri = await saveSandboxFileToPublicDownload(sandboxPath, cleanFileName);
      const publicDir = settingsService.get().downloadPath || DEFAULT_DOWNLOAD_DIR;
      const publicPath = `${publicDir}/${cleanFileName}`;
      hilog.info(DOMAIN, TAG, '转存到公共目录成功: uri=%{public}s path=%{public}s', publicUri, publicPath);

      task.status = DownloadStatus.COMPLETED;
      task.progress = 100;
      task.filePath = publicPath;
      if (onProgress) {
        onProgress(task);
      }
      hilog.info(DOMAIN, TAG, '下载完成: %{public}s', task.musicInfo.name);
      void processQueue();
      void saveDownloadHistory();
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, '下载失败: %{public}s - %{public}s', task.musicInfo.name, errMsg);
      task.status = DownloadStatus.FAILED;
      task.error = errMsg;
      task.filePath = sandboxPath;
      void saveDownloadHistory();
      throw new Error(errMsg);
    }

    const downloadId = Date.now();
    task.downloadId = downloadId;
    hilog.info(DOMAIN, TAG, '开始下载: %{public}s, ID: %{public}d', task.musicInfo.name, downloadId);
    return downloadId;
  } catch (err) {
    // 更好的错误信息格式化
    let errorMessage = 'Unknown error';
    if (err instanceof Error) {
      errorMessage = err.message;
    } else if (typeof err === 'string') {
      errorMessage = err;
    } else if (err && typeof err === 'object') {
      try {
        errorMessage = JSON.stringify(err);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'JSON.stringify failed: %{public}s', (e as Error)?.message);
        errorMessage = String(err);
      }
    }

    const downloadErr: Error = new Error(`Download failed: ${errorMessage}${savePath ? `, path=${savePath}` : ''}`);
    hilog.error(DOMAIN, TAG, '下载失败: %{public}s', downloadErr.message);
    task.status = DownloadStatus.FAILED;
    task.error = downloadErr.message;
    void saveDownloadHistory();
    throw downloadErr;
  }
}

/**
 * 开始下载
 */
export async function startDownload(params: StartDownloadParams): Promise<string> {
  const musicInfo: MusicInfo = params.musicInfo;
  // 未显式指定音质时，跟随"高品质音乐"设置
  const quality: Quality = params.quality ?? settingsService.get().playQuality;
  const taskId: string = generateTaskId(musicInfo);
  const originalOnProgress: DownloadProgressCallback | undefined = params.onProgress;

  // 创建下载任务
  const task: DownloadTask = {
    id: taskId,
    musicInfo,
    quality,
    status: DownloadStatus.PENDING,
    progress: 0,
    downloadedSize: 0,
    totalSize: 0,
    filePath: getDefaultDownloadPath(musicInfo),
    context: getContext()
  };

  downloadTasks.set(taskId, task);

  // 检查并发限制（或用户关闭了"自动开始下载"）
  const currentDownloading = getDownloadingCount();
  if (currentDownloading >= maxConcurrentDownloads || !isAutoStartDownloadEnabled()) {
    // 加入等待队列
    pendingQueue.push(taskId);
    hilog.info(DOMAIN, TAG, '下载任务进入等待队列: %{public}s, 队列长度: %{public}d',
      musicInfo.name, pendingQueue.length);
    if (originalOnProgress) {
      originalOnProgress(task);
    }
    void processQueue();
    return taskId;
  }

  // 直接开始下载
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

/**
 * 获取下载任务
 */
export function getDownloadTask(taskId: string): DownloadTask | null {
  return downloadTasks.get(taskId) || null;
}

/**
 * 获取所有下载任务
 */
export function getAllDownloadTasks(): DownloadTask[] {
  return Array.from(downloadTasks.values());
}

/**
 * 备份用：导出已完成/失败的下载任务（含歌曲信息，便于恢复后仍可播放）
 */
export function exportDownloadTasksForBackup(): DownloadTask[] {
  return Array.from(downloadTasks.values()).filter(
    task => task.status === DownloadStatus.COMPLETED || task.status === DownloadStatus.FAILED
  );
}

/**
 * 恢复备份中的下载任务（恢复为已完成记录，文件路径沿用备份值）。
 * @returns 成功恢复的任务数
 */
export async function restoreDownloadTasksFromBackup(tasks: DownloadTask[]): Promise<number> {
  let restored = 0;
  for (let i = 0; i < tasks.length; i++) {
    const task = tasks[i];
    if (!task || !task.id || !task.musicInfo) {
      continue;
    }
    const existing = downloadTasks.get(task.id);
    if (existing) {
      continue;
    }
    downloadTasks.set(task.id, task);
    restored++;
  }
  if (restored > 0) {
    await saveDownloadHistory();
    hilog.info(DOMAIN, TAG, '下载任务已从备份恢复: %{public}d 条', restored);
  }
  return restored;
}

/**
 * 获取下载中的任务
 */
export function getDownloadingTasks(): DownloadTask[] {
  return Array.from(downloadTasks.values()).filter(
    task => task.status === DownloadStatus.DOWNLOADING || task.status === DownloadStatus.PENDING
  );
}

// 下载歌词参数接口
interface DownloadLyricParams {
  musicInfo: MusicInfo;
  savePath?: string;
}

/**
 * 下载歌词
 */
export async function downloadLyric(params: DownloadLyricParams): Promise<string | null> {
  const musicInfo: MusicInfo = params.musicInfo;
  const savePath: string | undefined = params.savePath;

  try {
    const lyricInfo = await getOnlineLyricInfo({
      musicInfo,
      isRefresh: true,
    });

    if (!lyricInfo.lyric) {
      return null;
    }

    // 保存歌词到文件
    const lyricPath = savePath || getLyricSavePath(musicInfo);
    try {
      const dir = lyricPath.substring(0, lyricPath.lastIndexOf('/'));
      if (!fs.listFileSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      const file = fs.openSync(lyricPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      fs.writeSync(file.fd, lyricInfo.lyric);
      fs.closeSync(file);
      return lyricInfo.lyric;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Save lyric failed: %{public}s', JSON.stringify(err));
    }

    return lyricInfo.lyric;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Download lyric failed: %{public}s', JSON.stringify(err));
    return null;
  }
}

// 下载封面参数接口
interface DownloadPicParams {
  musicInfo: MusicInfo;
  savePath?: string;
}

/**
 * 下载封面
 */
export async function downloadPic(params: DownloadPicParams): Promise<string | null> {
  const musicInfo: MusicInfo = params.musicInfo;
  const savePath: string | undefined = params.savePath;

  try {
    const picUrl = await getOnlinePicUrl({
      musicInfo,
      isRefresh: true,
    });

    if (!picUrl) {
      return null;
    }

    // 下载并保存封面图片
    const picSavePath = savePath || getPicSavePath(musicInfo);
    try {
      const dir = picSavePath.substring(0, picSavePath.lastIndexOf('/'));
      if (!fs.listFileSync(dir)) {
        fs.mkdirSync(dir, true);
      }
      // 使用HTTP请求下载图片
      const task = httpRequest(picUrl, { method: 'GET', responseType: 'binary' });
      const response = await task.promise;
      if (response.status === 200 && response.result) {
        const file = fs.openSync(picSavePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
        fs.writeSync(file.fd, response.result as ArrayBuffer);
        fs.closeSync(file);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Save pic failed: %{public}s', JSON.stringify(err));
    }

    return picUrl;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Download pic failed: %{public}s', JSON.stringify(err));
    return null;
  }
}

/**
 * 生成任务ID
 */
function generateTaskId(musicInfo: MusicInfo): string {
  const key =
    (musicInfo.songmid && musicInfo.songmid.length > 0) ? musicInfo.songmid :
      ((musicInfo.id && musicInfo.id.length > 0) ? musicInfo.id : 'unknown');
  return `dl_${musicInfo.source}_${key}_${Date.now()}`;
}

/**
 * 获取默认下载保存路径
 */
export function getDefaultDownloadPath(musicInfo: MusicInfo): string {
  // 清理文件名中的非法字符
  const cleanFileName = (musicInfo.name + ' - ' + musicInfo.singer)
    .replace(/[<>:"/\\|?*]/g, '_')  // 替换Windows非法字符
    .replace(/\s+/g, ' ')           // 合并多个空格
    .trim();

  // 根据音质选择文件扩展名
  const extension = '.mp3'; // 默认MP3，实际应根据quality选择

  const dir = settingsService.get().downloadPath || DEFAULT_DOWNLOAD_DIR;
  return `${dir}/${cleanFileName}${extension}`;
}

/**
 * 获取歌词保存路径
 */
export function getLyricSavePath(musicInfo: MusicInfo): string {
  try {
    const context = getContext();
    const filesDir = context.filesDir;
    const cleanName = (musicInfo.name + ' - ' + musicInfo.singer)
      .replace(/[<>:"/\\|?*]/g, '_')
      .replace(/\s+/g, ' ')
      .trim();
    return `${filesDir}/lyrics/${cleanName}.lrc`;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'getLyricSavePath failed: %{public}s', (e as Error)?.message);
    throw new Error(`getLyricSavePath failed: ${(e as Error)?.message}`);
  }
}

/**
 * 获取封面保存路径
 */
export function getPicSavePath(musicInfo: MusicInfo): string {
  try {
    const context = getContext();
    const filesDir = context.filesDir;
    const cleanName = (musicInfo.name + ' - ' + musicInfo.singer)
      .replace(/[<>:"/\\|?*]/g, '_')
      .replace(/\s+/g, ' ')
      .trim();
    return `${filesDir}/covers/${cleanName}.jpg`;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'getPicSavePath failed: %{public}s', (e as Error)?.message);
    throw new Error(`getPicSavePath failed: ${(e as Error)?.message}`);
  }
}

// 批量下载参数接口
interface BatchDownloadParams {
  musicList: MusicInfo[];
  quality?: Quality;
  onProgress?: (completed: number, total: number, task: DownloadTask) => void;
}

/**
 * 批量下载
 */
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
        onProgress: (task: DownloadTask) => {
          if (onProgress) {
            onProgress(i + 1, total, task);
          }
        }
      });
      taskIds.push(taskId);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Batch download failed for: %{public}s', musicInfo.name);
      // 继续下载下一首
    }
  }

  return taskIds;
}

/**
 * 清除已完成的任务记录
 */
export function clearCompletedTasks(): void {
  const taskArray = Array.from(downloadTasks.entries());
  for (let i = 0; i < taskArray.length; i++) {
    const taskId = taskArray[i][0];
    const task = taskArray[i][1];
    if (task.status === DownloadStatus.COMPLETED) {
      downloadTasks.delete(taskId);
    }
  }
}

/**
 * 清除所有任务记录
 */
export function clearAllTasks(): void {
  downloadTasks.clear();
}

// 下载模块接口
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
  clearCompletedTasks: () => void;
  clearAllTasks: () => void;
  getDefaultDownloadPath: (musicInfo: MusicInfo) => string;
  getLyricSavePath: (musicInfo: MusicInfo) => string;
  getPicSavePath: (musicInfo: MusicInfo) => string;
  setMaxConcurrentDownloads: (max: number) => void;
  startPendingDownloads: () => void;
}

// 导出命名对象供高级用法
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
  getDefaultDownloadPath,
  getLyricSavePath,
  getPicSavePath,
  setMaxConcurrentDownloads,
  startPendingDownloads,
};
