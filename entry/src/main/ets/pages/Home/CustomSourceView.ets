import { t, tf } from '../../service/LocalizationService';
import { showAppToast, TOAST_DURATION_DEFAULT } from '../../utils/Toast';
import { CustomSourceRow } from './CustomSource/CustomSourceRow';
import { appAlert, appConfirm } from '../../service/DialogService';
/**
 * 自定义源设置视图
 * 用于设置和管理在线JS源文件地址
 */

import { pluginManager, PluginMeta } from '../../core/plugin/PluginManager';
import type { StoredCustomSource } from '../../core/plugin/PluginStore';
import { navigationService } from '../../service/NavigationService';
import { storageService } from '../../service/StorageService';
import hilog from '@ohos.hilog';
import filePicker from '@ohos.file.picker';
import { common } from '@kit.AbilityKit';
import { DesignTokens } from '../../theme/DesignTokens';
import { NavBackButton } from '../../components/common/NavBackButton';

const TAG = 'CustomSource';
const DOMAIN = 0x0001;

interface PromptActionResult {
  index: number;
}

// 默认源列表
const DEFAULT_SOURCES: SourceItem[] = [
  { id: 'kw', name: t('source_kw'), builtIn: true },
  { id: 'kg', name: t('source_kg'), builtIn: true },
  { id: 'tx', name: t('source_tx'), builtIn: true },
  { id: 'wy', name: t('source_wy'), builtIn: true },
  { id: 'mg', name: t('source_mg'), builtIn: true },
];

interface SourceItem {
  id: string;
  name: string;
  builtIn: boolean;
  url?: string;
}

@Component
export struct CustomSourceView {
  /** 按压反馈：可点的源行/导入行变淡 */
  @Styles
  pressed() {
    .opacity(DesignTokens.pressedOpacity())
  }

  @StorageProp('theme') theme: string = 'light';
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State currentSource: string = 'kw';
  @State customSourceUrl: string = '';
  @State isLoading: boolean = false;
  @State loadStatus: string = '';
  @State pluginInfo: PluginMeta | null = null;
  @State errorMessage: string = '';
  @State selectedSource: string = 'kw';
  @State isShowUrlInput: boolean = false;
  /** 已保存的自定义源列表（多源管理：启用/停用/更新/删除） */
  @State customSources: StoredCustomSource[] = [];
  /** 正在处理中的源 id（避免重复点击） */
  @State busySourceId: string = '';

  aboutToAppear() {
    this.loadCurrentSource();
    void this.refreshCustomSources();
  }

