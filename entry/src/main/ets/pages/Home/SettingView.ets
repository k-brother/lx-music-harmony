// Setting 视图 - 对应 src/screens/Home/Views/Setting/index.tsx
// 设置视图 - 完整版

import { navigationService, RouteName } from '../../service/NavigationService';
import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import hilog from '@ohos.hilog';
import { DesignTokens } from '../../theme/DesignTokens';
import { backupService, BackupDataType } from '../../service/BackupService';
import fs from '@ohos.file.fs';
import filePicker from '@ohos.file.picker';
import { utf8Encode, utf8Decode } from '../../utils/TextCodec';
import { musicItemFromPlainObject } from '../../core/list/PlaylistRecordMapper';
import {
  getUserList,
  getDefaultList,
  getLoveList,
  LIST_IDS,
  createUserList,
  addMusicToList,
  MusicItem
} from '../../service/ListService';
import { clearPlayHistory as clearPlayHistoryStore } from '../../service/PlayHistoryService';
import { loadCustomSource } from '../../core/music/MusicFeatureEntry';

const TAG = 'SETTING';
const DOMAIN = 0x0001;

// 导出歌单 JSON 中单条歌单结构
interface ExportedPlaylistRow {
  id: string;
  name: string;
  type: string;
  musicCount?: number;
  musicList?: MusicItem[];
  source?: string;
  desc?: string;
  pic?: string;
  count?: number;
  createTime?: number;
  updateTime?: number;
}

// 导出歌单根对象
interface PlaylistsExportRoot {
  appVersion: string;
  exportTime: string;
  playlists: ExportedPlaylistRow[];
}

// 设置选项类型
interface SettingOption {
  label: string;
  value: string;
}

// 设置项选项类型（包含number类型value）
interface SettingItemOption {
  label: string;
  value: string | number;
}

// 设置区块项类型
interface SettingSectionItem {
  type: string;
  title: string;
  description?: string;
  value?: string | boolean;
  options?: Array<SettingOption>;
  onChange?: (value: string) => void;
  onChangeToggle?: (value: boolean) => void;
  onClick?: () => void;
}

// 设置项类型
interface SettingItem {
  id: string;
  title: string;
  description?: string;
  type: string;
  value?: boolean | string | number;
  options?: Array<SettingItemOption>;
}

@Component
export struct SettingView {
  @StorageProp('theme') theme: string = 'light';

  // 基础设置
  @State language: string = 'zh-CN';
  @State startupPage: string = 'home';
  @State showExitDialog: boolean = true;

  // 播放设置
  @State autoPlay: boolean = false;
  @State highQuality: boolean = true;
  @State playMode: string = 'listLoop';
  @State volume: number = 80;
  @State timeoutExit: boolean = false;
  @State timeoutMinutes: number = 30;

  // 搜索设置
  @State searchSource: string = 'kw';
  @State showHotSearch: boolean = true;
  @State searchHistoryCount: number = 20;

  // 列表设置
  @State listAddMusicLocation: string = 'top';
  @State autoCleanPlayedList: boolean = false;

  // 同步设置
  @State syncEnable: boolean = false;
  @State syncServer: string = '';
  @State syncKey: string = '';

  // 外观设置
  @State fontSize: number = 14;
  @State showAnimation: boolean = true;
  @State showSourceImportDialog: boolean = false;
  @State sourceImportUrl: string = '';
  @State sourceImportLoading: boolean = false;
  @State sourceImportError: string = '';

  aboutToAppear() {
    this.loadSettings();
  }

