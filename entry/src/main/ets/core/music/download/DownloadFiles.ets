/**
 * 下载文件层：路径规则、文件搬运、歌词/封面落盘
 *
 * 与「任务队列」分层的原因：队列关心状态机（等待/下载中/暂停/完成），
 * 这一层只关心文件系统与系统下载能力（request.downloadFile / 选择器 / 目录权限）。
 * 两者之前混在一个 991 行文件里，改一处要读完全文。
 *
 * 系统下载任务的句柄（暂停/恢复/删除用）也放在这里：它属于「传输」而不是「队列」。
 */
import { fileIo as fs } from '@kit.CoreFileKit';
import { picker as filePicker } from '@kit.CoreFileKit';
import { request } from '@kit.BasicServicesKit';
import { appLog as hilog } from '../../log/AppLogger';
import { settingsService } from '../../../service/SettingsService';
import { httpRequest } from '../../network/http';
import { t } from '../../../service/LocalizationService';
import { getMusicUrl, getLyricInfo, getPicUrl } from '../ResolvePlayback';
import { buildMusicFileStem } from '../MusicTitle';
import { requireDownloadContext } from './DownloadContext';
import type { MusicInfo } from '../../../types/MusicTypes';
import type { DownloadLyricParams, DownloadPicParams, TransferCallbacks } from './DownloadTypes';

const TAG = 'DOWNLOAD';
const DOMAIN = 0x0003;
const DEFAULT_DOWNLOAD_DIR = '/storage/Users/currentUser/Download';

/** 正在进行的系统下载任务句柄：暂停 / 恢复 / 取消都要用它 */
const activeRequestTasks: Map<string, request.DownloadTask> = new Map();

export function getActiveRequestTask(taskId: string): request.DownloadTask | undefined {
  return activeRequestTasks.get(taskId);
}

export function dropActiveRequestTask(taskId: string): void {
  activeRequestTasks.delete(taskId);
}

/** 默认下载目录（设置里没配时用系统公共下载目录） */
export function getDownloadDir(): string {
  return settingsService.get().downloadPath || DEFAULT_DOWNLOAD_DIR;
}

/** 下载文件名词干（受「设置 → 下载 → 下载文件名」影响） */
function downloadFileStem(musicInfo: MusicInfo): string {
  return buildMusicFileStem(musicInfo, settingsService.get().downloadFileName);
}

/** 沙箱内下载目录：先落到这里，成功后再转存到用户目录 */
export function getSandboxDownloadPath(musicInfo: MusicInfo): string {
  const context = requireDownloadContext();
  return `${context.filesDir}/downloads/${downloadFileStem(musicInfo)}.mp3`;
}

/** 下载后的默认保存路径（设置里的目录 + 文件名） */
export function getDefaultDownloadPath(musicInfo: MusicInfo): string {
  return `${getDownloadDir()}/${downloadFileStem(musicInfo)}.mp3`;
}

/** 歌词保存路径 */
export function getLyricSavePath(musicInfo: MusicInfo): string {
  try {
    const context = requireDownloadContext();
    return `${context.filesDir}/lyrics/${downloadFileStem(musicInfo)}.lrc`;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'getLyricSavePath failed: %{public}s', (e as Error)?.message);
    throw new Error(`getLyricSavePath failed: ${(e as Error)?.message}`);
  }
}

/** 封面保存路径 */
export function getPicSavePath(musicInfo: MusicInfo): string {
  try {
    const context = requireDownloadContext();
    return `${context.filesDir}/covers/${downloadFileStem(musicInfo)}.jpg`;
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'getPicSavePath failed: %{public}s', (e as Error)?.message);
    throw new Error(`getPicSavePath failed: ${(e as Error)?.message}`);
  }
}

/** 删除已存在的文件（request.downloadFile 不支持覆盖写） */
export async function removeExistingFile(filePath: string): Promise<void> {
  try {
    await fs.access(filePath);
    await fs.unlink(filePath);
    hilog.info(DOMAIN, TAG, '删除已存在的文件: %{public}s', filePath);
  } catch (e) {
    // 文件不存在，什么都不做
  }
}

/** 确保目标目录存在 */
export function ensureParentDir(targetPath: string): void {
  const dirPath = targetPath.substring(0, targetPath.lastIndexOf('/'));
  if (dirPath.length === 0) {
    return;
  }
  try {
    fs.mkdirSync(dirPath, true);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, '创建目录失败（继续尝试）: %{public}s', (e as Error)?.message);
  }
}

/** 把沙箱文件拷贝到目标 URI（documents:// 或 file://） */
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
 * 用系统下载能力把 URL 拉到目标路径（支持真正的暂停/恢复）。
 * 进度只上报字节数，任务状态由队列层维护。
 */
