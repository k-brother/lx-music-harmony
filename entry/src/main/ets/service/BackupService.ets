// 备份与恢复服务
// 对应安卓版的备份恢复功能
//
// 配置归属：备份/WebDAV 的非敏感字段（开关、间隔、目录、加密、目标地址与账号）
// 统一存进设置存储（service/SettingsService），口令只进资产存储（service/CredentialStore）。
// 本服务因此不再直接使用 preferences —— 设置只有一个写入方，也别在这里开第二条链。

import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { picker as filePicker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { encryptWithPassword, decryptWithPassword } from './crypto/AesPayload';
import { utf8Decode } from '../utils/TextCodec';
import { settingsService } from './SettingsService';
import type { AppSettings } from './SettingsService';
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
  /** 备份目录；空串 = 应用沙箱 filesDir（见 BackupService.backupDir） */
  backupLocation: string;
  encryptBackup: boolean;
  backupPassword?: string;
  // WebDAV 备份目标（留空即不启用）
  webdavUrl: string;
  webdavUser: string;
  webdavPassword: string;
}



// 备份服务类
export class BackupService {
  private static instance: BackupService;
  /**
   * 口令缓存。
   *
   * 为什么不跟其它字段一样现读：口令不在设置里，而 `getConfig()` 是同步接口、
   * 设置页要拿它回显表单，所以只能在 `initialize()` 里读进内存（来源是资产存储，
   * 见 service/CredentialStore）。**非敏感字段一律不缓存**，每次从 SettingsService
   * 现读 —— 否则「恢复备份 / 恢复默认设置」改过设置之后，这里会一直显示旧值。
   */
  private backupPassword: string = '';
  private webdavPassword: string = '';

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

