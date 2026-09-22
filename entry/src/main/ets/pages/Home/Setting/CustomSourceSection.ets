/**
 * 设置 → 自定义源
 *
 * 入口跳转到自定义源管理页；同时提供「快速导入」底部面板：
 * - 在线链接导入（校验 http(s)）
 * - 本地 .js 文件导入
 * 面板与状态由本组件自持，不再占用页面状态。
 */
import { common } from '@kit.AbilityKit';
import filePicker from '@ohos.file.picker';
import hilog from '@ohos.hilog';
import { t } from '../../../service/LocalizationService';
import { navigationService, RouteName } from '../../../service/NavigationService';
import { appToast } from '../../../service/DialogService';
import { DesignTokens } from '../../../theme/DesignTokens';
import { loadCustomSource } from '../../../core/music/MusicFeatureEntry';
import { pluginManager } from '../../../core/plugin/PluginManager';
import { BottomSheet } from '../../../components/ui/BottomSheet';
import { watchSettings } from '../../../service/SettingsWatcher';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import type { SettingSectionItem } from '../../../components/ui/SettingsTypes';

const DOMAIN = 0x0001;
const TAG = 'CustomSourceSection';

@Component
export struct CustomSourceSection {
  @StorageProp('theme') theme: string = 'light';
  @State showImport: boolean = false;
  @State url: string = '';
  @State loading: boolean = false;
  @State error: string = '';
  /** 已加载自定义源的名字（未加载为空） */
  @State loadedName: string = '';

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
    const meta = pluginManager.getPluginInfo();
    this.loadedName = meta ? meta.name : '';  }

  private isValidUrl(value: string): boolean {
    return /^https?:\/\/.+/i.test(value.trim());
  }

  /** 在线链接导入 */
  private async importFromUrl(): Promise<void> {
    const url = this.url.trim();
    if (url.length === 0) {
      this.error = t('source_import_fail');
      return;
    }
    if (!this.isValidUrl(url)) {
      this.error = t('invalid_url_format');
      return;
    }
    this.loading = true;
    this.error = '';
    try {
      const ok = await loadCustomSource(url);
      this.applyResult(ok, t('source_import_success'), t('source_import_fail'));
    } catch (err) {
      this.failWith(err instanceof Error ? err.message : JSON.stringify(err));
    } finally {
      this.loading = false;
    }
  }

  /** 本地 .js 文件导入 */
  private async importFromFile(): Promise<void> {
    this.loading = true;
    this.error = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options = new filePicker.DocumentSelectOptions();
      options.fileSuffixFilters = ['.js'];
      const picker = new filePicker.DocumentViewPicker(context);
      const uris = await picker.select(options);
      if (!uris || uris.length === 0) {
        appToast(t('toast_import_cancel'));
        return;
      }
      const ok = await loadCustomSource(uris[0]);
      this.applyResult(ok, t('source_local_import_success'), t('source_local_import_fail'));
    } catch (err) {
      this.failWith(err instanceof Error ? err.message : JSON.stringify(err));
    } finally {
      this.loading = false;
    }
  }

  /** 统一处理导入结果：成功关面板提示，失败留在面板里显示原因 */
  private applyResult(ok: boolean, successText: string, failText: string): void {
    if (ok) {
      const meta = pluginManager.getPluginInfo();
      this.loadedName = meta ? meta.name : '';
      this.showImport = false;
      this.url = '';
      appToast(successText);
      return;
    }
    this.failWith(failText);
  }

  private failWith(message: string): void {
    const content = message.trim().length > 0 ? message : t('unknown_error');
    this.error = content;
    hilog.warn(DOMAIN, TAG, 'custom source import failed: %{public}s', content);
  }

  private buildItems(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];
    items.push({
      type: 'button',
      title: t('settings_custom_source'),
      description: this.loadedName.length > 0
        ? `${t('custom_source_in_use')}: ${this.loadedName}`
        : t('settings_custom_source_desc'),
      onClick: (): void => {
        navigationService.navigateTo(RouteName.CUSTOM_SOURCE);
      },
    });
    items.push({
      type: 'button',
      title: t('custom_source_quick_import'),
      description: t('custom_source_online_js') + ' / ' + t('custom_source_local_js'),
      onClick: (): void => {
        this.error = '';
        this.showImport = true;
      },
    });
    return items;
  }

  /** 快速导入面板 */
  @Builder
  ImportForm() {
    Column({ space: 12 }) {
      TextInput({ placeholder: t('custom_source_url_placeholder'), text: this.url })
        .height(DesignTokens.touchTarget())
        .width('100%')
        .backgroundColor(DesignTokens.mutedFill(this.theme))
        .borderRadius(12)
        .padding({ left: 14, right: 14 })
        .fontSize(15)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .placeholderColor(DesignTokens.labelTertiary(this.theme))
        .onChange((value: string) => {
          this.url = value;
        })

      if (this.error.length > 0) {
        Text(this.error)
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.danger())
          .width('100%')
          .maxLines(3)
      }

      Row({ space: 12 }) {
        Button(this.loading ? t('loading') : t('custom_source_import_from_url'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(DesignTokens.touchTarget())
          .fontSize(15)
          .fontColor('#FFFFFF')
          .backgroundColor(DesignTokens.accent())
          .enabled(!this.loading)
          .onClick(() => {
            void this.importFromUrl();
          })
        Button(t('custom_source_local_js'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(DesignTokens.touchTarget())
          .fontSize(15)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .backgroundColor(DesignTokens.mutedFill(this.theme))
          .enabled(!this.loading)
          .onClick(() => {
            void this.importFromFile();
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  build() {
    Stack() {
      SettingsSection({ title: t('settings_custom_source'), items: this.buildItems() })

      if (this.showImport) {
        BottomSheet({
          visible: $showImport,
          title: t('custom_source_quick_import'),
          content: (): void => {
            this.ImportForm();
          },
        })
      }
    }
    .width('100%')
  }
}