  /** 刷新自定义源列表 */
  private async refreshCustomSources(): Promise<void> {
    try {
      this.customSources = await pluginManager.getStoredSources();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'refreshCustomSources failed: %{public}s', JSON.stringify(err));
      this.customSources = [];
    }
  }

  /** 启用/停用某个自定义源 */
  /** 从 id 找当前数据（组件只回调 id，避免闭包持有旧对象） */
  private findSource(sourceId: string): StoredCustomSource | undefined {
    return this.customSources.find((item: StoredCustomSource): boolean => item.id === sourceId);
  }

  private async toggleSourceEnabledById(sourceId: string, enabled: boolean): Promise<void> {
    const source = this.findSource(sourceId);
    if (source) {
      await this.toggleSourceEnabled(source);
    }
  }

  private async updateSourceById(sourceId: string): Promise<void> {
    const source = this.findSource(sourceId);
    if (source) {
      await this.updateSource(source);
    }
  }

  private async removeSourceById(sourceId: string): Promise<void> {
    const source = this.findSource(sourceId);
    if (source) {
      await this.removeSource(source);
    }
  }

  private async toggleSourceEnabled(source: StoredCustomSource): Promise<void> {
    if (this.busySourceId.length > 0) {
      return;
    }
    this.busySourceId = source.id;
    this.isLoading = true;
    this.loadStatus = t('loading');
    try {
      const next = !source.enabled;
      const ok = await pluginManager.setSourceEnabled(source.id, next);
      if (ok) {
        this.currentSource = next ? 'custom' : 'kw';
        this.pluginInfo = pluginManager.getPluginInfo();
        this.showToast(next ? t('custom_source_enabled') : t('custom_source_disabled'));
      } else {
        this.showPluginErrorDialog(pluginManager.getError() || t('plugin_load_failed'));
      }
      await this.refreshCustomSources();
    } catch (err) {
      this.showPluginErrorDialog((err as Error).message || t('unknown_error'));
    } finally {
      this.isLoading = false;
      this.loadStatus = '';
      this.busySourceId = '';
    }
  }

  /** 重新下载脚本并刷新（「更新」） */
  private async updateSource(source: StoredCustomSource): Promise<void> {
    if (this.busySourceId.length > 0) {
      return;
    }
    this.busySourceId = source.id;
    this.isLoading = true;
    this.loadStatus = t('loading');
    try {
      const ok = await pluginManager.updateSource(source.id);
      if (ok) {
        this.showToast(t('custom_source_updated'));
        this.pluginInfo = pluginManager.getPluginInfo();
      } else {
        this.showPluginErrorDialog(pluginManager.getError() || t('plugin_load_failed'));
      }
      await this.refreshCustomSources();
    } catch (err) {
      this.showPluginErrorDialog((err as Error).message || t('unknown_error'));
    } finally {
      this.isLoading = false;
      this.loadStatus = '';
      this.busySourceId = '';
    }
  }

  /** 删除自定义源（带确认） */
  private async removeSource(source: StoredCustomSource): Promise<void> {
    // 统一走 DialogService 的危险确认（不再自己拼按钮与颜色）
    const confirmed = await appConfirm(
      t('custom_source_remove'),
      tf('custom_source_remove_confirm', [source.name]),
      { danger: true, confirmText: t('delete') });
    if (!confirmed) {
      return;
    }
    try {
      await pluginManager.removeSource(source.id);
      if (this.customSources.length <= 1) {
        this.currentSource = 'kw';
        this.pluginInfo = null;
      }
      await this.refreshCustomSources();
      this.showToast(t('custom_source_removed'));
    } catch (err) {
      this.showPluginErrorDialog((err as Error).message || t('unknown_error'));
    }
  }

  async loadCurrentSource() {
    try {
      // 使用统一的 storageService，不需要直接获取上下文
      const savedSource = await storageService.getString('plugin.currentSource', 'kw');
      const savedUrl = await storageService.getString('plugin.customSourceUrl', '');
      this.currentSource = savedSource;
      this.customSourceUrl = savedUrl;
      this.selectedSource = this.currentSource;

      hilog.info(DOMAIN, TAG, 'Loaded current source: %{public}s', this.currentSource);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to load current source: %{public}s', JSON.stringify(err));
    }
  }

  async saveSettings() {
    try {
      // 使用统一的 storageService
      await storageService.setString('plugin.currentSource', this.currentSource);
      await storageService.setString('plugin.customSourceUrl', this.customSourceUrl);
      hilog.info(DOMAIN, TAG, 'Settings saved');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save settings: %{public}s', JSON.stringify(err));
    }
  }

  async loadPlugin() {
    if (!this.customSourceUrl || this.customSourceUrl.length === 0) {
      this.errorMessage = t('plugin_enter_url');
      return;
    }

    // 验证URL格式
    if (!this.isValidUrl(this.customSourceUrl)) {
      this.errorMessage = t('plugin_invalid_url');
      return;
    }

    this.isLoading = true;
    this.loadStatus = t('loading');
    this.errorMessage = '';

    try {
      const success = await pluginManager.loadCustomSource(this.customSourceUrl);
      if (success) {
        this.loadStatus = t('toast_playlist_created');
        this.pluginInfo = pluginManager.getPluginInfo();
        this.currentSource = 'custom';
        await this.saveSettings();
      } else {
        this.loadStatus = '';
        this.errorMessage = pluginManager.getError() || t('plugin_load_failed');
        this.showPluginErrorDialog(this.errorMessage);
      }
    } catch (error) {
      this.errorMessage = (error as Error).message || t('load_failed');
      this.showPluginErrorDialog(this.errorMessage);
    } finally {
      this.isLoading = false;
    }
  }

  /** 轻提示（统一走 utils/Toast） */
  private showToast(message: string): void {
    showAppToast(this.getUIContext(), message, TOAST_DURATION_DEFAULT);
  }

  /** 从本地选择 JS 源文件导入（安卓版 userApi 的脚本导入） */
  private async importFromLocalFile(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const picker = new filePicker.DocumentViewPicker(context);
      const options = new filePicker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['.js'];
      const uris = await picker.select(options);
      if (!uris || uris.length === 0) {
        return;
      }
      const picked = uris[0];
      this.isLoading = true;
      this.loadStatus = t('loading');
      this.errorMessage = '';
      const success = await pluginManager.loadCustomSource(picked);
      if (success) {
        this.pluginInfo = pluginManager.getPluginInfo();
        this.currentSource = 'custom';
        this.showToast(t('custom_source_imported'));
      } else {
        this.showPluginErrorDialog(pluginManager.getError() || t('plugin_load_failed'));
      }
      await this.refreshCustomSources();
    } catch (err) {
      this.showPluginErrorDialog((err as Error).message || t('unknown_error'));
    } finally {
      this.isLoading = false;
      this.loadStatus = '';
    }
  }

  private showPluginErrorDialog(message: string): void {
    const msg = message && message.length > 0 ? message : t('unknown_error');
    // 单按钮提示统一走 DialogService.appAlert
    appAlert(t('plugin_load_failed'), msg).catch((err: Error): void => {
      hilog.warn(DOMAIN, TAG, 'showPluginErrorDialog fallback: %{public}s', err.message);
    });
  }

  isValidUrl(url: string): boolean {
    try {
      const regex = /^https?:\/\/.+\.js(\?.*)?$/i;
      return regex.test(url);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'isValidUrl failed: %{public}s', (e as Error)?.message);
      return false;
    }
  }

  selectSource(sourceId: string) {
    this.selectedSource = sourceId;
    if (sourceId !== 'custom') {
      this.currentSource = sourceId;
      this.saveSettings();
      hilog.info(DOMAIN, TAG, 'Selected source: %{public}s', sourceId);
    } else {
      this.isShowUrlInput = true;
    }
  }

  onBackPressed(): boolean {
    navigationService.back();
    return true;
  }

  // NavDestination onReady callback
  onReady(params: Record<string, object | string | number | boolean | undefined>): void {
    hilog.info(DOMAIN, TAG, 'CustomSourceView onReady with params: %{public}s', JSON.stringify(params));
  }

  @Builder
  buildHeader(title: string) {
    Column() {
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.labelTertiary(this.theme))
        .padding({ left: 16, top: 20, bottom: 8 })
        .width('100%')
        .backgroundColor(DesignTokens.pageBg(this.theme))
    }
  }

  /** 一条自定义源：名称/版本/作者 + 启用开关 + 更新 + 删除 */
  @Builder
  buildSourceItem(item: SourceItem) {
    ListItem() {
      Row() {
        Column() {
          Text(item.name)
            .fontSize(15)
            .fontColor(DesignTokens.labelPrimary(this.theme))
          if (item.builtIn) {
            Text(t('custom_source_builtin'))
              .fontSize(11)
              .fontColor(DesignTokens.labelSecondary(this.theme))
              .margin({ top: 2 })
          } else {
            Text(item.url || '')
              .fontSize(11)
              .fontColor(DesignTokens.labelSecondary(this.theme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.selectedSource === item.id) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(26)
            .fontColor([DesignTokens.accent()])
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor(DesignTokens.card(this.theme))
      .stateStyles({ pressed: this.pressed })
      .onClick(() => {
        this.selectSource(item.id);
      })
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        NavBackButton()

        Text(t('custom_sources'))
          .fontSize(DesignTokens.fontTitle())
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .layoutWeight(1)
          .margin({ left: 12 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .height(60)
      .padding({ left: 14, right: 14, top: 8, bottom: 6 })
      .backgroundColor(DesignTokens.chromeBar(this.theme))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])

      Scroll() {
        Column() {
          // 内置源
          this.buildHeader(t('builtin_sources'))

          ForEach(DEFAULT_SOURCES, (item: SourceItem) => {
            this.buildSourceItem(item)
          })

          // 自定义源
          this.buildHeader(t('custom_sources'))

          // 已保存的自定义源列表：启用/停用、更新、删除（对齐安卓版 userApi 管理）
          if (this.customSources.length > 0) {
            ForEach(this.customSources, (source: StoredCustomSource) => {
              CustomSourceRow({
                sourceId: source.id,
                sourceName: source.name,
                sourceUrl: source.url,
                version: source.version,
                author: source.author,
                isEnabled: source.enabled,
                busy: this.busySourceId.length > 0,
                onToggle: (sourceId: string, enabled: boolean): void => {
                  void this.toggleSourceEnabledById(sourceId, enabled);
                },
                onUpdate: (sourceId: string): void => {
                  void this.updateSourceById(sourceId);
                },
                onRemove: (sourceId: string): void => {
                  void this.removeSourceById(sourceId);
                },
              })
            }, (source: StoredCustomSource) => `${source.id}_${source.enabled}_${source.version}`)
          }

          // 自定义源入口
          Row() {
            Column() {
              Text(t('custom_source_online_js'))
                .fontSize(15)
                .fontColor(DesignTokens.labelPrimary(this.theme))
              Text(t('custom_source_url_placeholder'))
                .fontSize(11)
                .fontColor(DesignTokens.labelSecondary(this.theme))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.selectedSource === 'custom') {
              SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                .fontSize(26)
                .fontColor([DesignTokens.accent()])
            }
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .backgroundColor(DesignTokens.card(this.theme))
          .onClick(() => {
            this.selectSource('custom');
          })

          // URL输入区域
          if (this.selectedSource === 'custom') {
            Column() {
              Text(t('custom_source_js_url'))
                .fontSize(13)
                .fontColor(DesignTokens.labelSecondary(this.theme))
                .padding({ left: 16, top: 12, bottom: 8 })

              TextInput({ placeholder: t('plugin_url_hint'), text: this.customSourceUrl })
                .width('100%')
                .height(44)
                .fontSize(14)
                .backgroundColor(DesignTokens.mutedFill(this.theme))
                .borderRadius(8)
                .padding({ left: 12, right: 12 })
                .onChange((value: string) => {
                  this.customSourceUrl = value;
                })

              // 示例地址提示
              Text(t('custom_source_hint'))
                .fontSize(11)
                .fontColor(DesignTokens.labelSecondary(this.theme))
                .padding({ left: 16, top: 8, right: 16 })
                .width('100%')

              // 加载按钮
              Button(t('plugin_load_btn'))
                .width('100%')
                .height(44)
                .fontSize(15)
                .backgroundColor(this.isLoading ? DesignTokens.disabled(this.theme) : DesignTokens.accent())
                .fontColor('#FFFFFF')
                .borderRadius(8)
                .margin({ top: 16, left: 16, right: 16 })
                .enabled(!this.isLoading)
                .onClick(() => {
                  this.loadPlugin();
                })

              // 状态显示
              if (this.loadStatus) {
                Text(this.loadStatus)
                  .fontSize(13)
                  .fontColor(DesignTokens.accent())
                  .padding({ left: 16, top: 8 })
                  .width('100%')
              }

              if (this.errorMessage) {
                Text(this.errorMessage)
                  .fontSize(13)
                  .fontColor(DesignTokens.danger())
                  .padding({ left: 16, top: 8 })
                  .width('100%')
              }

              // 插件信息
              if (this.pluginInfo) {
                Column() {
                  Text(t('custom_source_plugin_info'))
                    .fontSize(13)
                    .fontColor(DesignTokens.labelSecondary(this.theme))
                    .padding({ left: 16, top: 16, bottom: 8 })

                  Row() {
                    Text(t('label_name_colon'))
                      .fontSize(13)
                      .fontColor(DesignTokens.labelSecondary(this.theme))
                      .width(60)
                    Text(this.pluginInfo.name)
                      .fontSize(13)
                      .fontColor(DesignTokens.labelPrimary(this.theme))
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16 })

                  Row() {
                    Text(t('label_version_colon'))
                      .fontSize(13)
                      .fontColor(DesignTokens.labelSecondary(this.theme))
                      .width(60)
                    Text(this.pluginInfo.version)
                      .fontSize(13)
                      .fontColor(DesignTokens.labelPrimary(this.theme))
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 4 })

                  Row() {
                    Text(t('label_author_colon'))
                      .fontSize(13)
                      .fontColor(DesignTokens.labelSecondary(this.theme))
                      .width(60)
                    Text(this.pluginInfo.author)
                      .fontSize(13)
                      .fontColor(DesignTokens.labelPrimary(this.theme))
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 4 })
                  .margin({ bottom: 16 })
                }
                .width('100%')
                .backgroundColor(DesignTokens.card(this.theme))
                .borderRadius(8)
                .margin({ left: 16, right: 16, top: 16 })
              }
            }
            .width('100%')
            .backgroundColor(DesignTokens.pageBg(this.theme))
          }

          // 本地 JS 文件导入（与在线链接导入并列，对齐安卓版脚本导入）
          Row() {
            Column() {
              Text(t('custom_source_local_js'))
                .fontSize(15)
                .fontColor(DesignTokens.labelPrimary(this.theme))
              Text(t('custom_source_local_js_desc'))
                .fontSize(11)
                .fontColor(DesignTokens.labelSecondary(this.theme))
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            SymbolGlyph($r('sys.symbol.folder'))
              .fontSize(22)
              .fontColor([DesignTokens.accent()])
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .backgroundColor(DesignTokens.card(this.theme))
          .borderRadius(10)
          .border({ width: 0.33, color: DesignTokens.cardBorder(this.theme) })
          .margin({ left: 16, right: 16, top: 8 })
          .stateStyles({ pressed: this.pressed })
          .onClick(() => {
            void this.importFromLocalFile();
          })

          // 使用说明
          Column() {
            Text(t('custom_source_help_title'))
              .fontSize(13)
              .fontColor(DesignTokens.labelSecondary(this.theme))
              .padding({ left: 16, top: 20, bottom: 8 })

            Text(t('custom_source_help_body'))
              .fontSize(12)
              .fontColor(DesignTokens.labelSecondary(this.theme))
              .padding({ left: 16, right: 16, bottom: 20 })
              .lineHeight(20)
          }
          .width('100%')
        }
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
