/**
 * 下载历史持久化 + 备份导入导出
 *
 * 只做「任务数组 ↔ 存储」的转换，不认识队列，所以返回/接收的都是数组：
 * 队列层负责把结果并入内存里的任务表，测试与备份服务也能单独复用这一层。
 */
import { preferences } from '@kit.ArkData';
import { appLog as hilog } from '../../log/AppLogger';
import { requireDownloadContext } from './DownloadContext';
import { DownloadStatus, type DownloadTask } from './DownloadTypes';

const TAG = 'DOWNLOAD';
const DOMAIN = 0x0003;
const LEGACY_DOWNLOAD_STORE = 'download_settings';
const DOWNLOAD_HISTORY_KEY = 'download_history';

/** 只保留「完成 / 失败」的任务，避免把进行中的任务写成假历史 */
export function pickHistoricTasks(tasks: DownloadTask[]): DownloadTask[] {
  return tasks.filter((task: DownloadTask): boolean =>
    task.status === DownloadStatus.COMPLETED || task.status === DownloadStatus.FAILED);
}

export async function saveDownloadHistory(tasks: DownloadTask[]): Promise<void> {
  try {
    const context = requireDownloadContext();
    const pref = await preferences.getPreferences(context, LEGACY_DOWNLOAD_STORE);
    const historyTasks = pickHistoricTasks(tasks);
    await pref.put(DOWNLOAD_HISTORY_KEY, JSON.stringify(historyTasks));
    await pref.flush();
    hilog.info(DOMAIN, TAG, '下载历史已保存: %{public}d 条', historyTasks.length);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, '保存下载历史失败: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
  }
}

export async function loadDownloadHistory(): Promise<DownloadTask[]> {
  try {
    const context = requireDownloadContext();
    const pref = await preferences.getPreferences(context, LEGACY_DOWNLOAD_STORE);
    const historyJson = await pref.get(DOWNLOAD_HISTORY_KEY, '') as string;
    if (historyJson && historyJson.length > 0) {
      const historyTasks: DownloadTask[] = JSON.parse(historyJson);
      hilog.info(DOMAIN, TAG, '下载历史已加载: %{public}d 条', historyTasks.length);
      return historyTasks;
    }
  } catch (err) {
    hilog.warn(DOMAIN, TAG, '加载下载历史失败: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
  }
  return [];
}

/** 备份用：导出可恢复的任务（含歌曲信息，恢复后仍可播放） */
export function exportTasksForBackup(tasks: DownloadTask[]): DownloadTask[] {
  return pickHistoricTasks(tasks);
}
