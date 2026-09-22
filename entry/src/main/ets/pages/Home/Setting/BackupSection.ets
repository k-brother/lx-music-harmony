/**
 * 设置 → 备份与恢复
 *
 * 备份/恢复走 BackupService（整包数据），导入/导出歌单走 PlaylistTransferService（JSON）。
 * 本组件只负责：文件选择器、确认、提示、恢复后重载列表数据。
 */
import { common } from '@kit.AbilityKit';
import filePicker from '@ohos.file.picker';
import hilog from '@ohos.hilog';
import { t, tf } from '../../../service/LocalizationService';
import { appConfirm, appToast } from '../../../service/DialogService';
import { backupService, BackupDataType } from '../../../service/BackupService';
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

const DOMAIN = 0x0001;
const TAG = 'BackupSection';

@Component
export struct BackupSection {
  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 整包备份 */
  private async backupData(): Promise<void> {
    try {
      appToast(t('toast_backup_running'));
      backupService.setContext(this.hostContext());
      const file = await backupService.createBackup(BackupDataType.ALL);
      if (file) {
        hilog.info(DOMAIN, TAG, 'Backup created: %{public}s', file.fileName);
        appToast(t('toast_backup_success'));
      } else {
        appToast(t('toast_backup_fail'));
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
      const confirmed = await appConfirm(
        t('restore_confirm_title'),
        tf('confirm_restore_backup', [file.fileName]),
        { danger: true });
      if (!confirmed) {
        appToast(t('toast_restore_cancel'));
        return;
      }
      const ok = await backupService.restoreBackup(file);
      if (!ok) {
        appToast(t('toast_restore_fail'));
        return;
      }
      appToast(t('toast_restore_success'));
      // 恢复后列表数据需要重新加载，否则界面还是旧数据
      await initListService();
      hilog.info(DOMAIN, TAG, 'App data reloaded after restore');
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

  private buildItems(): SettingSectionItem[] {
    return [
      {
        type: 'button',
        title: t('settings_backup_data'),
        description: t('settings_backup_data_desc'),
        onClick: (): void => {
          void this.backupData();
        },
      },
      {
        type: 'button',
        title: t('settings_restore_data'),
        description: t('settings_restore_data_desc'),
        onClick: (): void => {
          void this.restoreData();
        },
      },
      {
        type: 'button',
        title: t('settings_export_list'),
        description: t('settings_export_list_desc'),
        onClick: (): void => {
          void this.exportPlaylists();
        },
      },
      {
        type: 'button',
        title: t('settings_import_list'),
        description: t('settings_import_list_desc'),
        onClick: (): void => {
          void this.importPlaylists();
        },
      },
    ];
  }

  build() {
    SettingsSection({ title: t('settings_backup'), items: this.buildItems() })
  }
}