  /**
   * 初始化：读口令 + 按「自动备份」开关启动定时器。
   * 幂等，可重复调用（设置页进入时也会调一次，保证冷启动后立刻生效）。
   */
  async initialize(): Promise<void> {
    try {
      this.backupPassword = await readSecret(CREDENTIAL_BACKUP_PASSWORD);
      this.webdavPassword = await readSecret(CREDENTIAL_WEBDAV_PASSWORD);

      if (this.settings().autoBackup) {
        this.startAutoBackup();
      }

      hilog.info(DOMAIN, TAG, 'Backup service initialized');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to initialize backup service: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 备份配置的权威来源。
   * 备份/WebDAV 的非敏感字段自 B15b 起并入设置存储（StorageKeys.BACKUP_*），
   * 旧版本写在旁路实例 backup_config 里的值由 SettingsStorage 一次性迁移过来，
   * 因此这里只需要现读，不需要再维护一份缓存。
   */
  private settings(): AppSettings {
    return settingsService.get();
  }

  /** 备份目录：设置里留空时落到应用沙箱 filesDir */
  private backupDir(): string {
    const configured: string = this.settings().backupLocation;
    return configured.length > 0 ? configured : this.getContext().filesDir;
  }

  // 获取配置
  getConfig(): BackupConfig {
    const settings = this.settings();
    const result: BackupConfig = {
      autoBackup: settings.autoBackup,
      backupInterval: settings.backupInterval,
      backupLocation: settings.backupLocation,
      encryptBackup: settings.encryptBackup,
      webdavUrl: settings.webdavUrl,
      webdavUser: settings.webdavUser,
      webdavPassword: ''
    };
    if (this.backupPassword) {
      result.backupPassword = this.backupPassword;
    }
    // 密码只在已设置时回传（编辑表单回显用），调用方不应把它打到日志里
    if (this.webdavPassword) {
      result.webdavPassword = this.webdavPassword;
    }
    return result;
  }

  /**
   * 更新配置。
   * 非敏感字段统一交给 SettingsService（设置只有一个写入方）；
   * 口令只写资产存储，既不落偏好文件，也不会被设置快照/备份包带出去。
   */
  async updateConfig(newConfig: Partial<BackupConfig>): Promise<void> {
    const current = this.settings();

    // 地址在这里提前规范化，让设置页能就地报错，而不是等第一次备份才失败
    let webdavUrl: string = current.webdavUrl;
    if (newConfig.webdavUrl !== undefined) {
      const raw: string = newConfig.webdavUrl.trim();
      webdavUrl = raw.length > 0 ? normalizeWebDavUrl(raw) : '';
    }

    await settingsService.update({
      autoBackup: newConfig.autoBackup !== undefined ? newConfig.autoBackup : current.autoBackup,
      backupInterval: newConfig.backupInterval !== undefined
        ? newConfig.backupInterval : current.backupInterval,
      backupLocation: newConfig.backupLocation !== undefined
        ? newConfig.backupLocation : current.backupLocation,
      encryptBackup: newConfig.encryptBackup !== undefined
        ? newConfig.encryptBackup : current.encryptBackup,
      webdavUrl,
      webdavUser: newConfig.webdavUser !== undefined ? newConfig.webdavUser : current.webdavUser,
    });

    if (newConfig.backupPassword !== undefined) {
      this.backupPassword = newConfig.backupPassword;
      await saveSecret(CREDENTIAL_BACKUP_PASSWORD, this.backupPassword);
    }
    if (newConfig.webdavPassword !== undefined) {
      this.webdavPassword = newConfig.webdavPassword;
      await saveSecret(CREDENTIAL_WEBDAV_PASSWORD, this.webdavPassword);
    }

    // 重新启动自动备份
    if (this.backupTimer) {
      clearInterval(this.backupTimer);
      this.backupTimer = null;
    }

    if (this.settings().autoBackup) {
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
      const encrypt: boolean = this.settings().encryptBackup;
      if (encrypt && this.backupPassword.length > 0) {
        finalData = await this.encryptData(jsonData, this.backupPassword);
      }
      
      // 4. 确保备份目录存在
      await this.ensureBackupDirectoryExists();
      
      // 5. 生成文件名
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      const fileName = this.generateBackupFileName(dataType, timestamp, encrypt);
      const filePath = `${this.backupDir()}/${fileName}`;
      
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
      if (this.backupPassword.length === 0) {
        throw new Error('Backup password required for encrypted backup');
      }
      plain = await this.decryptData(jsonData, this.backupPassword);
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

      const dir: string = this.backupDir();
      const backupFiles: BackupFileInfo[] = [];
      
      try {
        // 使用fs.listFile读取目录内容
        const entries: string[] = fs.listFileSync(dir);
        for (let i = 0; i < entries.length; i++) {
          const fileName = entries[i];
          if (fileName.endsWith('.json') || fileName.endsWith('.enc')) {
            const filePath = `${dir}/${fileName}`;
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
    const settings = this.settings();
    return settings.webdavUrl.trim().length > 0 && settings.webdavUser.trim().length > 0;
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
    const settings = this.settings();
    return {
      url: settings.webdavUrl,
      user: settings.webdavUser,
      password: this.webdavPassword
    };
  }

  // 开始自动备份
  startAutoBackup(): void {
    if (this.backupTimer) {
      clearInterval(this.backupTimer);
    }

    const settings = this.settings();
    if (settings.autoBackup && settings.backupInterval > 0) {
      const intervalMs = settings.backupInterval * 24 * 60 * 60 * 1000; // 转换为毫秒
      
      this.backupTimer = setInterval(() => {
        this.createBackup(BackupDataType.ALL).then(() => {
          hilog.info(DOMAIN, TAG, 'Auto backup completed successfully');
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'Auto backup failed: %{public}s', err.message);
        });
      }, intervalMs);
      
      hilog.info(DOMAIN, TAG, 'Auto backup started, interval: %{public}d days', settings.backupInterval);
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
   * @param encrypt 本次备份是否加密（决定扩展名；由调用方读一次设置传进来，避免重复读设置）
   */
  private generateBackupFileName(dataType: BackupDataType, timestamp: string, encrypt: boolean): string {
    const extension = encrypt ? '.enc' : '.json';
    return `lxmusic-backup-${dataType}-${timestamp}${extension}`;
  }

  // 确保备份目录存在
  private async ensureBackupDirectoryExists(): Promise<void> {
    const dir: string = this.backupDir();
    try {
      await fs.access(dir);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'access backup directory failed: %{public}s', (e as Error)?.message);
      try {
        await fs.mkdir(dir);
        hilog.info(DOMAIN, TAG, 'Created backup directory: %{public}s', dir);
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
