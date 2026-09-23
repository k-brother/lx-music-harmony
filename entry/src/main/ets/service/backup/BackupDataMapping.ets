/**
 * 备份数据映射：本地数据 ↔ 备份文件内容
 *
 * 从 BackupService 抽出：这些方法都在做「按类型收集 / 按类型恢复」的搬运，
 * 与定时器、文件读写、密码无关。抽出来后备份服务只剩「文件 + 配置 + 调度」。
 */
import { appLog as hilog } from '../../core/log/AppLogger';
import {
  addMusicToList,
  createUserList,
  getDefaultList,
  getLoveList,
  getUserList,
  getUserListMusic,
  LIST_IDS,
} from '../ListService';
import { DownloadStatus } from '../../core/music/download/DownloadTypes';
import type { MusicInfo, Quality } from '../../types/MusicTypes';
import { settingsService, type SettingsPatch } from '../SettingsService';
import { musicItemFromPlainObject } from '../../core/list/PlaylistRecordMapper';
import { exportDownloadTasksForBackup, restoreDownloadTasksFromBackup, type DownloadTask } from '../../core/music/RunMusicDownloads';
import { BackupDataType } from './BackupTypes';
import type {
  BackupDataContent,
  BackupDownloadSnapshot,
  BackupPlaylistSnapshot,
} from './BackupTypes';

const TAG = 'BackupDataMapping';
const DOMAIN: number = 0x0001;

// 收集备份数据
export async function collectBackupData(dataType: BackupDataType): Promise<BackupDataContent> {
  const backupData: BackupDataContent = {
    appVersion: '1.0.0',
    backupTime: new Date().toISOString(),
    dataType,
    data: {
      playlists: undefined,
      settings: undefined,
      downloads: undefined
    }
  };

  try {
    // 收集歌单数据
    if (dataType === BackupDataType.ALL || dataType === BackupDataType.PLAYLISTS) {
      backupData.data.playlists = await collectPlaylistData();
    }

    // 收集设置数据
    if (dataType === BackupDataType.ALL || dataType === BackupDataType.SETTINGS) {
      backupData.data.settings = await collectSettingsData();
    }

    // 收集下载数据
    if (dataType === BackupDataType.ALL || dataType === BackupDataType.DOWNLOADS) {
      backupData.data.downloads = await collectDownloadData();
    }

  } catch (err) {
    const errorMsg: string = err instanceof Error ? err.message : 'Unknown error';
    hilog.error(DOMAIN, TAG, 'Failed to collect backup data: %{public}s', errorMsg);
    throw new Error(`Failed to collect backup data: ${errorMsg}`);
  }

  return backupData;
}

// 收集歌单数据
export async function collectPlaylistData(): Promise<BackupPlaylistSnapshot[]> {
  try {
    hilog.info(DOMAIN, TAG, 'Collecting playlist data');

    const playlists: BackupPlaylistSnapshot[] = [];

    // 默认列表
    const defaultMusic = getDefaultList();
    playlists.push({
      id: LIST_IDS.DEFAULT,
      name: '默认列表',
      musicList: defaultMusic.map((item: Object): Object => item as Object),
      createTime: Date.now(),
      updateTime: Date.now()
    });

    // 我喜欢列表
    const loveMusic = getLoveList();
    playlists.push({
      id: LIST_IDS.LOVE,
      name: '我喜欢',
      musicList: loveMusic.map((item: Object): Object => item as Object),
      createTime: Date.now(),
      updateTime: Date.now()
    });

    // 用户自定义列表
    const userLists = getUserList();
    for (let i = 0; i < userLists.length; i++) {
      const list = userLists[i];
      const songs = getUserListMusic(list.id);
      playlists.push({
        id: list.id,
        name: list.name,
        musicList: songs.map((item: Object): Object => item as Object),
        createTime: list.createTime || Date.now(),
        updateTime: list.updateTime || Date.now()
      });
    }

    hilog.info(DOMAIN, TAG, 'Collected %{public}d playlists', playlists.length);
    return playlists;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to collect playlist data: %{public}s', JSON.stringify(err));
    return [];
  }
}

// 收集设置数据
export async function collectSettingsData(): Promise<Record<string, Object>> {
  try {
    hilog.info(DOMAIN, TAG, 'Collecting settings data');

    // 设置项统一由 SettingsService 提供（同一份 Preferences 存储）
    const settings: Record<string, Object> = {};
    settings['app_settings'] = JSON.stringify(settingsService.get());

    // 添加应用信息
    settings['appVersion'] = '1.0.0';
    settings['backupTime'] = new Date().toISOString();

    hilog.info(DOMAIN, TAG, 'Collected %{public}d settings', Object.keys(settings).length);
    return settings;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to collect settings data: %{public}s', JSON.stringify(err));
    return {};
  }
}

// 收集下载数据
export async function collectDownloadData(): Promise<BackupDownloadSnapshot[]> {
  try {
    const tasks: DownloadTask[] = exportDownloadTasksForBackup();
    const snapshots: BackupDownloadSnapshot[] = [];
    for (let i = 0; i < tasks.length; i++) {
      const task = tasks[i];
      snapshots.push({
        id: task.id,
        fileName: task.musicInfo ? `${task.musicInfo.name} - ${task.musicInfo.singer}` : '',
        filePath: task.filePath ?? '',
        status: task.status,
        createTime: Date.now(),
        musicInfo: task.musicInfo as Object,
        quality: task.quality,
        progress: task.progress,
      });
    }
    hilog.info(DOMAIN, TAG, 'Collected %{public}d download tasks', snapshots.length);
    return snapshots;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'collectDownloadData failed: %{public}s', JSON.stringify(err));
    return [];
  }
}

