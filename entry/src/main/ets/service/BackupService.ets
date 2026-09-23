// 备份与恢复服务
// 对应安卓版的备份恢复功能

import hilog from '@ohos.hilog';
import fs from '@ohos.file.fs';
import filePicker from '@ohos.file.picker';
import { common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import { encryptWithPassword, decryptWithPassword } from './crypto/AesPayload';
import { utf8Decode } from '../utils/TextCodec';
import {
  getUserList,
  getDefaultList,
  getLoveList,
  getUserListMusic,
  createUserList,
  addMusicToList,
  LIST_IDS,
} from './ListService';
import { musicItemFromPlainObject } from '../core/list/PlaylistRecordMapper';
import { settingsService, type SettingsPatch } from './SettingsService';
import {
  exportDownloadTasksForBackup,
  restoreDownloadTasksFromBackup,
  DownloadStatus,
  type DownloadTask,
} from '../core/music/RunMusicDownloads';
import type { MusicInfo, Quality } from '../types/MusicTypes';

const DOMAIN: number = 0x0001;
const TAG: string = 'BackupService';

// 备份数据类型
export enum BackupDataType {
  ALL = 'all',
  PLAYLISTS = 'playlists',
  SETTINGS = 'settings',
  DOWNLOADS = 'downloads'
}

// 备份文件信息
export interface BackupFileInfo {
  fileName: string;
  filePath: string;
  fileSize: number;
  backupTime: number;
  dataType: BackupDataType;
  version: string;
}

// 备份配置
export interface BackupConfig {
  autoBackup: boolean;
  backupInterval: number; // 天数
  backupLocation: string;
  encryptBackup: boolean;
  backupPassword?: string;
}

// 备份数据内容
interface BackupDataContent {
  appVersion: string;
  backupTime: string;
  dataType: BackupDataType;
  data: BackupData;
}

// 备份中的歌单快照
interface BackupPlaylistSnapshot {
  id: string;
  name: string;
  musicList: Object[];
  createTime: number;
  updateTime: number;
}

// 备份中的下载任务快照
interface BackupDownloadSnapshot {
  id: string;
  fileName: string;
  filePath: string;
  status: string;
  createTime: number;
  /** 歌曲信息（恢复后仍可播放/展示） */
  musicInfo?: Object;
  quality?: string;
  progress?: number;
}

// 备份数据
interface BackupData {
  playlists?: BackupPlaylistSnapshot[];
  settings?: Record<string, Object>;
  downloads?: BackupDownloadSnapshot[];
}



// 备份服务类
export class BackupService {
  private static instance: BackupService;
  private config: BackupConfig = {
    autoBackup: false,
    backupInterval: 7,
    backupLocation: '',
    encryptBackup: false
  };
  
  private backupTimer: number | null = null;
  private abilityContext: common.UIAbilityContext | null = null;

  private constructor() {}

  // 单例获取
  static getInstance(): BackupService {
    if (!BackupService.instance) {
      BackupService.instance = new BackupService();
    }
    return BackupService.instance;
  }

  // 初始化
  async initialize(): Promise<void> {
    try {
      await this.loadConfig();
      
      if (this.config.autoBackup) {
        this.startAutoBackup();
      }
      
      hilog.info(DOMAIN, TAG, 'Backup service initialized');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to initialize backup service: %{public}s', JSON.stringify(err));
    }
  }

  // 加载配置
  async loadConfig(): Promise<void> {
    try {
      const context = this.getContext();
      const pref = await preferences.getPreferences(context, 'backup_config');
      
      this.config.autoBackup = await pref.get('autoBackup', false) as boolean;
      this.config.backupInterval = await pref.get('backupInterval', 7) as number;
      this.config.backupLocation = await pref.get('backupLocation', context.filesDir) as string;
      this.config.encryptBackup = await pref.get('encryptBackup', false) as boolean;
      this.config.backupPassword = await pref.get('backupPassword', '') as string;
      
      hilog.info(DOMAIN, TAG, 'Backup config loaded');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to load backup config: %{public}s', JSON.stringify(err));
    }
  }

  // 保存配置
  async saveConfig(): Promise<void> {
    try {
      const context = this.getContext();
      const pref = await preferences.getPreferences(context, 'backup_config');
      
      await pref.put('autoBackup', this.config.autoBackup);
      await pref.put('backupInterval', this.config.backupInterval);
      await pref.put('backupLocation', this.config.backupLocation);
      await pref.put('encryptBackup', this.config.encryptBackup);
      if (this.config.backupPassword) {
        await pref.put('backupPassword', this.config.backupPassword);
      }
      
      await pref.flush();
      hilog.info(DOMAIN, TAG, 'Backup config saved');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save backup config: %{public}s', JSON.stringify(err));
    }
  }

  // 获取配置
  getConfig(): BackupConfig {
    const result: BackupConfig = {
      autoBackup: this.config.autoBackup,
      backupInterval: this.config.backupInterval,
      backupLocation: this.config.backupLocation,
      encryptBackup: this.config.encryptBackup
    };
    if (this.config.backupPassword) {
      result.backupPassword = this.config.backupPassword;
    }
    return result;
  }

  // 更新配置
  async updateConfig(newConfig: Partial<BackupConfig>): Promise<void> {
    if (newConfig.autoBackup !== undefined) {
      this.config.autoBackup = newConfig.autoBackup;
    }
    if (newConfig.backupInterval !== undefined) {
      this.config.backupInterval = newConfig.backupInterval;
    }
    if (newConfig.backupLocation !== undefined) {
      this.config.backupLocation = newConfig.backupLocation;
    }
    if (newConfig.encryptBackup !== undefined) {
      this.config.encryptBackup = newConfig.encryptBackup;
    }
    if (newConfig.backupPassword !== undefined) {
      this.config.backupPassword = newConfig.backupPassword;
    }
    await this.saveConfig();
    
    // 重新启动自动备份
    if (this.backupTimer) {
      clearInterval(this.backupTimer);
      this.backupTimer = null;
    }
    
    if (this.config.autoBackup) {
      this.startAutoBackup();
    }
  }

  // 创建备份
  async createBackup(dataType: BackupDataType = BackupDataType.ALL): Promise<BackupFileInfo | null> {
    try {
      hilog.info(DOMAIN, TAG, 'Creating backup for data type: %{public}s', dataType);
      
      // 1. 收集数据
      const backupData = await this.collectBackupData(dataType);
      
      // 2. 转换为JSON
      const jsonData = JSON.stringify(backupData, null, 2);
      
      // 3. 加密数据（如果启用）
      let finalData = jsonData;
      if (this.config.encryptBackup && this.config.backupPassword) {
        finalData = await this.encryptData(jsonData, this.config.backupPassword);
      }
      
      // 4. 确保备份目录存在
      await this.ensureBackupDirectoryExists();
      
      // 5. 生成文件名
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      const fileName = this.generateBackupFileName(dataType, timestamp);
      const filePath = `${this.config.backupLocation}/${fileName}`;
      
      // 6. 保存文件（使用同步接口）
      const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      try {
        fs.writeSync(file.fd, finalData);
        fs.fsyncSync(file.fd);
      } finally {
        fs.closeSync(file.fd);
      }
      
      hilog.info(DOMAIN, TAG, 'Backup created successfully: %{public}s', fileName);
      
      // 5. 返回备份信息
      const fileInfo: BackupFileInfo = {
        fileName,
        filePath,
        fileSize: finalData.length,
        backupTime: Date.now(),
        dataType,
        version: '1.0.0'
      };
      
      return fileInfo;
      
    } catch (err) {
      const errorMsg: string = JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to create backup: %{public}s', errorMsg);
      return null;
    }
  }

  // 恢复备份
  async restoreBackup(backupFile: BackupFileInfo): Promise<boolean> {
    try {
      // 1. 读取文件
      const file = fs.openSync(backupFile.filePath, fs.OpenMode.READ_ONLY);
      try {
        const stat = fs.statSync(file.fd);
        const buffer = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buffer);

        let jsonData = utf8Decode(new Uint8Array(buffer));

        // 2. 解密数据（如果需要）
        if (backupFile.fileName.endsWith('.enc')) {
          if (!this.config.backupPassword) {
            throw new Error('Backup password required for encrypted backup');
          }
          jsonData = await this.decryptData(jsonData, this.config.backupPassword);
        }

        // 3. 解析JSON数据
        const backupData: BackupDataContent = JSON.parse(jsonData) as BackupDataContent;

        // 4. 验证数据格式
        if (!this.validateBackupData(backupData, backupFile.dataType)) {
          throw new Error('Invalid backup data format');
        }

        // 5. 恢复数据
        await this.restoreBackupData(backupData, backupFile.dataType);

        hilog.info(DOMAIN, TAG, 'Backup restored successfully: %{public}s', backupFile.fileName);
        return true;
      } finally {
        fs.closeSync(file.fd);
      }

    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to restore backup: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  // 选择备份文件
  async selectBackupFile(): Promise<BackupFileInfo | null> {
    try {
      const context = this.getContext();
      
      // 创建文件选择器
      const documentSelectOptions = new filePicker.DocumentSelectOptions();
      documentSelectOptions.fileSuffixFilters = ['.json', '.enc'];
      
      const documentPicker = new filePicker.DocumentViewPicker(context);
      
      // 打开文件选择器
      const uris: string[] = await documentPicker.select(documentSelectOptions);
      
      if (uris && uris.length > 0) {
        const fileUri: string = uris[0];
        
        // 获取文件信息
        const fileStat: fs.Stat = await fs.stat(fileUri);
        
        // 解析文件名获取备份信息
        const fileName: string = fileUri.split('/').pop() || 'unknown';
        const dataType: BackupDataType = this.parseDataTypeFromFileName(fileName);
        
        const fileInfo: BackupFileInfo = {
          fileName,
          filePath: fileUri,
          fileSize: fileStat.size,
          backupTime: fileStat.mtime * 1000, // mtime是Unix时间戳（秒），转换为毫秒
          dataType,
          version: '1.0.0'
        };
        
        return fileInfo;
      }
      
      return null;
      
    } catch (err) {
      const errorMsg: string = JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to select backup file: %{public}s', errorMsg);
      return null;
    }
  }

  // 获取备份列表
  async getBackupList(): Promise<BackupFileInfo[]> {
    try {
      await this.ensureBackupDirectoryExists();
      
      const backupFiles: BackupFileInfo[] = [];
      
      try {
        // 使用fs.listFile读取目录内容
        const entries: string[] = fs.listFileSync(this.config.backupLocation);
        for (let i = 0; i < entries.length; i++) {
          const fileName = entries[i];
          if (fileName.endsWith('.json') || fileName.endsWith('.enc')) {
            const filePath = `${this.config.backupLocation}/${fileName}`;
            const fileStat = await fs.stat(filePath);
            const dataType = this.parseDataTypeFromFileName(fileName);
            
            const fileInfo: BackupFileInfo = {
              fileName,
              filePath,
              fileSize: fileStat.size,
              backupTime: fileStat.mtime, // mtime is already a timestamp in milliseconds
              dataType,
              version: '1.0.0'
            };
            
            backupFiles.push(fileInfo);
          }
        }
      } catch (err) {
        const errMsg: string = err instanceof Error ? err.message : 'Unknown error';
        hilog.error(DOMAIN, TAG, 'Failed to list backup files: %{public}s', errMsg);
      }
      
      // 按备份时间排序（最新的在前）
      backupFiles.sort((a, b) => b.backupTime - a.backupTime);
      
      return backupFiles;
      
    } catch (err) {
      const errMsg: string = err instanceof Error ? err.message : 'Unknown error';
      hilog.error(DOMAIN, TAG, 'Failed to get backup list: %{public}s', errMsg);
      return [];
    }
  }

  // 删除备份
  async deleteBackup(backupFile: BackupFileInfo): Promise<boolean> {
    try {
      await fs.unlink(backupFile.filePath);
      hilog.info(DOMAIN, TAG, 'Backup deleted: %{public}s', backupFile.fileName);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to delete backup: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  // 开始自动备份
  startAutoBackup(): void {
    if (this.backupTimer) {
      clearInterval(this.backupTimer);
    }
    
    if (this.config.autoBackup && this.config.backupInterval > 0) {
      const intervalMs = this.config.backupInterval * 24 * 60 * 60 * 1000; // 转换为毫秒
      
      this.backupTimer = setInterval(() => {
        this.createBackup(BackupDataType.ALL).then(() => {
          hilog.info(DOMAIN, TAG, 'Auto backup completed successfully');
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'Auto backup failed: %{public}s', err.message);
        });
      }, intervalMs);
      
      hilog.info(DOMAIN, TAG, 'Auto backup started, interval: %{public}d days', this.config.backupInterval);
    }
  }

  // 停止自动备份
  stopAutoBackup(): void {
    if (this.backupTimer) {
      clearInterval(this.backupTimer);
      this.backupTimer = null;
      hilog.info(DOMAIN, TAG, 'Auto backup stopped');
    }
  }

  // 收集备份数据
  private async collectBackupData(dataType: BackupDataType): Promise<BackupDataContent> {
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
        backupData.data.playlists = await this.collectPlaylistData();
      }
      
      // 收集设置数据
      if (dataType === BackupDataType.ALL || dataType === BackupDataType.SETTINGS) {
        backupData.data.settings = await this.collectSettingsData();
      }
      
      // 收集下载数据
      if (dataType === BackupDataType.ALL || dataType === BackupDataType.DOWNLOADS) {
        backupData.data.downloads = await this.collectDownloadData();
      }
      
    } catch (err) {
      const errorMsg: string = err instanceof Error ? err.message : 'Unknown error';
      hilog.error(DOMAIN, TAG, 'Failed to collect backup data: %{public}s', errorMsg);
      throw new Error(`Failed to collect backup data: ${errorMsg}`);
    }
    
    return backupData;
  }

  // 收集歌单数据
  private async collectPlaylistData(): Promise<BackupPlaylistSnapshot[]> {
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
  private async collectSettingsData(): Promise<Record<string, Object>> {
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
  private async collectDownloadData(): Promise<BackupDownloadSnapshot[]> {
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

  /**
   * 生成备份文件名（唯一的文件名拼装处，避免创建/恢复两处规则漂移）
   * @param timestamp 调用方已算好的时间戳，保证同一次备份的名字一致
   */
  private generateBackupFileName(dataType: BackupDataType, timestamp: string): string {
    const extension = this.config.encryptBackup ? '.enc' : '.json';
    return `lxmusic-backup-${dataType}-${timestamp}${extension}`;
  }

  // 确保备份目录存在
  private async ensureBackupDirectoryExists(): Promise<void> {
    try {
      await fs.access(this.config.backupLocation);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'access backup directory failed: %{public}s', (e as Error)?.message);
      try {
        await fs.mkdir(this.config.backupLocation);
        hilog.info(DOMAIN, TAG, 'Created backup directory: %{public}s', this.config.backupLocation);
      } catch (me) {
        const msg = (me as Error)?.message || JSON.stringify(me);
        hilog.error(DOMAIN, TAG, 'mkdir backup directory failed: %{public}s', msg);
        throw new Error(`Cannot create backup directory: ${msg}`);
      }
    }
  }

  // 加密数据
  /** 备份载荷加密：实现在 service/crypto/AesPayload（随机 IV + SHA-256 派生密钥） */
  private async encryptData(data: string, password: string): Promise<string> {
    return encryptWithPassword(data, password);
  }

  // 解密数据
  /** 备份载荷解密：新格式走 AES；历史 XOR 备份仍可恢复（见 AesPayload） */
  private async decryptData(encryptedData: string, password: string): Promise<string> {
    return decryptWithPassword(encryptedData, password);
  }

  // 从密码派生密钥


  // 验证备份数据
  private validateBackupData(data: BackupDataContent, expectedDataType: BackupDataType): boolean {
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
  private async restoreBackupData(backupData: BackupDataContent, dataType: BackupDataType): Promise<void> {
    try {
      // 恢复歌单数据
      if (dataType === BackupDataType.ALL || dataType === BackupDataType.PLAYLISTS) {
        if (backupData.data && backupData.data.playlists) {
          await this.restorePlaylistData(backupData.data.playlists);
        }
      }
      
      // 恢复设置数据
      if (dataType === BackupDataType.ALL || dataType === BackupDataType.SETTINGS) {
        if (backupData.data && backupData.data.settings) {
          await this.restoreSettingsData(backupData.data.settings);
        }
      }
      
      // 恢复下载数据
      if (dataType === BackupDataType.ALL || dataType === BackupDataType.DOWNLOADS) {
        if (backupData.data && backupData.data.downloads) {
          await this.restoreDownloadData(backupData.data.downloads);
        }
      }
      
    } catch (err) {
      const errorMsg: string = err instanceof Error ? err.message : 'Unknown error';
      hilog.error(DOMAIN, TAG, 'Failed to restore backup data: %{public}s', errorMsg);
      throw new Error(`Failed to restore backup data: ${errorMsg}`);
    }
  }

  // 恢复歌单数据
  private async restorePlaylistData(playlists: BackupPlaylistSnapshot[]): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, 'Restoring playlist data, count: %{public}d', playlists.length);

      for (const playlist of playlists) {
        const listName = playlist.name || '未知歌单';
        const songs = playlist.musicList || [];
        hilog.info(DOMAIN, TAG, 'Restoring playlist: %{public}s (%{public}d songs)', listName, songs.length);

        if (playlist.id === LIST_IDS.DEFAULT) {
          // 恢复到默认列表
          for (let i = 0; i < songs.length; i++) {
            await addMusicToList(LIST_IDS.DEFAULT, musicItemFromPlainObject(songs[i]));
          }
        } else if (playlist.id === LIST_IDS.LOVE) {
          // 恢复到我喜欢的列表
          for (let i = 0; i < songs.length; i++) {
            await addMusicToList(LIST_IDS.LOVE, musicItemFromPlainObject(songs[i]));
          }
        } else {
          // 用户自定义歌单
          const newList = await createUserList(listName);
          for (let i = 0; i < songs.length; i++) {
            await addMusicToList(newList.id, musicItemFromPlainObject(songs[i]));
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
  private async restoreSettingsData(settings: Record<string, Object>): Promise<void> {
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
  private async restoreDownloadData(downloads: BackupDownloadSnapshot[]): Promise<void> {
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

  // 从文件名解析数据类型
  private parseDataTypeFromFileName(fileName: string): BackupDataType {
    if (fileName.includes('-all-')) return BackupDataType.ALL;
    if (fileName.includes('-playlists-')) return BackupDataType.PLAYLISTS;
    if (fileName.includes('-settings-')) return BackupDataType.SETTINGS;
    if (fileName.includes('-downloads-')) return BackupDataType.DOWNLOADS;
    return BackupDataType.ALL;
  }

  // ArrayBuffer转Base64
  // （旧 XOR 备份的 arrayBufferToBase64 已随加解密迁移到 AesPayload 移除）

  // Base64转ArrayBuffer
  // （旧 XOR 备份的 base64ToArrayBuffer 已随加解密迁移到 AesPayload 移除）

  // Base64编码 - 修复: 不使用索引访问
  private btoa(input: string): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result = '';
    let i = 0;
    while (i < input.length) {
      const a = input.charCodeAt(i++);
      const b = i < input.length ? input.charCodeAt(i++) : 0;
      const c = i < input.length ? input.charCodeAt(i++) : 0;
      const triplet = (a << 16) | (b << 8) | c;
      result += chars.charAt((triplet >> 18) & 0x3F) +
                chars.charAt((triplet >> 12) & 0x3F) +
                (i > input.length + 1 ? '=' : chars.charAt((triplet >> 6) & 0x3F)) +
                (i > input.length ? '=' : chars.charAt(triplet & 0x3F));
    }
    return result;
  }

  // Base64解码 - 修复: 不使用索引访问
  private atob(input: string): string {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result = '';
    const cleanInput = input.replace(/=+$/, '');
    let i = 0;
    while (i < cleanInput.length) {
      const a = chars.indexOf(cleanInput.charAt(i++));
      const b = chars.indexOf(cleanInput.charAt(i++));
      const c = chars.indexOf(cleanInput.charAt(i++));
      const d = chars.indexOf(cleanInput.charAt(i++));
      const triplet = (a << 18) | (b << 12) | (c << 6) | d;
      result += String.fromCharCode((triplet >> 16) & 0xFF) +
                String.fromCharCode((triplet >> 8) & 0xFF) +
                String.fromCharCode(triplet & 0xFF);
    }
    return result;
  }

  // 获取上下文
  private getContext(): common.UIAbilityContext {
    if (!this.abilityContext) {
      throw new Error('UIAbilityContext not set. Call setContext first.');
    }
    return this.abilityContext;
  }

  // 设置上下文
  setContext(context: common.UIAbilityContext): void {
    this.abilityContext = context;
  }
}

// 导出单例
export const backupService = BackupService.getInstance();
