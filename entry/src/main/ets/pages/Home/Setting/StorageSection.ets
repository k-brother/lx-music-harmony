/**
 * 设置 → 存储（缓存分项管理）
 *
 * 清理规则全部下沉到 CacheService（元数据 / 资源 / 历史遗留目录 / 搜索与播放历史），
 * 本组件只负责展示占用、确认与提示。
 */
import { common } from '@kit.AbilityKit';
import hilog from '@ohos.hilog';
import { t, tf } from '../../../service/LocalizationService';
import { appConfirm, appToast } from '../../../service/DialogService';
import { cacheService, formatCacheSize } from '../../../service/CacheService';
import { watchSettings } from '../../../service/SettingsWatcher';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import type { SettingSectionItem } from '../../../components/ui/SettingsTypes';

const DOMAIN = 0x0005;
const TAG = 'StorageSection';

@Component
export struct StorageSection {
  @State metaText: string = '';
  @State resourceText: string = '';

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
    void this.refreshInfo();  }

  private async refreshInfo(): Promise<void> {
    try {
      const meta = await cacheService.getMetadataCacheInfo();
      const resource = cacheService.getResourceCacheInfo();
      this.metaText = `${formatCacheSize(meta.bytes)} · ${meta.count}`;
      this.resourceText = `${formatCacheSize(resource.bytes)} · ${resource.count}`;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'refreshInfo failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 元数据缓存（歌曲链接 / 歌词） */
  private async clearMetadata(): Promise<void> {
    const before = await cacheService.getMetadataCacheInfo();
    if (before.count === 0) {
      appToast(t('settings_cache_empty'));
      return;
    }
    const confirmed = await appConfirm(
      t('settings_cache_meta'),
      tf('confirm_clear_cache_msg', [t('settings_cache_meta')]),
      { danger: true });
    if (!confirmed) {
      return;
    }
    try {
      await cacheService.clearMetadataCache();
      await this.refreshInfo();
      appToast(tf('toast_cache_freed', [formatCacheSize(before.bytes)]));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clearMetadata failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_clear_failed'));
    }
  }

  /** 资源缓存（封面图片） */
  private async clearResource(): Promise<void> {
    const before = cacheService.getResourceCacheInfo();
    if (before.count === 0) {
      appToast(t('settings_cache_empty'));
      return;
    }
    const confirmed = await appConfirm(
      t('settings_cache_resource'),
      tf('confirm_clear_cache_msg', [t('settings_cache_resource')]),
      { danger: true });
    if (!confirmed) {
      return;
    }
    try {
      await cacheService.clearResourceCache();
      await this.refreshInfo();
      appToast(tf('toast_cache_freed', [formatCacheSize(before.bytes)]));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clearResource failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_clear_failed'));
    }
  }

  /** 一键清理（含搜索/播放历史与历史遗留目录） */
  private async clearAll(): Promise<void> {
    const confirmed = await appConfirm(
      t('settings_clear_cache'),
      t('settings_clear_cache_desc'),
      { danger: true });
    if (!confirmed) {
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const clearedCount = await cacheService.clearEverything(context);
      await this.refreshInfo();
      appToast(tf('toast_cache_cleared_count', [clearedCount.toString()]));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clearAll failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_clear_failed'));
    }
  }

  private buildItems(): SettingSectionItem[] {
    return [
      {
        type: 'button',
        title: t('settings_cache_meta'),
        description: `${this.metaText} · ${t('settings_cache_meta_tip')}`,
        onClick: (): void => {
          void this.clearMetadata();
        },
      },
      {
        type: 'button',
        title: t('settings_cache_resource'),
        description: `${this.resourceText} · ${t('settings_cache_resource_tip')}`,
        onClick: (): void => {
          void this.clearResource();
        },
      },
      {
        type: 'button',
        title: t('settings_clear_cache'),
        description: t('settings_clear_cache_desc'),
        danger: true,
        onClick: (): void => {
          void this.clearAll();
        },
      },
    ];
  }

  build() {
    SettingsSection({ title: t('settings_storage'), items: this.buildItems() })
  }
}