export async function transferToPath(
  taskKey: string, url: string, targetPath: string, callbacks?: TransferCallbacks): Promise<void> {
  const context = requireDownloadContext();
  await removeExistingFile(targetPath);
  ensureParentDir(targetPath);
  hilog.info(DOMAIN, TAG, '直接下载: url=%{public}s -> %{public}s', url, targetPath);

  return new Promise((resolve, reject) => {
    request.downloadFile(context, { url: url, filePath: targetPath }).then((downloadTask) => {
      activeRequestTasks.set(taskKey, downloadTask);
      downloadTask.on('progress', (size: number, total: number) => {
        if (callbacks && callbacks.onBytes) {
          callbacks.onBytes(size, total);
        }
      });
      downloadTask.on('complete', () => {
        activeRequestTasks.delete(taskKey);
        hilog.info(DOMAIN, TAG, '沙箱下载完成: %{public}s', targetPath);
        resolve();
      });
      downloadTask.on('fail', (err: number) => {
        activeRequestTasks.delete(taskKey);
        hilog.error(DOMAIN, TAG, '下载失败: %{public}d', err);
        reject(new Error(`Download failed: ${err}`));
      });
    }).catch((err: Error) => {
      activeRequestTasks.delete(taskKey);
      hilog.error(DOMAIN, TAG, 'request.downloadFile 失败: %{public}s', err.message);
      reject(err);
    });
  });
}

/**
 * 转存到公共下载目录。
 *
 * 优先级：
 * 1. 「下载设置 → 保存位置」配置的目录（正常路径）；
 * 2. 配置目录不可写时，若开启了「每次下载询问保存位置」则拉起保存面板由用户决定；
 * 3. 否则保留在应用沙箱目录（文件已下载完成，不打扰用户）。
 *
 * @returns 实际可播放的路径（file:// 形式）
 */
export async function saveSandboxFileToPublicDownload(
  sandboxFilePath: string, fileName: string): Promise<string> {
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
      hilog.warn(DOMAIN, TAG, '写入配置目录失败: %{public}s', msg);
    }
  }

  if (!settingsService.get().downloadUseFilePicker) {
    const sandboxUri = `file://${sandboxFilePath}`;
    hilog.info(DOMAIN, TAG, '保留在应用目录（可在下载设置里配置保存位置）: %{public}s', sandboxUri);
    return sandboxUri;
  }

  const context = requireDownloadContext();
  const picker = new filePicker.DocumentViewPicker(context);
  const saveOptions = new filePicker.DocumentSaveOptions();
  saveOptions.newFileNames = [fileName];
  try {
    const saveUris = await picker.save(saveOptions);
    if (!saveUris || saveUris.length === 0) {
      throw new Error(t('download_save_cancelled'));
    }
    const targetUri = saveUris[0];
    try {
      copyFileToUri(sandboxFilePath, targetUri);
    } catch (fileErr) {
      // 同上：这条会作为失败原因展示，走 i18n
      throw new Error(t('media_save_fail'));
    }
    try {
      await removeExistingFile(sandboxFilePath);
    } catch (_cleanupErr) {
      // 清理源文件失败，忽略
    }
    return targetUri;
  } catch (err) {
    // 这条消息会显示在下载任务的失败原因里，必须走 i18n（英文界面不能出现中文）
    let msg = t('media_save_fail');
    if (err instanceof Error) {
      msg += ': ' + err.message;
    }
    throw new Error(msg);
  }
}

/** 获取音乐下载链接（带超时，避免任务长期卡在等待中） */
export async function resolveMusicUrl(musicInfo: MusicInfo, timeoutMs: number = 15000): Promise<string> {
  const urlPromise = getMusicUrl({ musicInfo: musicInfo, isRefresh: false });
  const timeoutPromise = new Promise<null>((_resolve, reject) => {
    setTimeout(() => reject(new Error('获取下载链接超时')), timeoutMs);
  });
  const url = await Promise.race([urlPromise, timeoutPromise]) as string | null;
  if (!url) {
    throw new Error('Failed to get music URL');
  }
  return url;
}

/** 下载歌词到文件（返回歌词文本，失败返回 null） */
export async function downloadLyric(params: DownloadLyricParams): Promise<string | null> {
  const musicInfo: MusicInfo = params.musicInfo;
  try {
    const lyricInfo = await getLyricInfo({ musicInfo: musicInfo, isRefresh: true });
    if (!lyricInfo.lyric) {
      return null;
    }
    const lyricPath = params.savePath || getLyricSavePath(musicInfo);
    try {
      ensureParentDir(lyricPath);
      const file = fs.openSync(lyricPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      fs.writeSync(file.fd, lyricInfo.lyric);
      fs.closeSync(file);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Save lyric failed: %{public}s', JSON.stringify(err));
    }
    return lyricInfo.lyric;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Download lyric failed: %{public}s', JSON.stringify(err));
    return null;
  }
}

/** 下载封面到文件（返回封面 URL，失败返回 null） */
export async function downloadPic(params: DownloadPicParams): Promise<string | null> {
  const musicInfo: MusicInfo = params.musicInfo;
  try {
    const picUrl = await getPicUrl({ musicInfo: musicInfo, isRefresh: true });
    if (!picUrl) {
      return null;
    }
    const picSavePath = params.savePath || getPicSavePath(musicInfo);
    try {
      ensureParentDir(picSavePath);
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
