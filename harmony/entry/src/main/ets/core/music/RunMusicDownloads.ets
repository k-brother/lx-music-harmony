// 下载任务与系统下载 API（原 download.ets）

import type { MusicInfo, LyricInfo, Quality } from '../../types/MusicTypes';
import { getMusicUrl as getOnlineMusicUrl } from './MusicFeatureEntry';
import { getPicUrl as getOnlinePicUrl, getLyricInfo as getOnlineLyricInfo } from './ResolvePlayback';
import { buildLyricInfo } from './MusicParsingUtils';
import hilog from '@ohos.hilog';
import fs from '@ohos.file.fs';
import { httpRequest } from '../network/http';
import { common } from '@kit.AbilityKit';
import { request } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';

// 鸿蒙下载配置接口
interface DownloadConfig {
  url: string;
  title: string;
  description: string;
  savePath: string;
  enableMetered?: boolean;
  enableRoaming?: boolean;
  networkType?: number;
  header?: Record<string, string>;
}

// 鸿蒙下载状态枚举（根据鸿蒙API定义）
enum DownloadState {
  PENDING = 0,      // 等待下载
  DOWNLOADING = 1,  // 下载中
  PAUSED = 2,       // 暂停
  COMPLETED = 3,    // 完成
  FAILED = 4        // 失败
}

const TAG = 'DOWNLOAD';
const DOMAIN = 0x0003;

