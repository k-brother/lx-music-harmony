/**
 * 设置 → 同步
 *
 * 服务器历史（连接过的地址）用 SelectSheet 呈现，选中即切换、支持清空。
 */
import { common } from '@kit.AbilityKit';
import hilog from '@ohos.hilog';
import { settingsService } from '../../../service/SettingsService';
import { t, tf } from '../../../service/LocalizationService';
import { appActionMenu, appToast } from '../../../service/DialogService';
import { syncService, SyncMode, type SyncHistoryItem } from '../../../service/SyncService';
import { watchSettings } from '../../../service/SettingsWatcher';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import type { SettingOption, SettingSectionItem } from '../../../components/ui/SettingsTypes';

const DOMAIN = 0x0005;
const TAG = 'SyncSection';

@Component
export struct SyncSection {
  @State syncEnable: boolean = false;
  @State syncServer: string = '';
  @State syncKey: string = '';
  @State syncMode: string = 'client';
  @State syncAutoSync: boolean = true;
  @State historyCount: number = 0;
  private history: SyncHistoryItem[] = [];

  private settingsUnsub: (() => void) | null = null;

  aboutToAppear() {
    this.loadFromSettings();
    // 外部改动（恢复备份 / 同步下发 / 其它入口）也要刷新本分组
    this.settingsUnsub = watchSettings((): void => {
      this.loadFromSettings();
    });
  }

  aboutToDisappear() {
    if (this.settingsUnsub) {
      this.settingsUnsub();
      this.settingsUnsub = null;
    }
  }

  /** 从设置服务读取本分组的当前值 */
  private loadFromSettings(): void {
    const settings = settingsService.get();
    this.syncEnable = settings.syncEnabled;
    this.syncServer = settings.syncServer;
    this.syncKey = settings.syncKey;
    this.syncMode = settings.syncMode;
    this.syncAutoSync = settings.syncAutoSync;
    void this.refreshHistory();  }

  private async refreshHistory(): Promise<void> {
    try {
      this.history = await syncService.getServerHistory();
      this.historyCount = this.history.length;
    } catch (err) {
      hilog.warn(0x0005, TAG, 'refreshHistory failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 同步历史：选择即切换服务器；提供清空 */
  private async openHistory(): Promise<void> {
    await this.refreshHistory();
    if (this.history.length === 0) {
      appToast(t('toast_never_sync'));
      return;
    }
    const options: SettingOption[] = [];
    for (let i = 0; i < this.history.length; i++) {
      options.push({ label: this.history[i].serverUrl, value: this.history[i].serverUrl });
    }
    const picked = await appActionMenu(t('settings_sync_history'), [
      t('settings_sync_history_use'),
      t('settings_sync_history_clear'),
    ], { dangerIndexes: [1] });
    if (picked === 1) {
      for (let i = 0; i < this.history.length; i++) {
        await syncService.removeServerHistory(this.history[i].serverUrl);
      }
      this.history = [];
      this.historyCount = 0;
      appToast(t('toast_sync_history_cleared'));
    }
  }

  private async syncNow(): Promise<void> {
    if (!this.syncEnable) {
      appToast(t('sync_msg_not_enabled'));
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      syncService.setUIContext(context);
      appToast(t('toast_sync_running'));
      const ok = await syncService.sync();
      appToast(ok ? t('toast_sync_success') : t('toast_sync_fail'));
    } catch (err) {
      hilog.error(0x0005, TAG, 'syncNow failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_sync_fail'));
    }
  }

  private buildItems(): SettingSectionItem[] {
    const modeOptions: SettingOption[] = [
      { label: t('settings_sync_mode_client'), value: 'client' },
      { label: t('settings_sync_mode_server'), value: 'server' },
    ];

    const items: SettingSectionItem[] = [];

    items.push({
      type: 'toggle',
      title: t('settings_sync_enable'),
      value: this.syncEnable,
      onChangeToggle: (value: boolean): void => {
        this.syncEnable = value;
        syncService.updateConfig({ enabled: value }).catch((err: Error) => {
          hilog.error(0x0005, TAG, 'update enabled failed: %{public}s', err.message);
        });
      },
    });

    items.push({
      type: 'input',
      title: t('settings_sync_server'),
      description: t('settings_sync_server_desc'),
      value: this.syncServer,
      onChange: (value: string): void => {
        this.syncServer = value;
        syncService.updateConfig({ serverUrl: value }).catch((err: Error) => {
          hilog.error(0x0005, TAG, 'update server failed: %{public}s', err.message);
        });
      },
    });

    items.push({
      type: 'input',
      title: t('settings_sync_key'),
      description: t('settings_sync_key_desc'),
      value: this.syncKey,
      onChange: (value: string): void => {
        this.syncKey = value;
        syncService.updateConfig({ syncKey: value }).catch((err: Error) => {
          hilog.error(0x0005, TAG, 'update key failed: %{public}s', err.message);
        });
      },
    });

    items.push({
      type: 'select',
      title: t('settings_sync_mode'),
      value: this.syncMode,
      options: modeOptions,
      onChange: (value: string): void => {
        this.syncMode = value;
        syncService.updateConfig({ mode: value === 'server' ? SyncMode.SERVER : SyncMode.CLIENT })
          .catch((err: Error) => {
            hilog.error(0x0005, TAG, 'update mode failed: %{public}s', err.message);
          });
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_sync_auto'),
      value: this.syncAutoSync,
      onChangeToggle: (value: boolean): void => {
        this.syncAutoSync = value;
        syncService.updateConfig({ autoSync: value }).catch((err: Error) => {
          hilog.error(0x0005, TAG, 'update autoSync failed: %{public}s', err.message);
        });
        if (value && this.syncEnable) {
          syncService.startAutoSync();
        } else {
          syncService.stopAutoSync();
        }
      },
    });

    items.push({
      type: 'button',
      title: t('settings_sync_now'),
      onClick: (): void => {
        void this.syncNow();
      },
    });

    items.push({
      type: 'button',
      title: t('settings_sync_history'),
      description: this.historyCount > 0
        ? tf('sync_history_count', [this.historyCount.toString()])
        : t('toast_never_sync'),
      onClick: (): void => {
        void this.openHistory();
      },
    });

    return items;
  }

  build() {
    SettingsSection({ title: t('settings_sync'), items: this.buildItems() })
  }
}
