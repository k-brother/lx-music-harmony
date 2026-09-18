import { t } from '../../service/LocalizationService';
/**
 * 自定义源设置视图
 * 用于设置和管理在线JS源文件地址
 */

import { pluginManager, PluginMeta } from '../../core/plugin/PluginManager';
import { navigationService } from '../../service/NavigationService';
import { storageService } from '../../service/StorageService';
import hilog from '@ohos.hilog';
import { DesignTokens } from '../../theme/DesignTokens';
import { NavBackButton } from '../../components/common/NavBackButton';

const TAG = 'CustomSource';
const DOMAIN = 0x0001;

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

  aboutToAppear() {
    this.loadCurrentSource();
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

  private showPluginErrorDialog(message: string): void {
    const msg = message && message.length > 0 ? message : t('unknown_error');
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: t('plugin_load_failed'),
        message: msg,
        buttons: [
          { text: t('got_it'), color: DesignTokens.accent() },
        ],
      });
    } catch (_e) {
      hilog.warn(DOMAIN, TAG, 'showPluginErrorDialog fallback: %{public}s', msg);
    }
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
        .fontColor(this.theme === 'dark' ? '#8E8E93' : '#8E8E93')
        .padding({ left: 16, top: 20, bottom: 8 })
        .width('100%')
        .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
    }
  }

  @Builder
  buildSourceItem(item: SourceItem) {
    ListItem() {
      Row() {
        Column() {
          Text(item.name)
            .fontSize(15)
            .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          if (item.builtIn) {
            Text('内置源')
              .fontSize(11)
              .fontColor('#999999')
              .margin({ top: 2 })
          } else {
            Text(item.url || '')
              .fontSize(11)
              .fontColor('#999999')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.selectedSource === item.id) {
          Image($r('sys.symbol.checkmark_circle_fill'))
            .width(22)
            .height(22)
            .fillColor('#007DFF')
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
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

          // 自定义源入口
          Row() {
            Column() {
              Text('在线JS源文件')
                .fontSize(15)
                .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
              Text('输入在线JS源文件地址')
                .fontSize(11)
                .fontColor('#999999')
                .margin({ top: 2 })
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.selectedSource === 'custom') {
              Image($r('sys.symbol.checkmark_circle_fill'))
                .width(22)
                .height(22)
                .fillColor('#007DFF')
            }
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
          .onClick(() => {
            this.selectSource('custom');
          })

          // URL输入区域
          if (this.selectedSource === 'custom') {
            Column() {
              Text('JS源文件地址')
                .fontSize(13)
                .fontColor('#666666')
                .padding({ left: 16, top: 12, bottom: 8 })

              TextInput({ placeholder: t('plugin_url_hint'), text: this.customSourceUrl })
                .width('100%')
                .height(44)
                .fontSize(14)
                .backgroundColor(this.theme === 'dark' ? '#2C2C2C' : '#F5F5F5')
                .borderRadius(8)
                .padding({ left: 12, right: 12 })
                .onChange((value: string) => {
                  this.customSourceUrl = value;
                })

              // 示例地址提示
              Text('提示: 安卓版 LX Music 的在线JS源可以在设置 -> 自定义源 中查看')
                .fontSize(11)
                .fontColor('#999999')
                .padding({ left: 16, top: 8, right: 16 })
                .width('100%')

              // 加载按钮
              Button(t('plugin_load_btn'))
                .width('100%')
                .height(44)
                .fontSize(15)
                .backgroundColor(this.isLoading ? '#CCCCCC' : '#007DFF')
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
                  .fontColor('#007DFF')
                  .padding({ left: 16, top: 8 })
                  .width('100%')
              }

              if (this.errorMessage) {
                Text(this.errorMessage)
                  .fontSize(13)
                  .fontColor('#FF3B30')
                  .padding({ left: 16, top: 8 })
                  .width('100%')
              }

              // 插件信息
              if (this.pluginInfo) {
                Column() {
                  Text('已加载插件信息')
                    .fontSize(13)
                    .fontColor('#666666')
                    .padding({ left: 16, top: 16, bottom: 8 })

                  Row() {
                    Text('名称:')
                      .fontSize(13)
                      .fontColor('#999999')
                      .width(60)
                    Text(this.pluginInfo.name)
                      .fontSize(13)
                      .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16 })

                  Row() {
                    Text('版本:')
                      .fontSize(13)
                      .fontColor('#999999')
                      .width(60)
                    Text(this.pluginInfo.version)
                      .fontSize(13)
                      .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 4 })

                  Row() {
                    Text('作者:')
                      .fontSize(13)
                      .fontColor('#999999')
                      .width(60)
                    Text(this.pluginInfo.author)
                      .fontSize(13)
                      .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 4 })
                  .margin({ bottom: 16 })
                }
                .width('100%')
                .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
                .borderRadius(8)
                .margin({ left: 16, right: 16, top: 16 })
              }
            }
            .width('100%')
            .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
          }

          // 使用说明
          Column() {
            Text('使用说明')
              .fontSize(13)
              .fontColor('#666666')
              .padding({ left: 16, top: 20, bottom: 8 })

            Text('1. 在设置 -> 自定义源 中，可以输入在线JS源文件地址\n' +
                 '2. JS源文件需要与 LX Music 插件格式兼容\n' +
                 '3. 加载自定义源后，可以获取更好的音乐播放体验\n' +
                 '4. 如需使用内置源，选择对应的音乐源即可')
              .fontSize(12)
              .fontColor('#999999')
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
    .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