// 下载状态
export enum DownloadStatus {
  PENDING = 'pending',
  DOWNLOADING = 'downloading',
  PAUSED = 'paused',
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

// 鸿蒙下载任务Map (存储实际的downloadAgent任务)
const harmonyDownloadTasks: Map<number, request.DownloadTask> = new Map();

export function setDownloadContext(context: common.UIAbilityContext): void {
  globalContext = context;
  hilog.info(DOMAIN, TAG, 'Download context set');
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
 * 设置下载监听器 - 使用HTTP请求代替原生下载管理器
 */
function setupDownloadListeners(downloadId: number, taskId: string, onProgress?: DownloadProgressCallback): void {
  // HTTP请求的进度通过startActualDownload内部处理
}

/**
 * 确保目录存在
 */
async function ensureDirectoryExists(filePath: string): Promise<void> {
  try {
    const dirPath = filePath.substring(0, filePath.lastIndexOf('/'));

    try {
      // 检查目录是否存在
      fs.accessSync(dirPath);
      hilog.debug(DOMAIN, TAG, '目录已存在: %{public}s', dirPath);
    } catch {
      // 目录不存在，创建它
      fs.mkdirSync(dirPath);
      hilog.info(DOMAIN, TAG, '创建目录: %{public}s', dirPath);
    }
  } catch (err) {
    const errorMsg: string = err instanceof Error ? err.message : 'Unknown error';
    hilog.error(DOMAIN, TAG, '确保目录存在失败: %{public}s', errorMsg);
    const dirError: Error = new Error(errorMsg);
    throw dirError;
  }
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
    // HarmonyOS downloadFile API 不支持暂停功能
    // 只能通过取消下载来实现类似暂停效果
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
  if (!task || task.status !== DownloadStatus.PAUSED) {
    hilog.warn(DOMAIN, TAG, '恢复失败: 任务不存在或状态不是暂停 - %{public}s', taskId);
    return false;
  }

  try {
    // HarmonyOS downloadFile API 不支持恢复功能
    // 需要重新创建下载任务
    task.status = DownloadStatus.DOWNLOADING;
    hilog.info(DOMAIN, TAG, '下载恢复: %{public}s', task.musicInfo.name);
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

    // 标记为已取消（使用PAUSED状态表示已取消）
    task.status = DownloadStatus.PAUSED;

    // 删除部分下载的文件（如果存在且任务正在下载中）
    if (task.filePath && (originalStatus === DownloadStatus.DOWNLOADING || originalStatus === DownloadStatus.PENDING)) {
      try {
        await fs.access(task.filePath);
        await fs.unlink(task.filePath);
        hilog.info(DOMAIN, TAG, '删除部分下载文件: %{public}s', task.filePath);
      } catch {
        // 文件不存在，忽略
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
 * 开始实际下载
 */
async function startActualDownload(task: DownloadTask, onProgress?: DownloadProgressCallback): Promise<number> {
  try {
    // 获取音乐URL
    const musicUrl = await getOnlineMusicUrl({
      musicInfo: task.musicInfo,
      isRefresh: false,
    });

    if (!musicUrl) {
      throw new Error('Failed to get music URL');
    }

    // 确保文件路径存在
    const filePath = task.filePath || getDefaultDownloadPath(task.musicInfo);
    task.filePath = filePath;

    // 创建目录（如果不存在）
    await ensureDirectoryExists(filePath);

    // 使用鸿蒙 downloadFile API 进行下载
    const context = getContext();
    const filesDir = context.filesDir;
    const fileName = `${task.musicInfo.name} - ${task.musicInfo.singer}.mp3`.replace(/[<>:"/\\|?*]/g, '_');
    const savePath = `${filesDir}/Download/LxMusic/${fileName}`;



    // 使用鸿蒙 downloadFile API 进行下载
    const downloadContext = getContext();
    const downloadTask: request.DownloadTask = await request.downloadFile(downloadContext, {
      url: musicUrl,
      filePath: savePath
    });

    // 设置下载状态为下载中
    task.status = DownloadStatus.DOWNLOADING;
    const downloadId = Date.now(); // 使用时间戳作为临时ID
    task.downloadId = downloadId;

    // 设置下载进度监听
    if (onProgress) {
      downloadTask.on('progress', (size: number, total: number) => {
        task.downloadedSize = size;
        task.totalSize = total;
        task.progress = total > 0 ? Math.floor((size / total) * 100) : 0;
        onProgress(task);
      });

      downloadTask.on('complete', () => {
        task.status = DownloadStatus.COMPLETED;
        task.progress = 100;
        task.filePath = savePath;
        onProgress(task);
        hilog.info(DOMAIN, TAG, '下载完成: %{public}s', task.musicInfo.name);
      });

      downloadTask.on('fail', () => {
        task.status = DownloadStatus.FAILED;
        task.error = '下载失败';
        onProgress(task);
        hilog.error(DOMAIN, TAG, '下载失败: %{public}s', task.musicInfo.name);
      });
    }



    // 保存下载任务引用
    harmonyDownloadTasks.set(downloadId, downloadTask);

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
      } catch {
        errorMessage = String(err);
      }
    }
    
    const downloadErr: Error = new Error(`Download failed: ${errorMessage}`);
    hilog.error(DOMAIN, TAG, '下载失败: %{public}s', downloadErr.message);
    task.status = DownloadStatus.FAILED;
    task.error = downloadErr.message;
    throw downloadErr;
  }
}

/**
 * 开始下载
 */
export async function startDownload(params: StartDownloadParams): Promise<string> {
  const musicInfo: MusicInfo = params.musicInfo;
  const quality: Quality = params.quality ?? '128k';
  const taskId: string = generateTaskId(musicInfo);
  const originalOnProgress: DownloadProgressCallback | undefined = params.onProgress;

  try {
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

    // 开始实际下载
    const downloadId = await startActualDownload(task, originalOnProgress);
    task.downloadId = downloadId;

    return taskId;
  } catch (err) {
    const detail =
      err instanceof Error ? err.message : (typeof err === 'string' ? err : JSON.stringify(err));
    const downloadErr: Error = new Error(`Download failed: ${detail}`);
    hilog.error(DOMAIN, TAG, 'Download failed: %{public}s', downloadErr.message);

    const task = downloadTasks.get(taskId);
    if (task) {
      task.status = DownloadStatus.FAILED;
      task.error = downloadErr.message;
      if (originalOnProgress) {
        originalOnProgress(task);
      }
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
  try {
    const context = getContext();
    const filesDir = context.filesDir;

    // 清理文件名中的非法字符
    const cleanFileName = (musicInfo.name + ' - ' + musicInfo.singer)
      .replace(/[<>:"/\\|?*]/g, '_')  // 替换Windows非法字符
      .replace(/\s+/g, ' ')           // 合并多个空格
      .trim();

    // 根据音质选择文件扩展名
    const extension = '.mp3'; // 默认MP3，实际应根据quality选择

    return `${filesDir}/Download/LxMusic/${cleanFileName}${extension}`;
  } catch (error) {
    // 如果无法获取上下文，返回一个合理的默认路径
    hilog.warn(DOMAIN, TAG, '无法获取上下文，使用默认路径: %{public}s', error instanceof Error ? error.message : 'Unknown error');
    return `/data/local/tmp/LxMusic/${musicInfo.name} - ${musicInfo.singer}.mp3`;
  }
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
  } catch {
    return `/data/local/tmp/LxMusic/lyrics/${musicInfo.name} - ${musicInfo.singer}.lrc`;
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
  } catch {
    return `/data/local/tmp/LxMusic/covers/${musicInfo.name} - ${musicInfo.singer}.jpg`;
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
}

// 导出命名对象供高级用法
export const download: DownloadModule = {
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
};
