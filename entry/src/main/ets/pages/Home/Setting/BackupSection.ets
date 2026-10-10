/**
 * 设置 → 备份与恢复
 *
 * 备份/恢复走 BackupService（整包数据），导入/导出歌单走 PlaylistTransferService（JSON）。
 * 本组件只负责：文件选择器、确认、提示、恢复后重载列表数据。
 */
import { common } from '@kit.AbilityKit';
import { picker as filePicker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { t, tf } from '../../../service/LocalizationService';
import { appActionMenu, appConfirmSystem, appToast } from '../../../service/DialogService';
import { backupService, BackupDataType } from '../../../service/BackupService';
import type { BackupFileInfo } from '../../../service/BackupService';
import { initListService } from '../../../service/ListService';
import {
  buildPlaylistsExport,
  importPlaylistsPayload,
  isValidPlaylistsExport,
  readPlaylistsFromUri,
  writePlaylistsToUri,
} from '../../../service/PlaylistTransferService';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import type { SettingSectionItem } from '../../../components/ui/SettingsTypes';
import { WebDavSheet } from './WebDavSheet';
import { normalizeWebDavUrl } from '../../../core/network/webdav/WebDavClient';

const DOMAIN = 0x0001;
const TAG = 'BackupSection';

@Component
export struct BackupSection {
  /** 自动备份开关与间隔（天） */
  @State autoBackup: boolean = false;
  @State backupInterval: number = 7;
  /** 应用目录里的备份个数（用于「本地备份」行的说明） */
  @State localBackupCount: number = 0;
  /** WebDAV 配置状态（用于设置行说明与「WebDAV 上的备份」行显隐） */
  @State webdavConfigured: boolean = false;
  @State showWebDavSheet: boolean = false;

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  aboutToAppear(): void {
    void this.loadConfig();
    void this.refreshBackupCount();
  }

  /**
   * 读取备份配置。
   * 先跑一遍服务初始化（幂等：读口令 + 按开关起定时器），保证冷启动后直接进设置页
   * 也能看到真实开关而不是默认值；配置本体每次都是从 SettingsService 现读的。
   */
  private async loadConfig(): Promise<void> {
    backupService.setContext(this.hostContext());
    try {
      await backupService.initialize();
    } catch (err) {
      hilog.warn(0x0001, 'BackupSection', 'initialize failed: %{public}s', JSON.stringify(err));
    }
    const config = backupService.getConfig();
    this.autoBackup = config.autoBackup;
    this.backupInterval = config.backupInterval;
    this.webdavConfigured = backupService.isWebDavConfigured();
  }

  private async refreshBackupCount(): Promise<void> {
    backupService.setContext(this.hostContext());
    const list = await backupService.getBackupList();
    this.localBackupCount = list.length;
  }

  /** 整包备份 */
  private async backupData(): Promise<void> {
    try {
      appToast(t('toast_backup_running'));
      backupService.setContext(this.hostContext());
      const file = await backupService.createBackup(BackupDataType.ALL);
      if (!file) {
        appToast(t('toast_backup_fail'));
      } else if (backupService.isWebDavConfigured()) {
        // 配置了 WebDAV：创建时已顺带上传，这里区分三种结局给用户明确反馈
        hilog.info(DOMAIN, TAG, 'Backup created: %{public}s', file.fileName);
        appToast(file.remoteUploaded === true
          ? t('toast_backup_success_remote')
          : t('toast_backup_local_only'));
        this.localBackupCount++;
      } else {
        hilog.info(DOMAIN, TAG, 'Backup created: %{public}s', file.fileName);
        appToast(t('toast_backup_success'));
        this.localBackupCount++;
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'backupData failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_backup_fail'));
    }
  }

  /** 从备份文件恢复 */
  private async restoreData(): Promise<void> {
    try {
      appToast(t('toast_restore_running'));
      backupService.setContext(this.hostContext());
      const file = await backupService.selectBackupFile();
      if (!file) {
        appToast(t('toast_restore_cancel'));
        return;
      }
      // 确认 / 恢复 / 重载的收尾与「本地备份」路径共用同一实现
      await this.applyRestore(file);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'restoreData failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_restore_fail'));
    }
  }

  /** 导出全部歌单为 JSON */
  private async exportPlaylists(): Promise<void> {
    try {
      appToast(t('toast_export_running'));
      const picker = new filePicker.DocumentViewPicker(this.hostContext());
      const options = new filePicker.DocumentSaveOptions();
      const fileName = `lxmusic-playlists-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
      options.newFileNames = [fileName];
      const uris = await picker.save(options);
      if (!uris || uris.length === 0) {
        appToast(t('toast_export_cancel'));
        return;
      }
      const ok = writePlaylistsToUri(uris[0], buildPlaylistsExport());
      appToast(ok ? `${t('toast_export_success')}: ${fileName}` : t('toast_export_fail'));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'exportPlaylists failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_export_fail'));
    }
  }

  /** 从 JSON 导入歌单 */
  private async importPlaylists(): Promise<void> {
    try {
      appToast(t('toast_import_running'));
      const picker = new filePicker.DocumentViewPicker(this.hostContext());
      const uris = await picker.select(new filePicker.DocumentSelectOptions());
      if (!uris || uris.length === 0) {
        appToast(t('toast_import_cancel'));
        return;
      }
      const payload = readPlaylistsFromUri(uris[0]);
      if (!payload || !isValidPlaylistsExport(payload)) {
        appToast(t('toast_format_invalid'));
        return;
      }
      const count = await importPlaylistsPayload(payload);
      await initListService();
      appToast(tf('toast_import_count', [count.toString()]));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'importPlaylists failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_import_fail'));
    }
  }

  /**
   * 本地备份列表：列出应用目录里的备份，选中后可恢复或删除。
   *
   * 「备份数据」写的是应用沙箱目录（backupLocation 默认 filesDir），此前没有任何入口
   * 能看到这些文件 —— 用户备份完就等于找不到了，只能靠系统文件选择器碰运气。
   */
  private async openBackupList(): Promise<void> {
    await this.refreshBackupCount();
    const list = await backupService.getBackupList();
    if (list.length === 0) {
      appToast(t('backup_list_empty'));
      return;
    }
    // 新的排在前面：备份时间倒序
    list.sort((a: BackupFileInfo, b: BackupFileInfo): number => b.backupTime - a.backupTime);
    const labels: string[] = [];
    for (let i = 0; i < list.length; i++) {
      labels.push(this.describeBackup(list[i]));
    }
    const picked = await appActionMenu(t('settings_backup_list'), labels);
    if (picked < 0 || picked >= list.length) {
      return;
    }
    const target = list[picked];
    const action = await appActionMenu(target.fileName, [
      t('settings_backup_restore'),
      t('settings_backup_delete'),
    ], { dangerIndexes: [1] });
    if (action === 0) {
      await this.restoreFromList(target);
    } else if (action === 1) {
      await this.deleteFromList(target);
    }
  }

  /** 备份行的展示文案：时间 · 类型 · 大小（远端没返回修改时间时退回文件名） */
  private describeBackup(file: BackupFileInfo): string {
    const sizeKb = Math.max(1, Math.round(file.fileSize / 1024));
    if (file.backupTime <= 0) {
      return `${file.fileName} · ${sizeKb} KB`;
    }
    const when = new Date(file.backupTime).toLocaleString();
    return `${when} · ${sizeKb} KB`;
  }

  /**
   * 执行恢复（确认 → 恢复 → 重载列表数据）。
   *
   * 「从文件恢复」与「从本地备份恢复」两条路径的收尾完全一样，抽成一处：
   * 恢复后必须重新加载列表，否则界面还是旧数据。
   * @returns 是否真的恢复了
   */
  private async applyRestore(file: BackupFileInfo): Promise<boolean> {
    const confirmed = await appConfirmSystem(
      t('restore_confirm_title'),
      tf('confirm_restore_backup', [file.fileName]),
      { danger: true });
    if (!confirmed) {
      appToast(t('toast_restore_cancel'));
      return false;
    }
    const ok = await backupService.restoreBackup(file);
    if (!ok) {
      appToast(t('toast_restore_fail'));
      return false;
    }
    appToast(t('toast_restore_success'));
    await initListService();
    hilog.info(DOMAIN, TAG, 'App data reloaded after restore: %{public}s', file.fileName);
    return true;
  }

  private async restoreFromList(file: BackupFileInfo): Promise<void> {
    await this.applyRestore(file);
  }

  private async deleteFromList(file: BackupFileInfo): Promise<void> {
    const confirmed = await appConfirmSystem(
      t('settings_backup_delete'),
      tf('confirm_delete_backup', [file.fileName]),
      { danger: true });
    if (!confirmed) {
      return;
    }
    const ok = await backupService.deleteBackup(file);
    appToast(ok ? t('toast_backup_deleted') : t('toast_operation_failed'));
    await this.refreshBackupCount();
  }

  // ------------------------------------------------------------ WebDAV

  /** 保存 WebDAV 配置（格式不合法时面板保持打开并提示） */
  private async saveWebDav(url: string, user: string, password: string): Promise<void> {
    if (url.length > 0) {
      try {
        normalizeWebDavUrl(url);
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'invalid webdav url: %{public}s',
          e instanceof Error ? e.message : JSON.stringify(e));
        appToast(t('webdav_url_invalid'));
        return;
      }
    }
    await backupService.updateConfig({ webdavUrl: url, webdavUser: user, webdavPassword: password });
    this.webdavConfigured = backupService.isWebDavConfigured();
    this.showWebDavSheet = false;
    appToast(t('webdav_saved'));
  }

  /** 清除 WebDAV 配置（面板里的危险操作，配置项少不再二次确认） */
  private async clearWebDav(): Promise<void> {
    await backupService.updateConfig({ webdavUrl: '', webdavUser: '', webdavPassword: '' });
    this.webdavConfigured = false;
    appToast(t('webdav_saved'));
  }

  /** WebDAV 上的备份列表：列出 → 选中后可恢复或删除（交互对齐本地备份列表） */
  private async openWebDavList(): Promise<void> {
    let list: BackupFileInfo[] = [];
    try {
      list = await backupService.listWebDavBackups();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'listWebDavBackups failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_webdav_fail'));
      return;
    }
    if (list.length === 0) {
      appToast(t('backup_list_webdav_empty'));
      return;
    }
    const labels: string[] = [];
    for (let i: number = 0; i < list.length; i++) {
      labels.push(this.describeBackup(list[i]));
    }
    const picked = await appActionMenu(t('settings_webdav_backups'), labels);
    if (picked < 0 || picked >= list.length) {
      return;
    }
    const target = list[picked];
    const action = await appActionMenu(target.fileName, [
      t('settings_backup_restore'),
      t('settings_backup_delete'),
    ], { dangerIndexes: [1] });
    if (action === 0) {
      await this.restoreFromWebDav(target);
    } else if (action === 1) {
      await this.deleteFromWebDav(target);
    }
  }

  /** 从 WebDAV 恢复（确认 → 下载并恢复 → 重载列表数据） */
  private async restoreFromWebDav(file: BackupFileInfo): Promise<void> {
    const confirmed = await appConfirmSystem(
      t('restore_confirm_title'),
      tf('confirm_restore_backup', [file.fileName]),
      { danger: true });
    if (!confirmed) {
      appToast(t('toast_restore_cancel'));
      return;
    }
    appToast(t('toast_restore_running'));
    const ok = await backupService.restoreWebDavBackup(file.fileName, file.dataType);
    if (!ok) {
      appToast(t('toast_restore_fail'));
      return;
    }
    appToast(t('toast_restore_success'));
    await initListService();
    hilog.info(DOMAIN, TAG, 'App data reloaded after WebDAV restore: %{public}s', file.fileName);
  }

  private async deleteFromWebDav(file: BackupFileInfo): Promise<void> {
    const confirmed = await appConfirmSystem(
      t('settings_backup_delete'),
      tf('confirm_delete_backup', [file.fileName]),
      { danger: true });
    if (!confirmed) {
      return;
    }
    const ok = await backupService.deleteWebDavBackup(file.fileName);
    appToast(ok ? t('toast_backup_deleted') : t('toast_webdav_fail'));
  }

  /** 自动备份开关：写配置并启停计时器 */
  private toggleAutoBackup(enabled: boolean): void {
    this.autoBackup = enabled;
    void backupService.updateConfig({ autoBackup: enabled });
    if (enabled) {
      backupService.startAutoBackup();
    } else {
      backupService.stopAutoBackup();
    }
  }

  /** 备份间隔（天）：写配置后立即重新计时 */
  private applyBackupInterval(value: string): void {
    const days = parseInt(value);
    if (isNaN(days) || days < 1 || days > 365) {
      appToast(t('settings_backup_interval_desc'));
      return;
    }
    this.backupInterval = days;
    void backupService.updateConfig({ backupInterval: days }).then((): void => {
      if (this.autoBackup) {
        backupService.startAutoBackup();
      }
    });
    appToast(`${t('settings_backup_interval')}: ${days}`);
  }

  private buildItems(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];

    items.push({
      type: 'button',
      title: t('settings_backup_data'),
      description: t('settings_backup_data_desc'),
      onClick: (): void => {
        void this.backupData();
      },
    });
    items.push({
      type: 'button',
      title: t('settings_restore_data'),
      description: t('settings_restore_data_desc'),
      onClick: (): void => {
        void this.restoreData();
      },
    });
    // 应用目录里的备份清单（此前备份出来就再也找不到）
    items.push({
      type: 'button',
      title: t('settings_backup_list'),
      description: this.localBackupCount > 0
        ? tf('settings_backup_count', [this.localBackupCount.toString()])
        : t('backup_list_empty'),
      onClick: (): void => {
        void this.openBackupList();
      },
    });
    // WebDAV：配置行 + 配置后的远端备份清单
    items.push({
      type: 'button',
      title: t('settings_webdav'),
      description: this.webdavConfigured ? t('settings_webdav_on') : t('settings_webdav_desc'),
      onClick: (): void => {
        this.showWebDavSheet = true;
      },
    });
    if (this.webdavConfigured) {
      items.push({
        type: 'button',
        title: t('settings_webdav_backups'),
        description: t('settings_webdav_backups_desc'),
        onClick: (): void => {
          void this.openWebDavList();
        },
      });
    }
    items.push({
      type: 'toggle',
      title: t('settings_backup_auto'),
      description: t('settings_backup_auto_desc'),
      value: this.autoBackup,
      onChangeToggle: (value: boolean): void => {
        this.toggleAutoBackup(value);
      },
    });
    if (this.autoBackup) {
      items.push({
        type: 'input',
        title: t('settings_backup_interval'),
        description: t('settings_backup_interval_desc'),
        value: this.backupInterval.toString(),
        onChange: (value: string): void => {
          this.applyBackupInterval(value);
        },
      });
    }
    items.push({
      type: 'button',
      title: t('settings_export_list'),
      description: t('settings_export_list_desc'),
      onClick: (): void => {
        void this.exportPlaylists();
      },
    });
    items.push({
      type: 'button',
      title: t('settings_import_list'),
      description: t('settings_import_list_desc'),
      onClick: (): void => {
        void this.importPlaylists();
      },
    });

    return items;
  }

  build() {
    Column() {
      SettingsSection({ title: t('settings_backup'), items: this.buildItems() })

      if (this.showWebDavSheet) {
        WebDavSheet({
          visible: $showWebDavSheet,
          url: backupService.getConfig().webdavUrl,
          user: backupService.getConfig().webdavUser,
          password: backupService.getConfig().webdavPassword,
          configured: this.webdavConfigured,
          onCancel: (): void => {},
          onSave: (url: string, user: string, password: string): void => {
            void this.saveWebDav(url, user, password);
          },
          onClear: (): void => {
            void this.clearWebDav();
          },
        })
      }
    }
  }
}
