// 备份与恢复服务
// 对应安卓版的备份恢复功能

import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { picker as filePicker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { encryptWithPassword, decryptWithPassword } from './crypto/AesPayload';
import { utf8Decode } from '../utils/TextCodec';
import {
  readSecret,
  saveSecret,
  CREDENTIAL_BACKUP_PASSWORD,
  CREDENTIAL_WEBDAV_PASSWORD,
} from './CredentialStore';
import {
  normalizeWebDavUrl,
  webDavDelete,
  webDavDownload,
  webDavList,
  webDavUpload,
  type WebDavEntry,
  type WebDavTarget,
} from '../core/network/webdav/WebDavClient';
import {
  collectBackupData,
  restoreBackupData,
  validateBackupData,
} from './backup/BackupDataMapping';
import { BackupDataType } from './backup/BackupTypes';
import type { BackupDataContent, BackupFileInfo } from './backup/BackupTypes';

// 类型对外仍从本模块导出（调用方 import 路径不变）
export { BackupDataType };
export type { BackupFileInfo };

const DOMAIN: number = 0x0001;
const TAG: string = 'BackupService';

// 备份配置
export interface BackupConfig {
  autoBackup: boolean;
  backupInterval: number; // 天数
  backupLocation: string;
  encryptBackup: boolean;
  backupPassword?: string;
  // WebDAV 备份目标（留空即不启用；配置跟其它备份配置同一个 preferences，不重复建链）
  webdavUrl: string;
  webdavUser: string;
  webdavPassword: string;
}



// 备份服务类
export class BackupService {
  private static instance: BackupService;
  private config: BackupConfig = {
    autoBackup: false,
    backupInterval: 7,
    backupLocation: '',
    encryptBackup: false,
    webdavUrl: '',
    webdavUser: '',
    webdavPassword: ''
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
      this.config.webdavUrl = await pref.get('webdavUrl', '') as string;
      this.config.webdavUser = await pref.get('webdavUser', '') as string;

      // 口令走系统资产存储；同时把历史上写在 preferences 里的明文迁移过去并清除
      this.config.backupPassword = await this.loadPassword(pref, 'backupPassword', CREDENTIAL_BACKUP_PASSWORD);
      this.config.webdavPassword = await this.loadPassword(pref, 'webdavPassword', CREDENTIAL_WEBDAV_PASSWORD);

      hilog.info(DOMAIN, TAG, 'Backup config loaded');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to load backup config: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 读口令：优先资产存储；若资产存储里没有、而旧 preferences 里还留着明文，
   * 则迁移到资产存储并删除明文键（一次性的兼容处理，之后 preferences 不再持有口令）。
   */
  private async loadPassword(pref: preferences.Preferences, legacyKey: string,
    alias: string): Promise<string> {
    const stored: string = await readSecret(alias);
    if (stored.length > 0) {
      // 资产存储已就绪：顺手清掉可能残留的明文
      if (await pref.has(legacyKey)) {
        await pref.delete(legacyKey);
        await pref.flush();
      }
      return stored;
    }
    const legacy: string = await pref.get(legacyKey, '') as string;
    if (legacy.length === 0) {
      return '';
    }
    await saveSecret(alias, legacy);
    await pref.delete(legacyKey);
    await pref.flush();
    hilog.info(DOMAIN, TAG, 'migrated %{public}s from preferences to AssetStore', legacyKey);
    return legacy;
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
      await pref.put('webdavUrl', this.config.webdavUrl);
      await pref.put('webdavUser', this.config.webdavUser);

      // 口令只进资产存储，不进明文偏好文件（历史明文键一并清掉）
      await saveSecret(CREDENTIAL_BACKUP_PASSWORD, this.config.backupPassword ?? '');
      await saveSecret(CREDENTIAL_WEBDAV_PASSWORD, this.config.webdavPassword);
      for (const legacyKey of ['backupPassword', 'webdavPassword']) {
        if (await pref.has(legacyKey)) {
          await pref.delete(legacyKey);
        }
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
      encryptBackup: this.config.encryptBackup,
      webdavUrl: this.config.webdavUrl,
      webdavUser: this.config.webdavUser,
      webdavPassword: ''
    };
    if (this.config.backupPassword) {
      result.backupPassword = this.config.backupPassword;
    }
    // 密码只在已设置时回传（编辑表单回显用），调用方不应把它打到日志里
    if (this.config.webdavPassword) {
      result.webdavPassword = this.config.webdavPassword;
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
    if (newConfig.webdavUrl !== undefined) {
      // 提前校验格式，让设置页能就地报错，而不是等第一次备份才失败
      this.config.webdavUrl = newConfig.webdavUrl.trim().length > 0
        ? normalizeWebDavUrl(newConfig.webdavUrl) : '';
    }
    if (newConfig.webdavUser !== undefined) {
      this.config.webdavUser = newConfig.webdavUser.trim();
    }
    if (newConfig.webdavPassword !== undefined) {
      this.config.webdavPassword = newConfig.webdavPassword;
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
      const backupData = await collectBackupData(dataType);
      
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

      // 配置了 WebDAV 就顺手同步上传；失败不丢本地备份，只把结果标给调用方提示
      if (this.isWebDavConfigured()) {
        fileInfo.remoteUploaded = await this.uploadBackupToWebDav(fileInfo);
        if (!fileInfo.remoteUploaded) {
          hilog.warn(DOMAIN, TAG, 'WebDAV upload failed, local backup kept: %{public}s', fileName);
        }
      }

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
        const jsonData = utf8Decode(new Uint8Array(buffer));
        return await this.restoreFromText(jsonData, backupFile.fileName, backupFile.dataType);
      } finally {
        fs.closeSync(file.fd);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to restore backup: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * 从文本内容恢复（本地文件与 WebDAV 下载共用后半段：解密 → 校验 → 落数据）。
   * 文件名用于识别 .enc 加密备份与 dataType。
   */
  private async restoreFromText(jsonData: string, fileName: string, dataType: BackupDataType): Promise<boolean> {
    let plain = jsonData;
    // 解密数据（如果需要）
    if (fileName.endsWith('.enc')) {
      if (!this.config.backupPassword) {
        throw new Error('Backup password required for encrypted backup');
      }
      plain = await this.decryptData(jsonData, this.config.backupPassword);
    }

    // 解析JSON数据
    const backupData: BackupDataContent = JSON.parse(plain) as BackupDataContent;

    // 验证数据格式
    if (!validateBackupData(backupData, dataType)) {
      throw new Error('Invalid backup data format');
    }

    // 恢复数据
    await restoreBackupData(backupData, dataType);
    hilog.info(DOMAIN, TAG, 'Backup restored successfully: %{public}s', fileName);
    return true;
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

  // ------------------------------------------------------------ WebDAV

  /** WebDAV 目标是否已配置完整（地址 + 用户名；密码允许为空） */
  isWebDavConfigured(): boolean {
    return this.config.webdavUrl.trim().length > 0 && this.config.webdavUser.trim().length > 0;
  }

  /** 把已生成的本地备份上传到 WebDAV（读取文件 → 上传；失败返回 false 不抛错） */
  async uploadBackupToWebDav(fileInfo: BackupFileInfo): Promise<boolean> {
    try {
      const file = fs.openSync(fileInfo.filePath, fs.OpenMode.READ_ONLY);
      let content: string;
      try {
        const stat = fs.statSync(file.fd);
        const buffer = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buffer);
        content = utf8Decode(new Uint8Array(buffer));
      } finally {
        fs.closeSync(file.fd);
      }
      await webDavUpload(this.webDavTarget(), fileInfo.fileName, content);
      hilog.info(DOMAIN, TAG, 'Backup uploaded to WebDAV: %{public}s', fileInfo.fileName);
      return true;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'WebDAV upload failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      return false;
    }
  }

  /** 列出 WebDAV 上的本应用备份（按修改时间倒序；filePath 为空表示远端条目） */
  async listWebDavBackups(): Promise<BackupFileInfo[]> {
    const entries: WebDavEntry[] = await webDavList(this.webDavTarget());
    const out: BackupFileInfo[] = [];
    for (let i: number = 0; i < entries.length; i++) {
      const name: string = entries[i].name;
      if (!name.startsWith('lxmusic-backup-')) {
        continue;
      }
      out.push({
        fileName: name,
        filePath: '',
        fileSize: entries[i].size,
        backupTime: entries[i].modifiedMs > 0 ? entries[i].modifiedMs : 0,
        dataType: this.parseDataTypeFromFileName(name),
        version: '1.0.0'
      });
    }
    out.sort((a: BackupFileInfo, b: BackupFileInfo): number => b.backupTime - a.backupTime);
    return out;
  }

  /** 从 WebDAV 恢复备份（下载 → 与本地恢复共用后半段） */
  async restoreWebDavBackup(fileName: string, dataType: BackupDataType): Promise<boolean> {
    try {
      const text: string = await webDavDownload(this.webDavTarget(), fileName);
      return await this.restoreFromText(text, fileName, dataType);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to restore WebDAV backup: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      return false;
    }
  }

  /** 删除 WebDAV 上的备份 */
  async deleteWebDavBackup(fileName: string): Promise<boolean> {
    try {
      await webDavDelete(this.webDavTarget(), fileName);
      hilog.info(DOMAIN, TAG, 'WebDAV backup deleted: %{public}s', fileName);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to delete WebDAV backup: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      return false;
    }
  }

  /** 组装 WebDAV 连接目标（未配置时抛错，调用前先过 isWebDavConfigured） */
  private webDavTarget(): WebDavTarget {
    if (!this.isWebDavConfigured()) {
      throw new Error('WebDAV not configured');
    }
    return {
      url: this.config.webdavUrl,
      user: this.config.webdavUser,
      password: this.config.webdavPassword
    };
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







  // 从文件名解析数据类型
  private parseDataTypeFromFileName(fileName: string): BackupDataType {
    if (fileName.includes('-all-')) return BackupDataType.ALL;
    if (fileName.includes('-playlists-')) return BackupDataType.PLAYLISTS;
    if (fileName.includes('-settings-')) return BackupDataType.SETTINGS;
    if (fileName.includes('-downloads-')) return BackupDataType.DOWNLOADS;
    return BackupDataType.ALL;
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