  async loadSettings() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'music_settings');

      // 基础设置
      this.language = await pref.get('language', 'zh-CN') as string;
      this.startupPage = await pref.get('startupPage', 'home') as string;
      this.showExitDialog = await pref.get('showExitDialog', true) as boolean;

      // 播放设置
      this.autoPlay = await pref.get('autoPlay', false) as boolean;
      this.highQuality = await pref.get('highQuality', true) as boolean;
      this.playMode = await pref.get('playMode', 'listLoop') as string;
      this.volume = await pref.get('volume', 80) as number;
      this.timeoutExit = await pref.get('timeoutExit', false) as boolean;
      this.timeoutMinutes = await pref.get('timeoutMinutes', 30) as number;

      // 搜索设置
      this.searchSource = await pref.get('searchSource', 'kw') as string;
      this.showHotSearch = await pref.get('showHotSearch', true) as boolean;
      this.searchHistoryCount = await pref.get('searchHistoryCount', 20) as number;

      // 列表设置
      this.listAddMusicLocation = await pref.get('listAddMusicLocation', 'top') as string;
      this.autoCleanPlayedList = await pref.get('autoCleanPlayedList', false) as boolean;

      // 同步设置
      this.syncEnable = await pref.get('syncEnable', false) as boolean;
      this.syncServer = await pref.get('syncServer', '') as string;
      this.syncKey = await pref.get('syncKey', '') as string;

      // 外观设置
      this.fontSize = await pref.get('fontSize', 14) as number;
      this.showAnimation = await pref.get('showAnimation', true) as boolean;

      hilog.info(DOMAIN, TAG, 'Settings loaded successfully');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to load settings: %{public}s', JSON.stringify(err));
    }
  }

  async saveSettings() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'music_settings');

      // 基础设置
      await pref.put('language', this.language);
      await pref.put('startupPage', this.startupPage);
      await pref.put('showExitDialog', this.showExitDialog);

      // 播放设置
      await pref.put('autoPlay', this.autoPlay);
      await pref.put('highQuality', this.highQuality);
      await pref.put('playMode', this.playMode);
      await pref.put('volume', this.volume);
      await pref.put('timeoutExit', this.timeoutExit);
      await pref.put('timeoutMinutes', this.timeoutMinutes);

      // 搜索设置
      await pref.put('searchSource', this.searchSource);
      await pref.put('showHotSearch', this.showHotSearch);
      await pref.put('searchHistoryCount', this.searchHistoryCount);

      // 列表设置
      await pref.put('listAddMusicLocation', this.listAddMusicLocation);
      await pref.put('autoCleanPlayedList', this.autoCleanPlayedList);

      // 同步设置
      await pref.put('syncEnable', this.syncEnable);
      await pref.put('syncServer', this.syncServer);
      await pref.put('syncKey', this.syncKey);

      // 外观设置
      await pref.put('fontSize', this.fontSize);
      await pref.put('showAnimation', this.showAnimation);

      await pref.flush();
      hilog.info(DOMAIN, TAG, 'Settings saved successfully');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save settings: %{public}s', JSON.stringify(err));
    }
  }

  async saveThemeSetting() {
    try {
      // 同步到 AppStorage 以便全局生效
      AppStorage.setOrCreate('theme', this.theme);
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'music_settings');
      await pref.put('theme', this.theme);
      await pref.flush();
      hilog.info(DOMAIN, TAG, 'Theme saved: %{public}s', this.theme);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save theme setting: %{public}s', JSON.stringify(err));
    }
  }



  build() {
    Stack() {
      Scroll() {
        Column() {
          // 基础设置
          this.buildSettingSection('基础设置', this.buildBasicSettings())

          // 播放设置
          this.buildSettingSection('播放设置', this.buildPlaybackSettings())

          // 搜索设置
          this.buildSettingSection('搜索设置', this.buildSearchSettings())

          // 列表设置
          this.buildSettingSection('列表设置', this.buildListSettings())

          // 备份与恢复
          this.buildSettingSection('备份与恢复', this.buildBackupSettings())

          // 同步设置
          this.buildSettingSection('同步', this.buildSyncSettings())

          // 外观设置
          this.buildSettingSection('外观', this.buildAppearanceSettings())

          // 自定义源设置
          this.buildSettingSection('自定义源', this.buildCustomSourceSettings())

          // 关于
          this.buildSettingSection('关于', this.buildAboutSettings())
        }
        .width('100%')
        .padding({ bottom: 20 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')

      this.buildSourceImportDialog()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildSettingSection(title: string, items: Array<SettingSectionItem>) {
    Column() {
      // 标题
      Text(title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme === 'dark' ? '#8E8E93' : '#8E8E93')
        .padding({ left: 16, top: 20, bottom: 8 })
        .width('100%')
        .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')

      // 设置项
      ForEach(items, (item: SettingSectionItem, index: number) => {
        Column() {
          Row() {
            Column() {
              Text(item.title)
                .fontSize(15)
                .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
              if (item.description) {
                Text(item.description)
                  .fontSize(11)
                  .fontColor('#999999')
                  .margin({ top: 2 })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (item.type === 'toggle') {
              Toggle({ type: ToggleType.Switch, isOn: item.value as boolean })
                .onChange((isOn: boolean) => {
                  if (item.onChangeToggle) {
                    item.onChangeToggle(isOn);
                  }
                })
            } else if (item.type === 'select') {
              Text(this.getOptionLabel(item.options || [], item.value as string))
                .fontSize(14)
                .fontColor('#999999')
              Image($r('sys.symbol.chevron_right'))
                .width(16)
                .height(16)
                .fillColor('#999999')
                .margin({ left: 8 })
            } else if (item.type === 'button') {
              Image($r('sys.symbol.chevron_right'))
                .width(16)
                .height(16)
                .fillColor('#999999')
            } else if (item.type === 'input') {
              Text(item.value as string)
                .fontSize(14)
                .fontColor('#999999')
                .maxLines(1)
            }
          }
          .width('100%')
          .height(item.description ? 56 : 50)
          .padding({ left: 16, right: 16 })
          .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
          .onClick(() => {
            if (item.type === 'button') {
              if (item.onClick) {
                item.onClick();
              }
            } else if (item.type === 'select') {
              // 对于select类型，应该显示选择器让用户选择
              // 这里先调用onChange回调（如果有），实际应用中应该显示选择器
              if (item.onChange && item.options && item.options.length > 0) {
                // 在实际应用中，这里应该显示一个选择器对话框
                // 暂时先选择下一个选项作为示例（循环选择）
                const currentValue = item.value as string;
                const currentIndex = item.options.findIndex((opt: SettingOption) => opt.value === currentValue);
                const nextIndex = (currentIndex + 1) % item.options.length;
                const nextOption = item.options[nextIndex];
                item.onChange(nextOption.value);
              }
            } else if (item.type === 'input') {
              // 对于input类型，应该显示输入框让用户输入
              // 这里先调用onChange回调（如果有），实际应用中应该显示输入对话框
              if (item.onChange) {
                // 在实际应用中，这里应该显示一个输入对话框
                // 暂时保持原值不变
                item.onChange(item.value as string);
              }
            }
          })

          // 分隔线
          if (index < items.length - 1) {
            Divider()
              .strokeWidth(0.5)
              .color(this.theme === 'dark' ? '#2C2C2C' : '#E8E8E8')
              .margin({ left: 16, right: 16 })
          }
        }
      })
    }
    .width('100%')
  }

  private getOptionLabel(options: Array<SettingOption>, value: string): string {
    const option: SettingOption | undefined = options.find((opt: SettingOption) => opt.value === value);
    return option ? option.label : value;
  }

  // 构建各个设置区块的方法
  private buildBasicSettings(): SettingSectionItem[] {
    const languageOption: SettingOption[] = [
      { label: '简体中文', value: 'zh-CN' },
      { label: 'English', value: 'en-US' }
    ];

    const startupOption: SettingOption[] = [
      { label: '首页', value: 'home' },
      { label: '播放页', value: 'playdetail' }
    ];

    const items: SettingSectionItem[] = [];

    const langItem: SettingSectionItem = {
      type: 'select',
      title: '语言',
      value: this.language,
      options: languageOption,
      onChange: (value: string) => {
        this.language = value;
        this.saveSettings();
      }
    };
    items.push(langItem);

    const startupItem: SettingSectionItem = {
      type: 'select',
      title: '启动页面',
      value: this.startupPage,
      options: startupOption,
      onChange: (value: string) => {
        this.startupPage = value;
        this.saveSettings();
      }
    };
    items.push(startupItem);

    const exitItem: SettingSectionItem = {
      type: 'toggle',
      title: '退出确认对话框',
      value: this.showExitDialog,
      onChangeToggle: (value: boolean) => {
        this.showExitDialog = value;
        this.saveSettings();
      }
    };
    items.push(exitItem);

    return items;
  }

  private buildPlaybackSettings(): SettingSectionItem[] {
    const playModeOption: SettingOption[] = [
      { label: '列表循环', value: 'listLoop' },
      { label: '单曲循环', value: 'singleLoop' },
      { label: '随机播放', value: 'random' },
      { label: '顺序播放', value: 'sequential' }
    ];

    const items: SettingSectionItem[] = [];

    const autoPlayItem: SettingSectionItem = {
      type: 'toggle',
      title: '自动播放',
      value: this.autoPlay,
      onChangeToggle: (value: boolean) => {
        this.autoPlay = value;
        this.saveSettings();
      }
    };
    items.push(autoPlayItem);

    const highQualityItem: SettingSectionItem = {
      type: 'toggle',
      title: '高品质音乐',
      value: this.highQuality,
      onChangeToggle: (value: boolean) => {
        this.highQuality = value;
        this.saveSettings();
      }
    };
    items.push(highQualityItem);

    const playModeItem: SettingSectionItem = {
      type: 'select',
      title: '播放模式',
      value: this.playMode,
      options: playModeOption,
      onChange: (value: string) => {
        this.playMode = value;
        this.saveSettings();
      }
    };
    items.push(playModeItem);

    const volumeItem: SettingSectionItem = {
      type: 'input',
      title: '音量',
      value: this.volume.toString(),
      description: '默认音量大小 (0-100)',
      onChange: (value: string) => {
        const num = parseInt(value);
        if (!isNaN(num) && num >= 0 && num <= 100) {
          this.volume = num;
          this.saveSettings();
        }
      }
    };
    items.push(volumeItem);

    const timeoutItem: SettingSectionItem = {
      type: 'toggle',
      title: '定时退出',
      value: this.timeoutExit,
      onChangeToggle: (value: boolean) => {
        this.timeoutExit = value;
        this.saveSettings();
      }
    };
    items.push(timeoutItem);

    const timeoutMinutesItem: SettingSectionItem = {
      type: 'input',
      title: '定时退出时间',
      value: this.timeoutMinutes.toString(),
      description: '分钟 (仅当定时退出开启时生效)',
      onChange: (value: string) => {
        const num = parseInt(value);
        if (!isNaN(num) && num > 0) {
          this.timeoutMinutes = num;
          this.saveSettings();
        }
      }
    };
    items.push(timeoutMinutesItem);

    return items;
  }

  private buildSearchSettings(): SettingSectionItem[] {
    const sourceOption: SettingOption[] = [
      { label: '酷我', value: 'kw' },
      { label: 'QQ音乐', value: 'tx' },
      { label: '网易云', value: 'wy' },
      { label: '酷狗', value: 'kg' },
      { label: '咪咕', value: 'mg' }
    ];

    const items: SettingSectionItem[] = [];

    const sourceItem: SettingSectionItem = {
      type: 'select',
      title: '默认搜索源',
      value: this.searchSource,
      options: sourceOption,
      onChange: (value: string) => {
        this.searchSource = value;
        this.saveSettings();
      }
    };
    items.push(sourceItem);

    const hotSearchItem: SettingSectionItem = {
      type: 'toggle',
      title: '显示热搜',
      value: this.showHotSearch,
      onChangeToggle: (value: boolean) => {
        this.showHotSearch = value;
        this.saveSettings();
      }
    };
    items.push(hotSearchItem);

    const historyItem: SettingSectionItem = {
      type: 'input',
      title: '搜索历史数量',
      value: this.searchHistoryCount.toString(),
      description: '最大保存的搜索历史数量',
      onChange: (value: string) => {
        const num = parseInt(value);
        if (!isNaN(num) && num > 0) {
          this.searchHistoryCount = num;
          this.saveSettings();
        }
      }
    };
    items.push(historyItem);

    return items;
  }

  private buildListSettings(): SettingSectionItem[] {
    const locationOption: SettingOption[] = [
      { label: '添加到顶部', value: 'top' },
      { label: '添加到底部', value: 'bottom' }
    ];

    const items: SettingSectionItem[] = [];

    const locationItem: SettingSectionItem = {
      type: 'select',
      title: '添加歌曲位置',
      value: this.listAddMusicLocation,
      options: locationOption,
      onChange: (value: string) => {
        this.listAddMusicLocation = value;
        this.saveSettings();
      }
    };
    items.push(locationItem);

    const cleanItem: SettingSectionItem = {
      type: 'toggle',
      title: '自动清理已播放列表',
      value: this.autoCleanPlayedList,
      onChangeToggle: (value: boolean) => {
        this.autoCleanPlayedList = value;
        this.saveSettings();
      }
    };
    items.push(cleanItem);

    return items;
  }

  private buildBackupSettings(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];

    const backupItem: SettingSectionItem = {
      type: 'button',
      title: '备份数据',
      description: '备份歌单、设置等数据到文件',
      onClick: () => {
        this.backupData();
      }
    };
    items.push(backupItem);

    const restoreItem: SettingSectionItem = {
      type: 'button',
      title: '恢复数据',
      description: '从备份文件恢复数据',
      onClick: () => {
        this.restoreData();
      }
    };
    items.push(restoreItem);

    const exportItem: SettingSectionItem = {
      type: 'button',
      title: '导出歌单',
      description: '导出歌单为JSON文件',
      onClick: () => {
        this.exportPlaylists();
      }
    };
    items.push(exportItem);

    const importItem: SettingSectionItem = {
      type: 'button',
      title: '导入歌单',
      description: '从JSON文件导入歌单',
      onClick: () => {
        this.importPlaylists();
      }
    };
    items.push(importItem);

    const clearItem: SettingSectionItem = {
      type: 'button',
      title: '清除缓存',
      description: '清除应用缓存数据',
      onClick: () => {
        this.clearCache();
      }
    };
    items.push(clearItem);

    return items;
  }

  private buildSyncSettings(): SettingSectionItem[] {
    const syncModeOption: SettingOption[] = [
      { label: '客户端模式', value: 'client' },
      { label: '服务器模式', value: 'server' }
    ];

    const items: SettingSectionItem[] = [];

    const enableItem: SettingSectionItem = {
      type: 'toggle',
      title: '启用同步',
      value: this.syncEnable,
      onChangeToggle: (value: boolean) => {
        this.syncEnable = value;
        this.saveSettings();
      }
    };
    items.push(enableItem);

    const serverItem: SettingSectionItem = {
      type: 'input',
      title: '同步服务器地址',
      value: this.syncServer,
      description: '例如: http://192.168.1.100:9527',
      onChange: (value: string) => {
        this.syncServer = value;
        this.saveSettings();
      }
    };
    items.push(serverItem);

    const keyItem: SettingSectionItem = {
      type: 'input',
      title: '同步密钥',
      value: this.syncKey,
      description: '数据同步密钥',
      onChange: (value: string) => {
        this.syncKey = value;
        this.saveSettings();
      }
    };
    items.push(keyItem);

    const modeItem: SettingSectionItem = {
      type: 'select',
      title: '同步模式',
      value: 'client',
      options: syncModeOption,
      onChange: (value: string) => {
        hilog.info(0x0001, 'SettingView', 'Sync mode changed to: %{public}s', value);
      }
    };
    items.push(modeItem);

    const autoSyncItem: SettingSectionItem = {
      type: 'toggle',
      title: '自动同步',
      value: true,
      onChangeToggle: (value: boolean) => {
        hilog.info(0x0001, 'SettingView', 'Auto sync: %{public}s', value ? 'enabled' : 'disabled');
      }
    };
    items.push(autoSyncItem);

    const manualSyncItem: SettingSectionItem = {
      type: 'button',
      title: '立即同步',
      onClick: () => {
        hilog.info(0x0001, 'SettingView', 'Manual sync triggered');
      }
    };
    items.push(manualSyncItem);

    const historyItem: SettingSectionItem = {
      type: 'button',
      title: '同步历史',
      onClick: () => {
        hilog.info(0x0001, 'SettingView', 'Sync history clicked');
      }
    };
    items.push(historyItem);

    return items;
  }

  private buildAppearanceSettings(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];

    const darkModeItem: SettingSectionItem = {
      type: 'toggle',
      title: '深色模式',
      value: this.theme === 'dark',
      onChangeToggle: (value: boolean) => {
        this.theme = value ? 'dark' : 'light';
        this.saveThemeSetting();
      }
    };
    items.push(darkModeItem);

    const fontSizeItem: SettingSectionItem = {
      type: 'input',
      title: '字体大小',
      value: this.fontSize.toString(),
      description: '应用字体大小 (12-20)',
      onChange: (value: string) => {
        const num = parseInt(value);
        if (!isNaN(num) && num >= 12 && num <= 20) {
          this.fontSize = num;
          this.saveSettings();
        }
      }
    };
    items.push(fontSizeItem);

    const animationItem: SettingSectionItem = {
      type: 'toggle',
      title: '显示动画',
      value: this.showAnimation,
      onChangeToggle: (value: boolean) => {
        this.showAnimation = value;
        this.saveSettings();
      }
    };
    items.push(animationItem);

    return items;
  }

  private buildCustomSourceSettings(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];

    const importItem: SettingSectionItem = {
      type: 'button',
      title: '音源配置',
      description: '仅支持弹框配置：在线链接导入或本地JS文件导入',
      onClick: () => {
        this.openSourceImportDialog();
      }
    };
    items.push(importItem);

    return items;
  }

  private openSourceImportDialog(): void {
    this.sourceImportError = '';
    this.sourceImportLoading = false;
    this.showSourceImportDialog = true;
  }

  private closeSourceImportDialog(): void {
    if (this.sourceImportLoading) {
      return;
    }
    this.showSourceImportDialog = false;
    this.sourceImportError = '';
  }

  private showPluginLoadErrorDialog(message: string): void {
    const content = message.trim().length > 0 ? message : '未知错误';
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: '音源导入失败',
        message: content,
        buttons: [
          { text: '知道了', color: DesignTokens.accent() },
        ],
      });
    } catch (_e) {
      hilog.warn(DOMAIN, TAG, 'showPluginLoadErrorDialog fallback: %{public}s', content);
    }
  }

  private isValidSourceUrl(url: string): boolean {
    const value = url.trim();
    return /^https?:\/\/.+/i.test(value);
  }

  private async importSourceFromUrl(): Promise<void> {
    const url = this.sourceImportUrl.trim();
    if (!url) {
      this.sourceImportError = '请输入在线JS源链接';
      return;
    }
    if (!this.isValidSourceUrl(url)) {
      this.sourceImportError = '链接格式无效，请输入 http(s) 地址';
      return;
    }
    this.sourceImportLoading = true;
    this.sourceImportError = '';
    try {
      const ok = await loadCustomSource(url);
      if (ok) {
        this.showSourceImportDialog = false;
        this.showToast('音源导入成功');
      } else {
        const msg = '导入失败，请检查链接内容是否为可用JS插件';
        this.sourceImportError = msg;
        this.showPluginLoadErrorDialog(msg);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : JSON.stringify(err);
      this.sourceImportError = msg;
      this.showPluginLoadErrorDialog(msg);
    } finally {
      this.sourceImportLoading = false;
    }
  }

  private async importSourceFromLocalFile(): Promise<void> {
    this.sourceImportLoading = true;
    this.sourceImportError = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pickerOptions = new filePicker.DocumentSelectOptions();
      pickerOptions.fileSuffixFilters = ['.js'];
      const picker = new filePicker.DocumentViewPicker(context);
      const uris = await picker.select(pickerOptions);
      if (!uris || uris.length === 0) {
        this.showToast('已取消导入');
        return;
      }
      const selectedUri = uris[0];
      const ok = await loadCustomSource(selectedUri);
      if (ok) {
        this.showSourceImportDialog = false;
        this.showToast('本地音源导入成功');
      } else {
        const msg = '本地文件导入失败，请确认文件内容正确';
        this.sourceImportError = msg;
        this.showPluginLoadErrorDialog(msg);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : JSON.stringify(err);
      this.sourceImportError = msg;
      this.showPluginLoadErrorDialog(msg);
    } finally {
      this.sourceImportLoading = false;
    }
  }

  @Builder
  private buildSourceImportDialog() {
    if (this.showSourceImportDialog) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.35)')
          .onClick(() => {
            this.closeSourceImportDialog();
          })

        Column() {
          Row() {
            Text('导入音源')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor(DesignTokens.labelPrimary(this.theme))
            Blank()
              .layoutWeight(1)
            Stack() {
              Circle({ width: 30, height: 30 })
                .fill(DesignTokens.mutedFill(this.theme))
              Text('×')
                .fontSize(16)
                .fontColor(DesignTokens.labelSecondary(this.theme))
            }
            .onClick(() => {
              this.closeSourceImportDialog();
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          TextInput({ placeholder: '输入在线JS链接（https://...）', text: this.sourceImportUrl })
            .width('100%')
            .height(44)
            .fontSize(14)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .placeholderColor(DesignTokens.labelTertiary(this.theme))
            .backgroundColor(DesignTokens.mutedFill(this.theme))
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .margin({ top: 14 })
            .onChange((value: string) => {
              this.sourceImportUrl = value;
            })

          if (this.sourceImportError.length > 0) {
            Text(this.sourceImportError)
              .fontSize(12)
              .fontColor('#F44336')
              .width('100%')
              .margin({ top: 8 })
          }

          Row({ space: 10 }) {
            Button(this.sourceImportLoading ? '导入中…' : '导入在线链接')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor(DesignTokens.accent())
              .enabled(!this.sourceImportLoading)
              .onClick(() => {
                void this.importSourceFromUrl();
              })
            Button(this.sourceImportLoading ? '处理中…' : '选择本地文件')
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .backgroundColor(DesignTokens.mutedFill(this.theme))
              .enabled(!this.sourceImportLoading)
              .onClick(() => {
                void this.importSourceFromLocalFile();
              })
          }
          .width('100%')
          .margin({ top: 16 })

          Text('支持两种方式：在线JS链接导入 / 文件管理器选择本地JS文件')
            .fontSize(11)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .width('100%')
            .margin({ top: 10 })
        }
        .width('88%')
        .padding(18)
        .backgroundColor(DesignTokens.card(this.theme))
        .borderRadius(16)
        .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
        .onClick(() => {})
      }
      .width('100%')
      .height('100%')
    }
  }

  private buildAboutSettings(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];

    const aboutItem: SettingSectionItem = {
      type: 'button',
      title: '关于 LX Music',
      onClick: () => {
        navigationService.navigateTo(RouteName.ABOUT);
      }
    };
    items.push(aboutItem);

    const versionItem: SettingSectionItem = {
      type: 'button',
      title: '版本信息',
      onClick: () => {
        hilog.info(DOMAIN, TAG, 'Version info clicked');
      }
    };
    items.push(versionItem);

    return items;
  }

  // 备份数据
  async backupData(): Promise<void> {
    try {
      hilog.info(0x0001, 'SettingView', 'Starting data backup...');

      // 设置备份服务上下文
      const context = this.getUIContext().getHostContext();
      if (context) {
        backupService.setContext(context as common.UIAbilityContext);
      }

      // 创建备份
      const backupFile = await backupService.createBackup(BackupDataType.ALL);

      if (backupFile) {
        hilog.info(0x0001, 'SettingView', 'Data backup completed: %{public}s', backupFile.fileName);
        // 这里可以显示成功提示
        // 例如: this.showToast('备份创建成功');
      } else {
        hilog.error(0x0001, 'SettingView', 'Data backup failed: backup file is null');
        // 这里可以显示错误提示
        // 例如: this.showToast('备份创建失败');
      }
    } catch (err) {
      hilog.error(0x0001, 'SettingView', 'Data backup failed: %{public}s', JSON.stringify(err));
      // 这里可以显示错误提示
      // 例如: this.showToast('备份创建失败: ' + (err instanceof Error ? err.message : '未知错误'));
    }
  }

  // 恢复数据
  async restoreData(): Promise<void> {
    try {
      hilog.info(0x0001, 'SettingView', 'Starting data restore...');

      // 设置备份服务上下文
      const context = this.getUIContext().getHostContext();
      if (context) {
        backupService.setContext(context as common.UIAbilityContext);
      }

      // 选择备份文件
      const backupFile = await backupService.selectBackupFile();

      if (!backupFile) {
        hilog.info(0x0001, 'SettingView', 'Data restore cancelled: no file selected');
        // 这里可以显示取消提示
        // 例如: this.showToast('已取消恢复');
        return;
      }

      // 确认恢复操作
      // 在实际应用中，这里应该显示确认对话框
      // const confirmed = await this.showConfirmDialog('确认恢复', `确定要恢复备份文件 ${backupFile.fileName} 吗？`);
      // if (!confirmed) return;

      // 恢复备份
      const success = await backupService.restoreBackup(backupFile);

      if (success) {
        hilog.info(0x0001, 'SettingView', 'Data restore completed: %{public}s', backupFile.fileName);
        // 这里可以显示成功提示
        // 例如: this.showToast('数据恢复成功');

        // 重新加载应用数据
        // this.reloadAppData();
      } else {
        hilog.error(0x0001, 'SettingView', 'Data restore failed');
        // 这里可以显示错误提示
        // 例如: this.showToast('数据恢复失败');
      }
    } catch (err) {
      hilog.error(0x0001, 'SettingView', 'Data restore failed: %{public}s', JSON.stringify(err));
      // 这里可以显示错误提示
      // 例如: this.showToast('数据恢复失败: ' + (err instanceof Error ? err.message : '未知错误'));
    }
  }

  // 导出歌单
  async exportPlaylists(): Promise<void> {
    try {
      hilog.info(0x0001, 'SettingView', 'Exporting playlists...');

      // 1. 获取所有歌单数据
      const playlistsData = await this.collectPlaylistsData();
      
      // 2. 转换为JSON格式
      const jsonData = JSON.stringify(playlistsData, null, 2);
      
      // 3. 保存到文件
      const fileName = `lxmusic-playlists-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
      const filePath = `/storage/emulated/0/Download/${fileName}`;
      
      // 确保目录存在
      await this.ensureDirectoryExists('/storage/emulated/0/Download');
      
      // 写入文件
      const file = await fs.open(filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
      try {
        const data = utf8Encode(jsonData);
        await fs.write(file.fd, data);
        await fs.fsync(file.fd);
        hilog.info(0x0001, 'SettingView', 'Playlists exported to: %{public}s', filePath);
        
        // 显示成功提示
        this.showToast('歌单导出成功: ' + fileName);
      } finally {
        await fs.close(file.fd);
      }

    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(0x0001, 'SettingView', 'Playlists export failed: %{public}s', errorMsg);
      this.showToast('歌单导出失败: ' + errorMsg);
    }
  }

  // 收集歌单数据
  private async collectPlaylistsData(): Promise<PlaylistsExportRoot> {
    const playlistsData: PlaylistsExportRoot = {
      appVersion: '1.0.0',
      exportTime: new Date().toISOString(),
      playlists: []
    };

    try {
      const defaultList: ExportedPlaylistRow = {
        id: LIST_IDS.DEFAULT,
        name: '默认列表',
        type: 'default',
        musicCount: getDefaultList().length,
        musicList: getDefaultList()
      };
      
      const loveList: ExportedPlaylistRow = {
        id: LIST_IDS.LOVE,
        name: '我喜欢',
        type: 'love',
        musicCount: getLoveList().length,
        musicList: getLoveList()
      };
      
      const userLists = getUserList();
      const rows: ExportedPlaylistRow[] = [defaultList, loveList];
      for (let i = 0; i < userLists.length; i++) {
        const list = userLists[i];
        rows.push({
          id: list.id,
          name: list.name,
          type: 'user',
          source: list.source,
          desc: list.desc,
          pic: list.pic,
          count: list.count,
          createTime: list.createTime,
          updateTime: list.updateTime
        });
      }
      playlistsData.playlists = rows;
      
      hilog.info(0x0001, 'SettingView', 'Collected %{public}d playlists', playlistsData.playlists.length);
    } catch (err) {
      hilog.error(0x0001, 'SettingView', 'Failed to collect playlist data: %{public}s', JSON.stringify(err));
    }
    
    return playlistsData;
  }

  // 确保目录存在
  private async ensureDirectoryExists(dirPath: string): Promise<void> {
    try {
      await fs.access(dirPath);
    } catch (err) {
      try {
        await fs.mkdir(dirPath, true);
      } catch (mkdirErr) {
        hilog.error(0x0001, 'SettingView', 'ensureDirectoryExists mkdir failed: %{public}s', JSON.stringify(mkdirErr));
        const msg = mkdirErr instanceof Error ? mkdirErr.message : JSON.stringify(mkdirErr);
        throw new Error(msg);
      }
    }
  }

  // 显示提示
  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 2200,
      });
    } catch (_e) {
      hilog.info(0x0001, 'SettingView', 'Toast: %{public}s', message);
    }
  }

  // 导入歌单
  async importPlaylists(): Promise<void> {
    try {
      hilog.info(0x0001, 'SettingView', 'Importing playlists...');

      // 1. 选择JSON文件
      const filePath = await this.selectJsonFile();
      if (!filePath) {
        this.showToast('已取消导入');
        return;
      }
      
      // 2. 读取文件内容
      const file = await fs.open(filePath, fs.OpenMode.READ_ONLY);
      try {
        const stat = await fs.stat(file.fd);
        const buffer = new ArrayBuffer(stat.size);
        await fs.read(file.fd, buffer);
        
        const jsonData = utf8Decode(new Uint8Array(buffer));
        
        // 3. 解析歌单数据
        const playlistsData = JSON.parse(jsonData) as Record<string, Object>;
        
        // 4. 验证数据格式
        if (!this.validatePlaylistsData(playlistsData)) {
          this.showToast('文件格式无效');
          return;
        }
        
        // 5. 导入到应用
        const importCount = await this.importPlaylistsData(playlistsData);
        
        hilog.info(0x0001, 'SettingView', 'Playlists import completed: %{public}d playlists imported', importCount);
        this.showToast(`成功导入 ${importCount} 个歌单`);
        
      } finally {
        await fs.close(file.fd);
      }
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(0x0001, 'SettingView', 'Playlists import failed: %{public}s', errorMsg);
      this.showToast('歌单导入失败: ' + errorMsg);
    }
  }

  // 选择JSON文件
  private async selectJsonFile(): Promise<string | null> {
    try {
      // 在实际应用中，这里应该使用文件选择器
      // 暂时返回固定路径用于测试
      const testFilePath = '/storage/emulated/0/Download/lxmusic-playlists-test.json';
      
      // 检查文件是否存在
      try {
        await fs.access(testFilePath);
        return testFilePath;
      } catch (err) {
        // 文件不存在，创建测试文件
        const testPlaylistRow: ExportedPlaylistRow = {
          id: 'test-import-1',
          name: '测试导入歌单1',
          type: 'user',
          source: 'import',
          desc: '从文件导入的测试歌单',
          count: 0,
          createTime: Date.now(),
          updateTime: Date.now()
        };
        const testData: PlaylistsExportRoot = {
          appVersion: '1.0.0',
          exportTime: new Date().toISOString(),
          playlists: [testPlaylistRow]
        };
        
        const file = await fs.open(testFilePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
        try {
          const data = utf8Encode(JSON.stringify(testData, null, 2));
          await fs.write(file.fd, data);
          await fs.fsync(file.fd);
        } finally {
          await fs.close(file.fd);
        }
        
        return testFilePath;
      }
    } catch (err) {
      hilog.error(0x0001, 'SettingView', 'Failed to select file: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  // 验证歌单数据格式
  private validatePlaylistsData(data: Record<string, Object>): boolean {
    try {
      if (!data.appVersion || !data.exportTime || !Array.isArray(data.playlists)) {
        return false;
      }
      
      // 验证每个歌单的基本结构
      for (const playlist of data.playlists as Array<Record<string, Object>>) {
        if (!playlist.id || !playlist.name || !playlist.type) {
          return false;
        }
      }
      
      return true;
    } catch (err) {
      return false;
    }
  }

  // 导入歌单数据
  private async importPlaylistsData(data: Record<string, Object>): Promise<number> {
    let importCount = 0;
    
    try {
      const playlists = data.playlists as Array<Record<string, Object>>;
      
      for (let p = 0; p < playlists.length; p++) {
        const playlist = playlists[p];
        if (playlist.type === 'user') {
          try {
            const newList = await createUserList(playlist.name as string);
            const listId = newList.id;
            
            if (Array.isArray(playlist.musicList)) {
              const ml = playlist.musicList as Array<Record<string, Object>>;
              for (let m = 0; m < ml.length; m++) {
                await addMusicToList(listId, musicItemFromPlainObject(ml[m] as Object));
              }
            }
            
            importCount++;
            hilog.info(0x0001, 'SettingView', 'Imported playlist: %{public}s', playlist.name as string);
          } catch (err) {
            hilog.error(0x0001, 'SettingView', 'Failed to import playlist %{public}s: %{public}s',
              playlist.name as string, JSON.stringify(err));
          }
        }
      }
    } catch (err) {
      hilog.error(0x0001, 'SettingView', 'Failed to import playlists data: %{public}s', JSON.stringify(err));
    }
    
    return importCount;
  }

  // 清除缓存
  async clearCache(): Promise<void> {
    try {
      hilog.info(0x0001, 'SettingView', 'Clearing cache...');

      let clearedItems = 0;
      
      // 1. 清除图片缓存目录
      const imageCacheDir = '/storage/emulated/0/Android/data/com.example.lxmusic/cache/images';
      clearedItems += await this.clearDirectory(imageCacheDir);
      
      // 2. 清除临时文件目录
      const tempDir = '/storage/emulated/0/Android/data/com.example.lxmusic/cache/temp';
      clearedItems += await this.clearDirectory(tempDir);
      
      // 3. 清除搜索历史
      await this.clearSearchHistory();
      clearedItems++;
      
      // 4. 清除播放历史
      await this.clearPlayHistory();
      clearedItems++;

      hilog.info(0x0001, 'SettingView', 'Cache cleared: %{public}d items', clearedItems);
      this.showToast(`已清除 ${clearedItems} 项缓存数据`);
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(0x0001, 'SettingView', 'Cache clear failed: %{public}s', errorMsg);
      this.showToast('清除缓存失败: ' + errorMsg);
    }
  }

  // 清除目录内容
  private async clearDirectory(dirPath: string): Promise<number> {
    let clearedCount = 0;
    
    try {
      // 检查目录是否存在
      await fs.access(dirPath);
      
      const entries: string[] = fs.listFileSync(dirPath);
      for (let i = 0; i < entries.length; i++) {
        const name = entries[i];
        const fullPath = `${dirPath}/${name}`;
        const st = await fs.stat(fullPath);
        if (st.isFile()) {
          await fs.unlink(fullPath);
          clearedCount++;
          hilog.debug(0x0001, 'SettingView', 'Deleted file: %{public}s', name);
        } else if (st.isDirectory()) {
          clearedCount += await this.clearDirectory(fullPath);
          await fs.rmdir(fullPath);
        }
      }
      
    } catch (err) {
      // 目录不存在或无法访问，忽略错误
      hilog.debug(0x0001, 'SettingView', 'Directory not found or inaccessible: %{public}s', dirPath);
    }
    
    return clearedCount;
  }

  // 清除搜索历史
  private async clearSearchHistory(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'music_settings');
      
      // 清除搜索历史
      await pref.delete('searchHistory');
      await pref.flush();
      
      hilog.info(0x0001, 'SettingView', 'Search history cleared');
    } catch (err) {
      hilog.error(0x0001, 'SettingView', 'Failed to clear search history: %{public}s', JSON.stringify(err));
    }
  }

  // 清除播放历史
  private async clearPlayHistory(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'music_settings');
      
      // 清除播放历史
      await pref.delete('playHistory');
      await pref.flush();
      await clearPlayHistoryStore();
      
      hilog.info(0x0001, 'SettingView', 'Play history cleared');
    } catch (err) {
      hilog.error(0x0001, 'SettingView', 'Failed to clear play history: %{public}s', JSON.stringify(err));
    }
  }
}
