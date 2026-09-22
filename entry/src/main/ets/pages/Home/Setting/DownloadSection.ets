/**
 * 设置 → 下载
 *
 * 下载目录用系统文件保存面板选择（HarmonyOS 唯一获取可写目录 URI 的方式），
 * 并发数用输入面板。
 */
import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import filePicker from '@ohos.file.picker';
import hilog from '@ohos.hilog';
import { settingsService } from '../../../service/SettingsService';
import { t, tf } from '../../../service/LocalizationService';
import { appToast } from '../../../service/DialogService';
import { setMaxConcurrentDownloads } from '../../../core/music/MusicFeatureEntry';
import { watchSettings } from '../../../service/SettingsWatcher';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import type { SettingSectionItem } from '../../../components/ui/SettingsTypes';

const DOMAIN = 0x0005;
const TAG = 'DownloadSection';
const DEFAULT_DOWNLOAD_DIR = '/storage/Users/currentUser/Download';

@Component
export struct DownloadSection {
  @State downloadPath: string = '';
  @State autoStartDownload: boolean = true;
  @State maxConcurrentDownloads: number = 1;

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
    const stored = (settings.downloadPath || '').trim();
    this.downloadPath = stored.length > 0 ? stored : DEFAULT_DOWNLOAD_DIR;
    this.autoStartDownload = settings.autoStartDownload;
    this.maxConcurrentDownloads = settings.maxConcurrentDownloads;
    setMaxConcurrentDownloads(this.maxConcurrentDownloads);
    if (stored.length === 0) {
      void settingsService.update({ downloadPath: this.downloadPath });
    }  }

  /** 选择下载目录：用保存面板取一次目录 URI，再回退到父目录 */
  private async pickDownloadPath(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const picker = new filePicker.DocumentViewPicker(context);
      const saveOptions = new filePicker.DocumentSaveOptions();
      saveOptions.newFileNames = ['lxmusic-folder-marker.tmp'];
      const saveUris = await picker.save(saveOptions);
      if (!saveUris || saveUris.length === 0) {
        appToast(t('toast_dl_cancel'));
        return;
      }
      const selectedUri = saveUris[0];
      try {
        await fs.unlink(selectedUri);
      } catch (err) {
        hilog.debug(0x0005, TAG, 'placeholder cleanup skipped');
      }
      let dirUri = selectedUri;
      const lastSlash = dirUri.lastIndexOf('/');
      if (lastSlash > 0) {
        dirUri = dirUri.substring(0, lastSlash);
      }
      this.downloadPath = dirUri;
      await settingsService.update({ downloadPath: dirUri });
      appToast(t('toast_dl_path_updated'));
    } catch (err) {
      const message = err instanceof Error ? err.message : JSON.stringify(err);
      appToast(t('toast_dl_path_fail') + ': ' + message);
    }
  }

  private buildItems(): SettingSectionItem[] {
    return [
      {
        type: 'button',
        title: t('download_path'),
        description: this.downloadPath,
        onClick: (): void => {
          void this.pickDownloadPath();
        },
      },
      {
        type: 'toggle',
        title: t('download_auto_start'),
        value: this.autoStartDownload,
        onChangeToggle: (value: boolean): void => {
          this.autoStartDownload = value;
          void settingsService.update({ autoStartDownload: value });
        },
      },
      {
        type: 'input',
        title: t('download_concurrent'),
        description: t('download_concurrent_title'),
        value: this.maxConcurrentDownloads.toString(),
        onChange: (value: string): void => {
          const count = parseInt(value);
          if (isNaN(count) || count < 1 || count > 3) {
            appToast(t('download_concurrent_title'));
            return;
          }
          this.maxConcurrentDownloads = count;
          void settingsService.update({ maxConcurrentDownloads: count });
          setMaxConcurrentDownloads(count);
          appToast(tf('toast_concurrent_set', [count.toString()]));
        },
      },
    ];
  }

  build() {
    SettingsSection({ title: t('download_settings'), items: this.buildItems() })
  }
}
