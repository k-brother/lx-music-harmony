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
import type { SyncStatusInfo } from '../../../service/sync/SyncTypes';
import { Subscription } from '../../../service/Subscription';
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
  /** 自动同步间隔（分钟）；此前只有默认值 30，界面上改不了 */
  @State syncInterval: number = 30;
  @State historyCount: number = 0;
  /** 同步状态文案与上次同步时间（来自 SyncService 的状态订阅） */
  @State syncStatusText: string = '';
  @State lastSyncText: string = '';
  private history: SyncHistoryItem[] = [];

  private settingsWatch: Subscription = new Subscription();
  /** SyncService 的状态回调需要持有引用才能在 aboutToDisappear 解绑 */
  private readonly onSyncStatus = (status: SyncStatusInfo): void => {
    this.syncStatusText = status.message;
    this.lastSyncText = status.lastSyncTime > 0
      ? new Date(status.lastSyncTime).toLocaleString()
      : '';
  };

  aboutToAppear() {
    this.loadFromSettings();
    // 外部改动（恢复备份 / 同步下发 / 其它入口）也要刷新本分组
    this.settingsWatch.bindSettings((): void => {
      this.loadFromSettings();
    });
    this.onSyncStatus(syncService.getStatus());
    syncService.addStatusListener(this.onSyncStatus);
  }

  aboutToDisappear() {
    this.settingsWatch.detach();
    syncService.removeStatusListener(this.onSyncStatus);
  }

  /** 从设置服务读取本分组的当前值 */
  private loadFromSettings(): void {
    const settings = settingsService.get();
    this.syncEnable = settings.syncEnabled;
    this.syncServer = settings.syncServer;
    this.syncKey = settings.syncKey;
    this.syncMode = settings.syncMode;
    this.syncAutoSync = settings.syncAutoSync;
    this.syncInterval = settings.syncInterval;
    void this.refreshHistory();  }

  private async refreshHistory(): Promise<void> {
    try {
      this.history = await syncService.getServerHistory();
      this.historyCount = this.history.length;
    } catch (err) {
      hilog.warn(0x0005, TAG, 'refreshHistory failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 同步历史：列出连接过的服务器，选中即切换为当前服务器。
   *
   * 此前这里弹出的菜单只有「使用历史服务器 / 清空同步历史」两个动作，
   * 真正的服务器列表算出来后没人用 —— 点「使用历史服务器」什么都不会发生。
   * 现在直接把历史地址作为菜单项，选中即应用（走 SyncService.applyHistoryServer）。
   */
  private async openHistory(): Promise<void> {
    await this.refreshHistory();
    if (this.history.length === 0) {
      appToast(t('toast_never_sync'));
      return;
    }
    const options: string[] = [];
    for (let i = 0; i < this.history.length; i++) {
      options.push(this.history[i].serverUrl);
    }
    const picked = await appActionMenu(t('settings_sync_history_use'), options);
    if (picked < 0 || picked >= this.history.length) {
      return;
    }
    const serverUrl = this.history[picked].serverUrl;
    await syncService.applyHistoryServer(serverUrl);
    this.syncServer = serverUrl;
    appToast(`${t('settings_sync_server')}: ${serverUrl}`);
  }

  /** 清空同步历史（连接过的服务器地址） */
  private async clearHistory(): Promise<void> {
    await this.refreshHistory();
    if (this.history.length === 0) {
      appToast(t('toast_never_sync'));
      return;
    }
    for (let i = 0; i < this.history.length; i++) {
      await syncService.removeServerHistory(this.history[i].serverUrl);
    }
    await this.refreshHistory();
    appToast(t('toast_sync_history_cleared'));
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

    // 只读状态行：把 SyncService 的连接/同步状态显示出来（此前状态只在服务内部流转）
    items.push({
      type: 'info',
      title: t('settings_sync_status'),
      description: this.lastSyncText.length > 0
        ? `${t('settings_sync_last_time')}: ${this.lastSyncText}`
        : undefined,
      value: this.syncStatusText,
    });

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

    // 自动同步开启时才需要间隔；两端都落库并立刻重启计时器（不必等下次进页面）
    if (this.syncAutoSync) {
      items.push({
        type: 'input',
        title: t('settings_sync_interval'),
        description: t('settings_sync_interval_desc'),
        value: this.syncInterval.toString(),
        onChange: (value: string): void => {
          const minutes = parseInt(value);
          if (isNaN(minutes) || minutes < 1 || minutes > 1440) {
            appToast(t('settings_sync_interval_desc'));
            return;
          }
          this.syncInterval = minutes;
          syncService.updateConfig({ syncInterval: minutes }).then((): void => {
            syncService.startAutoSync();
          }).catch((err: Error) => {
            hilog.error(0x0005, TAG, 'update syncInterval failed: %{public}s', err.message);
          });
          appToast(`${t('settings_sync_interval')}: ${minutes}`);
        },
      });
    }

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

    // 清空历史单独成行（此前混在「使用历史服务器」同一个菜单里，语义容易混）
    if (this.historyCount > 0) {
      items.push({
        type: 'button',
        title: t('settings_sync_history_clear'),
        danger: true,
        onClick: (): void => {
          void this.clearHistory();
        },
      });
    }

    return items;
  }

  build() {
    SettingsSection({ title: t('settings_sync'), items: this.buildItems() })
  }
}