// 验证备份数据
export function validateBackupData(data: BackupDataContent, expectedDataType: BackupDataType): boolean {
  if (!data || typeof data !== 'object') {
    return false;
  }

  if (!data.appVersion || !data.backupTime || !data.dataType) {
    return false;
  }

  if (data.dataType !== expectedDataType) {
    return false;
  }

  if (!data.data || typeof data.data !== 'object') {
    return false;
  }

  return true;
}

// 恢复备份数据
export async function restoreBackupData(backupData: BackupDataContent, dataType: BackupDataType): Promise<void> {
  try {
    // 恢复歌单数据
    if (dataType === BackupDataType.ALL || dataType === BackupDataType.PLAYLISTS) {
      if (backupData.data && backupData.data.playlists) {
        await restorePlaylistData(backupData.data.playlists);
      }
    }

    // 恢复设置数据
    if (dataType === BackupDataType.ALL || dataType === BackupDataType.SETTINGS) {
      if (backupData.data && backupData.data.settings) {
        await restoreSettingsData(backupData.data.settings);
      }
    }

    // 恢复下载数据
    if (dataType === BackupDataType.ALL || dataType === BackupDataType.DOWNLOADS) {
      if (backupData.data && backupData.data.downloads) {
        await restoreDownloadData(backupData.data.downloads);
      }
    }

  } catch (err) {
    const errorMsg: string = err instanceof Error ? err.message : 'Unknown error';
    hilog.error(DOMAIN, TAG, 'Failed to restore backup data: %{public}s', errorMsg);
    throw new Error(`Failed to restore backup data: ${errorMsg}`);
  }
}

// 恢复歌单数据
export async function restorePlaylistData(playlists: BackupPlaylistSnapshot[]): Promise<void> {
  try {
    hilog.info(DOMAIN, TAG, 'Restoring playlist data, count: %{public}d', playlists.length);

    for (const playlist of playlists) {
      const listName = playlist.name || '未知歌单';
      const songs = playlist.musicList || [];
      hilog.info(DOMAIN, TAG, 'Restoring playlist: %{public}s (%{public}d songs)', listName, songs.length);

      if (playlist.id === LIST_IDS.DEFAULT) {
        // 恢复到默认列表
        for (let i = 0; i < songs.length; i++) {
          await addMusicToList(LIST_IDS.DEFAULT, musicItemFromPlainObject(songs[i] as Object));
        }
      } else if (playlist.id === LIST_IDS.LOVE) {
        // 恢复到我喜欢的列表
        for (let i = 0; i < songs.length; i++) {
          await addMusicToList(LIST_IDS.LOVE, musicItemFromPlainObject(songs[i] as Object));
        }
      } else {
        // 用户自定义歌单
        const newList = await createUserList(listName);
        for (let i = 0; i < songs.length; i++) {
          await addMusicToList(newList.id, musicItemFromPlainObject(songs[i] as Object));
        }
      }
    }

    hilog.info(DOMAIN, TAG, 'Playlist data restored successfully');
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to restore playlist data: %{public}s', JSON.stringify(err));
    const msg = err instanceof Error ? err.message : JSON.stringify(err);
    throw new Error(msg);
  }
}

// 恢复设置数据
export async function restoreSettingsData(settings: Record<string, Object>): Promise<void> {
  try {
    hilog.info(DOMAIN, TAG, 'Restoring settings data');

    const payload = settings['app_settings'];
    if (typeof payload !== 'string' || payload.length === 0) {
      hilog.warn(DOMAIN, TAG, 'Backup contains no app_settings payload, nothing to restore');
      return;
    }
    const patch: SettingsPatch = JSON.parse(payload) as SettingsPatch;
    await settingsService.update(patch);
    hilog.info(DOMAIN, TAG, 'Settings data restored successfully');
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to restore settings data: %{public}s', JSON.stringify(err));
    const msg = err instanceof Error ? err.message : JSON.stringify(err);
    throw new Error(msg);
  }
}

// 恢复下载数据
export async function restoreDownloadData(downloads: BackupDownloadSnapshot[]): Promise<void> {
  try {
    hilog.info(DOMAIN, TAG, 'Restoring download data, count: %{public}d', downloads.length);
    const tasks: DownloadTask[] = [];
    for (let i = 0; i < downloads.length; i++) {
      const snapshot = downloads[i];
      if (!snapshot.musicInfo) {
        continue;
      }
      tasks.push({
        id: snapshot.id,
        musicInfo: snapshot.musicInfo as MusicInfo,
        quality: (snapshot.quality ?? '128k') as Quality,
        status: snapshot.status === DownloadStatus.COMPLETED
          ? DownloadStatus.COMPLETED : DownloadStatus.FAILED,
        progress: snapshot.progress ?? 100,
        downloadedSize: 0,
        totalSize: 0,
        filePath: snapshot.filePath,
      });
    }
    const restored = await restoreDownloadTasksFromBackup(tasks);
    hilog.info(DOMAIN, TAG, 'Download data restored: %{public}d tasks', restored);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to restore download data: %{public}s', JSON.stringify(err));
    const msg = err instanceof Error ? err.message : JSON.stringify(err);
    throw new Error(msg);
  }
}
