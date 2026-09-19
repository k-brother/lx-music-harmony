// Setting 视图 - 对应 src/screens/Home/Views/Setting/index.tsx
// 设置视图 - 完整版

import { navigationService, RouteName } from '../../service/NavigationService';
import { common } from '@kit.AbilityKit';
import { Environment } from '@kit.CoreFileKit';
import hilog from '@ohos.hilog';
import { DesignTokens } from '../../theme/DesignTokens';
import { backupService, BackupDataType } from '../../service/BackupService';
import fs from '@ohos.file.fs';
import filePicker from '@ohos.file.picker';
import { utf8Encode, utf8Decode } from '../../utils/TextCodec';
import { musicItemFromPlainObject } from '../../core/list/PlaylistRecordMapper';
import {
  getUserList,
  initListService,
  getDefaultList,
  getLoveList,
  getUserListMusic,
  LIST_IDS,
  createUserList,
  addMusicToList,
  MusicItem
} from '../../service/ListService';
import { clearPlayHistory as clearPlayHistoryStore } from '../../service/PlayHistoryService';
import { clearHistoryList as clearSearchHistoryList } from '../../core/search/search';
import { loadCustomSource, setMaxConcurrentDownloads } from '../../core/music/MusicFeatureEntry';
import { syncService, SyncMode } from '../../service/SyncService';
import { playerService } from '../../service/PlayerService';
import { settingsService } from '../../service/SettingsService';
import { sleepTimerService } from '../../service/SleepTimerService';
import { DesktopLyricManager } from '../../components/common/DesktopLyric';
import type { DesktopLyricPosition, StartupPage, PlayMode, AddMusicLocation } from '../../service/SettingsService';
import { t, tf, setLanguage } from '../../service/LocalizationService';
import { applyThemeById, getAllThemes } from '../../service/ThemeService';
import { DEFAULT_THEME_ID } from '../../core/theme/themes';
import type { ThemeItem } from '../../types/ThemeTypes';

const TAG = 'SETTING';
const DOMAIN = 0x0001;
const DEFAULT_DOWNLOAD_DIR = '/storage/Users/currentUser/Download';
/** 内置深色主题 id（对应 core/theme/themes 中的 black） */
const DARK_THEME_ID = 'black';

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


interface ActionMenuResult {
  index: number;
}

interface ActionMenuButton {
  text: string;
  color: string;
}

@Component
export struct SettingView {
  @StorageProp('theme') theme: string = 'light';

  // 基础设置
  @StorageLink('language') language: string = 'zh-CN';
  @State startupPage: string = 'home';
  @State showExitDialog: boolean = true;

  // 播放设置
  @State autoPlay: boolean = false;
  @State highQuality: boolean = true;
  @State playMode: string = 'listLoop';
  @State volume: number = 80;
  @State timeoutExit: boolean = false;
  @State timeoutMinutes: number = 30;
  @State showDesktopLyric: boolean = true;
  @State desktopLyricBgAlpha: number = 0;
  @State desktopLyricFontSize: number = 18;
  @State desktopLyricShowNext: boolean = true;
  @State desktopLyricLocked: boolean = false;

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
  @State syncMode: string = 'client';
  @State syncAutoSync: boolean = true;

  // 外观设置
  @State fontSize: number = 14;
  @State showAnimation: boolean = true;
  @State themeId: string = DEFAULT_THEME_ID;
  @State showSourceImportDialog: boolean = false;
  @State sourceImportUrl: string = '';
  @State sourceImportLoading: boolean = false;
  @State sourceImportError: string = '';
  @State downloadPath: string = '';
  @State autoStartDownload: boolean = true;
  @State maxConcurrentDownloads: number = 1;
  // 输入对话框
  @State showInputDialog: boolean = false;
  @State inputDialogTitle: string = '';
  @State inputDialogValue: string = '';
  private inputDialogCallback: ((value: string) => void) | null = null;

  // 选择对话框
  @State showSelectDialog: boolean = false;
  @State selectDialogTitle: string = '';
  @State selectDialogOptions: SettingOption[] = [];
  @State selectDialogValue: string = '';
  private selectDialogCallback: ((value: string) => void) | null = null;

  // 确认对话框
  @State showConfirmOverlay: boolean = false;
  @State confirmTitle: string = '';
  @State confirmMessage: string = '';
  private confirmResolve: ((value: boolean) => void) | null = null;

  aboutToAppear() {
    void this.loadSettings();
    void this.loadDownloadSettings();
  }

  /** 从唯一的设置服务读取当前配置 */
  loadSettings(): void {
    const settings = settingsService.get();

    // 基础设置
    this.language = settings.language;
    this.startupPage = settings.startupPage;
    this.showExitDialog = settings.showExitDialog;

    // 播放设置
    this.autoPlay = settings.autoPlay;
    this.highQuality = settings.highQuality;
    this.playMode = settings.playMode;
    this.volume = settings.volume;
    this.timeoutExit = settings.sleepTimerEnabled;
    this.timeoutMinutes = settings.sleepTimerMinutes;
    this.showDesktopLyric = settings.showDesktopLyric;
    this.desktopLyricBgAlpha = settings.desktopLyricBgAlpha;
    this.desktopLyricFontSize = settings.desktopLyricFontSize;
    this.desktopLyricShowNext = settings.desktopLyricShowNext;
    this.desktopLyricLocked = settings.desktopLyricLocked;

    // 搜索设置
    this.searchSource = settings.searchSource;
    this.showHotSearch = settings.showHotSearch;
    this.searchHistoryCount = settings.searchHistoryCount;

    // 列表设置
    this.listAddMusicLocation = settings.addMusicLocation;
    this.autoCleanPlayedList = settings.autoCleanPlayedList;

    // 同步设置
    this.syncEnable = settings.syncEnabled;
    this.syncServer = settings.syncServer;
    this.syncKey = settings.syncKey;
    this.syncMode = settings.syncMode;
    this.syncAutoSync = settings.syncAutoSync;

    // 外观设置
    this.fontSize = settings.fontSize;
    this.showAnimation = settings.showAnimation;
    this.themeId = settings.themeId;

    hilog.info(DOMAIN, TAG, 'Settings loaded from SettingsService');
  }

  /** 把界面上的当前值统一写回设置服务（只写变化项） */
  async saveSettings(): Promise<void> {
    try {
      await settingsService.update({
        language: this.language,
        startupPage: this.startupPage as StartupPage,
        showExitDialog: this.showExitDialog,
        themeMode: this.theme === 'dark' ? 'dark' : 'light',
        autoPlay: this.autoPlay,
        highQuality: this.highQuality,
        playMode: this.playMode as PlayMode,
        volume: this.volume,
        sleepTimerEnabled: this.timeoutExit,
        sleepTimerMinutes: this.timeoutMinutes,
        showDesktopLyric: this.showDesktopLyric,
        desktopLyricBgAlpha: this.desktopLyricBgAlpha,
        desktopLyricFontSize: this.desktopLyricFontSize,
        desktopLyricShowNext: this.desktopLyricShowNext,
        desktopLyricLocked: this.desktopLyricLocked,
        searchSource: this.searchSource,
        showHotSearch: this.showHotSearch,
        searchHistoryCount: this.searchHistoryCount,
        addMusicLocation: this.listAddMusicLocation as AddMusicLocation,
        autoCleanPlayedList: this.autoCleanPlayedList,
        fontSize: this.fontSize,
        showAnimation: this.showAnimation,
      });
      hilog.info(DOMAIN, TAG, 'Settings saved');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save settings: %{public}s', JSON.stringify(err));
    }
  }

  async loadDownloadSettings() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const settings = settingsService.get();
      const fallbackPath = this.getDefaultDownloadPath(context);
      const storedPath = (settings.downloadPath || '').trim();
      // 只接受 docs:// URI 格式的路径，否则使用默认
      this.downloadPath = (!storedPath || storedPath.length === 0) ? fallbackPath : storedPath;
      if (this.downloadPath !== storedPath) {
        await settingsService.update({ downloadPath: this.downloadPath });
      }
      this.autoStartDownload = settings.autoStartDownload;
      this.maxConcurrentDownloads = settings.maxConcurrentDownloads;
      setMaxConcurrentDownloads(this.maxConcurrentDownloads);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to load download settings: %{public}s', JSON.stringify(err));
    }
  }

  async saveDownloadSettings() {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (!this.downloadPath || this.downloadPath.trim().length === 0) {
        this.downloadPath = this.getDefaultDownloadPath(context);
      }
      await settingsService.update({
        downloadPath: this.downloadPath,
        autoStartDownload: this.autoStartDownload,
        maxConcurrentDownloads: this.maxConcurrentDownloads,
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save download settings: %{public}s', JSON.stringify(err));
    }
  }

  private getDefaultDownloadPath(_context: common.UIAbilityContext): string {
    // 返回“我的手机/Download”的系统真实路径
    try {
      let systemDir: string = '';
      if (canIUse("SystemCapability.FileManagement.File.Environment.FolderObtain")) {
        systemDir = Environment.getUserDownloadDir();
      }
      if (systemDir && systemDir.trim().length > 0) {
        return systemDir;
      }
    } catch (_err) {
      // ignore and fallback
    }
    return DEFAULT_DOWNLOAD_DIR;
  }

  /** 应用主题（同时持久化主题 id 与明暗模式） */
  private async applyTheme(themeId: string): Promise<void> {
    try {
      await applyThemeById(themeId);
      const isDark = AppStorage.get<string>('theme') === 'dark';
      this.themeId = themeId;
      await settingsService.update({
        themeId: themeId,
        themeMode: isDark ? 'dark' : 'light',
      });
      hilog.info(DOMAIN, TAG, 'Theme applied: %{public}s', themeId);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to apply theme %{public}s: %{public}s', themeId, JSON.stringify(err));
    }
  }

  /** 切换深色/浅色模式（映射到对应内置主题） */
  private async setDarkMode(enabled: boolean): Promise<void> {
    const targetThemeId = enabled ? DARK_THEME_ID : DEFAULT_THEME_ID;
    await this.applyTheme(targetThemeId);
  }

  /** 主题 id -> 是否深色主题 */
  private getThemeIsDark(themeId: string): boolean {
    const list: ThemeItem[] = getAllThemes();
    for (let i = 0; i < list.length; i++) {
      if (list[i].id === themeId) {
        return list[i].isDark;
      }
    }
    return false;
  }



  build() {
    Stack() {
      Scroll() {
        Column() {
          // 基础设置
          this.buildSettingSection(t('settings_basic'), this.buildBasicSettings())

          // 播放设置
          this.buildSettingSection(t('settings_playback'), this.buildPlaybackSettings())

          // 下载设置
          this.buildSettingSection(t('download_settings'), this.buildDownloadSettings())

          // 搜索设置
          this.buildSettingSection(t('settings_search'), this.buildSearchSettings())

          // 列表设置
          this.buildSettingSection(t('settings_list'), this.buildListSettings())

          // 备份与恢复
          this.buildSettingSection(t('settings_backup'), this.buildBackupSettings())

          // 同步设置
          this.buildSettingSection(t('settings_sync'), this.buildSyncSettings())

          // 外观设置
          this.buildSettingSection(t('settings_appearance'), this.buildAppearanceSettings())

          // 自定义源设置
          this.buildSettingSection(t('settings_custom_source'), this.buildCustomSourceSettings())

          // 关于
          this.buildSettingSection(t('settings_about'), this.buildAboutSettings())
        }
        .width('100%')
        .padding({ bottom: 20 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(DesignTokens.pageBg(this.theme))

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
        .fontColor(DesignTokens.labelTertiary(this.theme))
        .padding({ left: 16, top: 20, bottom: 8 })
        .width('100%')
        .backgroundColor(DesignTokens.pageBg(this.theme))

      // 设置项
      ForEach(items, (item: SettingSectionItem, index: number) => {
        Column() {
          Row() {
            Column() {
              Text(item.title)
                .fontSize(15)
                .fontColor(DesignTokens.labelPrimary(this.theme))
              if (item.description) {
                Text(item.description)
                  .fontSize(11)
                  .fontColor(DesignTokens.labelTertiary(this.theme))
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
                .fontColor(DesignTokens.labelSecondary(this.theme))
              Image($r('sys.symbol.chevron_right'))
                .width(16)
                .height(16)
                .fillColor(DesignTokens.labelSecondary(this.theme))
                .margin({ left: 8 })
            } else if (item.type === 'button') {
              Image($r('sys.symbol.chevron_right'))
                .width(16)
                .height(16)
                .fillColor(DesignTokens.labelSecondary(this.theme))
            } else if (item.type === 'input') {
              Text(item.value as string)
                .fontSize(14)
                .fontColor(DesignTokens.labelSecondary(this.theme))
                .maxLines(1)
            }
          }
          .width('100%')
          .height(item.description ? 56 : 50)
          .padding({ left: 16, right: 16 })
        .backgroundColor(DesignTokens.card(this.theme))
          .onClick(() => {
            if (item.type === 'button') {
              if (item.onClick) {
                item.onClick();
              }
            } else if (item.type === 'select') {
              if (item.options && item.options.length > 0 && item.onChange) {
                this.selectDialogTitle = item.title;
                this.selectDialogOptions = item.options;
                this.selectDialogValue = item.value as string;
                this.selectDialogCallback = item.onChange;
                this.showSelectDialog = true;
              }
            } else if (item.type === 'input') {
              if (item.onChange) {
                this.inputDialogTitle = item.title;
                this.inputDialogValue = item.value as string;
                this.inputDialogCallback = item.onChange;
                this.showInputDialog = true;
              }
            }
          })

          // 分隔线
          if (index < items.length - 1) {
            Divider()
              .strokeWidth(0.5)
              .color(DesignTokens.cardBorder(this.theme))
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
      { label: t('songlist_title'), value: 'home' },
      { label: t('player_title'), value: 'playdetail' }
    ];

    const items: SettingSectionItem[] = [];

    const langItem: SettingSectionItem = {
      type: 'select',
      title: t('settings_language'),
      value: this.language,
      options: languageOption,
      onChange: (value: string) => {
        setLanguage(value);
        this.language = value;
        this.saveSettings().then(() => {
          hilog.info(0x0001, 'SettingView', 'Language saved to prefs: %{public}s', value);
        });
        this.showToast(value === 'zh-CN' ? t('toast_lang_zh') : 'Switched to English');
        // pop 回首页触发 HomePage 重新渲染
        navigationService.backTo(RouteName.HOME);
      }
    };
    items.push(langItem);

    const startupItem: SettingSectionItem = {
      type: 'select',
      title: t('settings_startup_page'),
      value: this.startupPage,
      options: startupOption,
      onChange: (value: string) => {
        this.startupPage = value;
        AppStorage.setOrCreate('startupPage', value);
        this.saveSettings();
      }
    };
    items.push(startupItem);

    const exitItem: SettingSectionItem = {
      type: 'toggle',
      title: t('settings_exit_confirm'),
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
      { label: t('mode_list_loop'), value: 'listLoop' },
      { label: t('mode_single_loop'), value: 'singleLoop' },
      { label: t('mode_random'), value: 'random' },
      { label: t('mode_sequential'), value: 'sequential' }
    ];

    const items: SettingSectionItem[] = [];

    const autoPlayItem: SettingSectionItem = {
      type: 'toggle',
      title: t('settings_auto_play'),
      value: this.autoPlay,
      onChangeToggle: (value: boolean) => {
        this.autoPlay = value;
        AppStorage.setOrCreate('autoPlay', value);
        this.saveSettings();
      }
    };
    items.push(autoPlayItem);

    const highQualityItem: SettingSectionItem = {
      type: 'toggle',
      title: t('settings_high_quality'),
      value: this.highQuality,
      onChangeToggle: (value: boolean) => {
        this.highQuality = value;
        AppStorage.setOrCreate('highQuality', value);
        this.saveSettings();
      }
    };
    items.push(highQualityItem);

    const playModeItem: SettingSectionItem = {
      type: 'select',
      title: t('settings_play_mode'),
      value: this.playMode,
      options: playModeOption,
      onChange: (value: string) => {
        this.playMode = value;
        playerService.setPlayMode(value as 'listLoop' | 'singleLoop' | 'random' | 'sequential');
        this.saveSettings();
        this.showToast(t('toast_mode_changed'));
      }
    };
    items.push(playModeItem);

    const volumeItem: SettingSectionItem = {
      type: 'input',
      title: t('settings_volume'),
      value: this.volume.toString(),
      description: t('settings_volume_desc'),
      onChange: (value: string) => {
        const num = parseInt(value);
        if (!isNaN(num) && num >= 0 && num <= 100) {
          this.volume = num;
          playerService.setVolume(num / 100).catch((err: Error) => {
            hilog.warn(0x0001, 'SettingView', 'setVolume failed: %{public}s', err.message);
          });
          this.saveSettings();
          this.showToast(`${t('toast_volume_set')} ${num}`);
        }
      }
    };
    items.push(volumeItem);

    const timeoutItem: SettingSectionItem = {
      type: 'toggle',
      title: t('settings_sleep_timer'),
      value: this.timeoutExit,
      onChangeToggle: (value: boolean) => {
        this.timeoutExit = value;
        this.saveSettings();
        if (value) {
          sleepTimerService.start(this.timeoutMinutes);
          this.showToast(`${t('toast_sleep_set')} ${this.timeoutMinutes} ${t('toast_sleep_start')}`);
        } else {
          sleepTimerService.stop();
          this.showToast(t('toast_sleep_cancel'));
        }
      }
    };
    items.push(timeoutItem);

    const timeoutMinutesItem: SettingSectionItem = {
      type: 'input',
      title: t('settings_sleep_minutes'),
      value: this.timeoutMinutes.toString(),
      description: t('settings_sleep_minutes_desc'),
      onChange: (value: string) => {
        const num = parseInt(value);
        if (!isNaN(num) && num > 0) {
          this.timeoutMinutes = num;
          this.saveSettings();
          sleepTimerService.setMinutes(num);
          this.showToast(`${t('toast_sleep_set')} ${num} ${t('settings_sleep_minutes')}`);
        }
      }
    };
    items.push(timeoutMinutesItem);

    const desktopLyricItem: SettingSectionItem = {
      type: 'toggle',
      title: t('desktop_lyric'),
      description: t('desktop_lyric_desc'),
      value: this.showDesktopLyric,
      onChangeToggle: (value: boolean) => {
        this.showDesktopLyric = value;
        this.saveSettings();
        // 立即生效：开启/关闭桌面歌词子窗口
        void DesktopLyricManager.setEnabled(value);
        this.showToast(value ? t('toast_desktop_on') : t('toast_desktop_off'));
      }
    };
    items.push(desktopLyricItem);

    const lyricPosOption: SettingOption[] = [
      { label: t('lyric_pos_top'), value: 'top' },
      { label: t('lyric_pos_middle'), value: 'middle' },
      { label: t('lyric_pos_bottom'), value: 'bottom' },
    ];
    const lyricPosItem: SettingSectionItem = {
      type: 'select',
      title: t('lyric_pos_title'),
      value: AppStorage.get('desktopLyricPosition') as string || 'top',
      options: lyricPosOption,
      onChange: (value: string) => {
        void settingsService.update({ desktopLyricPosition: value as DesktopLyricPosition });
        DesktopLyricManager.applyPosition(value as DesktopLyricPosition);
        this.showToast(`${t('lyric_pos_title')}: ${this.getOptionLabel(lyricPosOption, value)}`);
      }
    };
    items.push(lyricPosItem);

    const lyricColorOption: SettingOption[] = [
      { label: t('lyric_color_white'), value: '#FFFFFF' },
      { label: t('lyric_color_green'), value: '#4CAF50' },
      { label: t('lyric_color_blue'), value: '#42A5F5' },
      { label: t('lyric_color_pink'), value: '#EC407A' },
      { label: t('lyric_color_orange'), value: '#FF9800' },
    ];
    const lyricColorItem: SettingSectionItem = {
      type: 'select',
      title: t('lyric_color_title'),
      value: AppStorage.get('desktopLyricColor') as string || '#FFFFFF',
      options: lyricColorOption,
      onChange: (value: string) => {
        void settingsService.update({ desktopLyricColor: value });
        this.showToast(t('lyric_color_updated'));
      }
    };
    items.push(lyricColorItem);

    // 背景不透明度：0 = 完全透明的"浮字"效果（默认），调高则更接近纯色底
    const lyricBgOption: SettingOption[] = [
      { label: t('lyric_bg_transparent'), value: '0' },
      { label: t('lyric_bg_light'), value: '30' },
      { label: t('lyric_bg_medium'), value: '55' },
      { label: t('lyric_bg_solid'), value: '85' },
    ];
    const lyricBgItem: SettingSectionItem = {
      type: 'select',
      title: t('lyric_bg_title'),
      value: this.desktopLyricBgAlpha.toString(),
      options: lyricBgOption,
      onChange: (value: string) => {
        const alpha = parseInt(value);
        if (!isNaN(alpha)) {
          this.desktopLyricBgAlpha = alpha;
          void settingsService.update({ desktopLyricBgAlpha: alpha });
        }
      }
    };
    items.push(lyricBgItem);

    const lyricSizeOption: SettingOption[] = [
      { label: t('lyric_size_small'), value: '14' },
      { label: t('lyric_size_normal'), value: '18' },
      { label: t('lyric_size_large'), value: '22' },
      { label: t('lyric_size_xlarge'), value: '26' },
    ];
    const lyricSizeItem: SettingSectionItem = {
      type: 'select',
      title: t('lyric_size_title'),
      value: this.desktopLyricFontSize.toString(),
      options: lyricSizeOption,
      onChange: (value: string) => {
        const size = parseInt(value);
        if (!isNaN(size)) {
          this.desktopLyricFontSize = size;
          // 字号影响窗口高度，改完要让子窗口重新计算尺寸
          settingsService.update({ desktopLyricFontSize: size }).then((): void => {
            DesktopLyricManager.applyAppearance();
          }).catch((err: Error) => {
            hilog.warn(DOMAIN, TAG, 'update desktopLyricFontSize failed: %{public}s', err.message);
          });
        }
      }
    };
    items.push(lyricSizeItem);

    const lyricNextItem: SettingSectionItem = {
      type: 'toggle',
      title: t('lyric_show_next'),
      value: this.desktopLyricShowNext,
      onChangeToggle: (value: boolean) => {
        this.desktopLyricShowNext = value;
        settingsService.update({ desktopLyricShowNext: value }).then((): void => {
          DesktopLyricManager.applyAppearance();
        }).catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, 'update desktopLyricShowNext failed: %{public}s', err.message);
        });
      }
    };
    items.push(lyricNextItem);

    const lyricLockItem: SettingSectionItem = {
      type: 'toggle',
      title: t('lyric_lock_title'),
      description: t('lyric_lock_desc'),
      value: this.desktopLyricLocked,
      onChangeToggle: (value: boolean) => {
        this.desktopLyricLocked = value;
        void settingsService.update({ desktopLyricLocked: value });
        DesktopLyricManager.setLocked(value);
      }
    };
    items.push(lyricLockItem);

    return items;
  }

  private buildSearchSettings(): SettingSectionItem[] {
    const sourceOption: SettingOption[] = [
      { label: t('source_kw'), value: 'kw' },
      { label: t('source_tx'), value: 'tx' },
      { label: t('source_wy'), value: 'wy' },
      { label: t('source_kg'), value: 'kg' },
      { label: t('source_mg'), value: 'mg' }
    ];

    const items: SettingSectionItem[] = [];

    const sourceItem: SettingSectionItem = {
      type: 'select',
      title: t('settings_search_source'),
      value: this.searchSource,
      options: sourceOption,
      onChange: (value: string) => {
        this.searchSource = value;
        AppStorage.setOrCreate('defaultSearchSource', value);
        this.saveSettings();
      }
    };
    items.push(sourceItem);

    const hotSearchItem: SettingSectionItem = {
      type: 'toggle',
      title: t('settings_show_hot'),
      value: this.showHotSearch,
      onChangeToggle: (value: boolean) => {
        this.showHotSearch = value;
        AppStorage.setOrCreate('showHotSearch', value);
        this.saveSettings();
      }
    };
    items.push(hotSearchItem);

    const historyItem: SettingSectionItem = {
      type: 'input',
      title: t('settings_search_history'),
      value: this.searchHistoryCount.toString(),
      description: t('settings_search_history_desc'),
      onChange: (value: string) => {
        const num = parseInt(value);
        if (!isNaN(num) && num > 0) {
          this.searchHistoryCount = num;
          AppStorage.setOrCreate('searchHistoryCount', num);
          this.saveSettings();
          this.showToast(`${t('toast_history_max')} ${num}`);
        }
      }
    };
    items.push(historyItem);

    return items;
  }

  private buildDownloadSettings(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];

    items.push({
      type: 'button',
      title: t('download_path'),
      description: this.downloadPath,
      onClick: () => {
        void this.selectDownloadPath();
      }
    });

    items.push({
      type: 'toggle',
      title: t('download_auto_start'),
      value: this.autoStartDownload,
      onChangeToggle: (value: boolean) => {
        this.autoStartDownload = value;
        void this.saveDownloadSettings();
      }
    });

    items.push({
      type: 'button',
      title: t('download_concurrent'),
      description: `${t('download_concurrent_1')}`,
      onClick: () => {
        void this.selectMaxConcurrentDownloads();
      }
    });

    return items;
  }

  private async selectDownloadPath(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const picker = new filePicker.DocumentViewPicker(context);
      const saveOptions = new filePicker.DocumentSaveOptions();
      saveOptions.newFileNames = ['lxmusic-folder-marker.tmp'];
      const saveUris = await picker.save(saveOptions);
      if (!saveUris || saveUris.length === 0) {
        this.showToast(t('toast_dl_cancel'));
        return;
      }
      const selectedUri = saveUris[0];
      // 尝试清理占位文件（失败不阻塞）。
      try {
        await fs.unlink(selectedUri);
      } catch (cleanupErr) {
        // 占位文件可能已被系统回收，清理失败不影响后续流程
        hilog.debug(DOMAIN, TAG, 'Placeholder file cleanup skipped: %{public}s',
          cleanupErr instanceof Error ? cleanupErr.message : JSON.stringify(cleanupErr));
      }

      // 提取 docs:// URI 的目录部分（去掉文件名）
      let dirUri = selectedUri;
      const lastSlash = dirUri.lastIndexOf('/');
      if (lastSlash > 0) {
        dirUri = dirUri.substring(0, lastSlash);
      }

      this.downloadPath = dirUri;
      await this.saveDownloadSettings();
      this.showToast(t('toast_dl_path_updated'));
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      this.showToast(t('toast_dl_path_fail') + ': ' + errorMsg);
    }
  }

  private async selectMaxConcurrentDownloads(): Promise<void> {
    const countOptions: SettingOption[] = [
      { label: t('download_concurrent_1'), value: '1' },
      { label: t('download_concurrent_2'), value: '2' },
      { label: t('download_concurrent_3'), value: '3' },
    ];
    const selected = await new Promise<string | null>((resolve: (v: string | null) => void) => {
      this.selectDialogTitle = t('download_concurrent_title');
      this.selectDialogOptions = countOptions;
      this.selectDialogValue = this.maxConcurrentDownloads.toString();
      this.selectDialogCallback = (value: string) => {
        resolve(value);
      };
      this.showSelectDialog = true;
    });
    if (selected !== null) {
      const count = parseInt(selected);
      if (count === this.maxConcurrentDownloads) {
        return;
      }
      this.maxConcurrentDownloads = count;
      await this.saveDownloadSettings();
      setMaxConcurrentDownloads(count);
      this.showToast(tf('toast_concurrent_set', [count.toString()]));
    }
  }

  private buildListSettings(): SettingSectionItem[] {
    const locationOption: SettingOption[] = [
      { label: t('toast_add_top'), value: 'top' },
      { label: t('toast_add_bottom'), value: 'bottom' }
    ];

    const items: SettingSectionItem[] = [];

    const locationItem: SettingSectionItem = {
      type: 'select',
      title: t('settings_add_location'),
      value: this.listAddMusicLocation,
      options: locationOption,
      onChange: (value: string) => {
        this.listAddMusicLocation = value;
        AppStorage.setOrCreate('addMusicLocation', value);
        this.saveSettings();
        this.showToast(value === 'top' ? t('toast_add_top') : t('toast_add_bottom'));
      }
    };
    items.push(locationItem);

    const cleanItem: SettingSectionItem = {
      type: 'toggle',
      title: t('settings_auto_clean'),
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
      title: t('settings_backup_data'),
      description: t('settings_backup_data_desc'),
      onClick: () => {
        this.backupData();
      }
    };
    items.push(backupItem);

    const restoreItem: SettingSectionItem = {
      type: 'button',
      title: t('settings_restore_data'),
      description: t('settings_restore_data_desc'),
      onClick: () => {
        this.restoreData();
      }
    };
    items.push(restoreItem);

    const exportItem: SettingSectionItem = {
      type: 'button',
      title: t('settings_export_list'),
      description: t('settings_export_list_desc'),
      onClick: () => {
        this.exportPlaylists();
      }
    };
    items.push(exportItem);

    const importItem: SettingSectionItem = {
      type: 'button',
      title: t('settings_import_list'),
      description: t('settings_import_list_desc'),
      onClick: () => {
        this.importPlaylists();
      }
    };
    items.push(importItem);

    const clearItem: SettingSectionItem = {
      type: 'button',
      title: t('settings_clear_cache'),
      description: t('settings_clear_cache_desc'),
      onClick: () => {
        this.clearCache();
      }
    };
    items.push(clearItem);

    return items;
  }

  private buildSyncSettings(): SettingSectionItem[] {
    const syncModeOption: SettingOption[] = [
      { label: t('settings_sync_mode_client'), value: 'client' },
      { label: t('settings_sync_mode_server'), value: 'server' }
    ];

    const items: SettingSectionItem[] = [];

    const enableItem: SettingSectionItem = {
      type: 'toggle',
      title: t('settings_sync_enable'),
      value: this.syncEnable,
      onChangeToggle: (value: boolean) => {
        this.syncEnable = value;
        syncService.updateConfig({ enabled: value }).catch((err: Error) => {
          hilog.error(0x0001, 'SettingView', 'Sync config update failed: %{public}s', err.message);
        });
      }
    };
    items.push(enableItem);

    const serverItem: SettingSectionItem = {
      type: 'input',
      title: t('settings_sync_server'),
      value: this.syncServer,
      description: t('settings_sync_server_desc'),
      onChange: (value: string) => {
        this.syncServer = value;
        syncService.updateConfig({ serverUrl: value }).catch((err: Error) => {
          hilog.error(0x0001, 'SettingView', 'Sync config update failed: %{public}s', err.message);
        });
      }
    };
    items.push(serverItem);

    const keyItem: SettingSectionItem = {
      type: 'input',
      title: t('settings_sync_key'),
      value: this.syncKey,
      description: t('settings_sync_key_desc'),
      onChange: (value: string) => {
        this.syncKey = value;
        syncService.updateConfig({ syncKey: value }).catch((err: Error) => {
          hilog.error(0x0001, 'SettingView', 'Sync config update failed: %{public}s', err.message);
        });
      }
    };
    items.push(keyItem);

    const modeItem: SettingSectionItem = {
      type: 'select',
      title: t('settings_sync_mode'),
      value: this.syncMode,
      options: syncModeOption,
      onChange: (value: string) => {
        this.syncMode = value;
        syncService.updateConfig({
          mode: value === 'server' ? SyncMode.SERVER : SyncMode.CLIENT
        }).catch((err: Error) => {
          hilog.error(0x0001, 'SettingView', 'Sync config update failed: %{public}s', err.message);
        });
        hilog.info(0x0001, 'SettingView', 'Sync mode changed to: %{public}s', value);
      }
    };
    items.push(modeItem);

    const autoSyncItem: SettingSectionItem = {
      type: 'toggle',
      title: t('settings_sync_auto'),
      value: this.syncAutoSync,
      onChangeToggle: (value: boolean) => {
        this.syncAutoSync = value;
        syncService.updateConfig({ autoSync: value }).catch((err: Error) => {
          hilog.error(0x0001, 'SettingView', 'Sync config update failed: %{public}s', err.message);
        });
        hilog.info(0x0001, 'SettingView', 'Auto sync: %{public}s', value ? 'enabled' : 'disabled');
        if (value && this.syncEnable) {
          syncService.startAutoSync();
        } else {
          syncService.stopAutoSync();
        }
      }
    };
    items.push(autoSyncItem);

    const manualSyncItem: SettingSectionItem = {
      type: 'button',
      title: t('settings_sync_now'),
      onClick: () => {
        try {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
          syncService.setUIContext(context);
          syncService.sync().then((success: boolean) => {
            if (success) {
              this.showToast(t('toast_sync_sent'));
            } else {
              const status = syncService.getStatus();
              this.showToast(`${t('toast_sync_fail')}: ${status.error || status.message}`);
            }
          }).catch((err: Error) => {
            this.showToast(`${t('toast_sync_fail')}: ${err.message}`);
          });
        } catch (e) {
          hilog.error(0x0001, 'SettingView', 'Manual sync error: %{public}s', JSON.stringify(e));
          this.showToast(t('toast_sync_fail'));
        }
      }
    };
    items.push(manualSyncItem);

    const historyItem: SettingSectionItem = {
      type: 'button',
      title: t('settings_sync_history'),
      onClick: () => {
        const status = syncService.getStatus();
        const lastSyncTime = status.lastSyncTime > 0
          ? new Date(status.lastSyncTime).toLocaleString()
          : t('toast_never_sync');
        this.showToast(`${t('toast_last_sync')} ${lastSyncTime}`);
      }
    };
    items.push(historyItem);

    return items;
  }

  private buildAppearanceSettings(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];

    const darkModeItem: SettingSectionItem = {
      type: 'toggle',
      title: t('settings_dark_mode'),
      value: this.theme === 'dark',
      onChangeToggle: (value: boolean) => {
        this.theme = value ? 'dark' : 'light';
        this.setDarkMode(value);
        this.showToast(value ? t('toast_theme_dark') : t('toast_theme_light'));
      }
    };
    items.push(darkModeItem);

    const themeOptions: SettingOption[] = [];
    const themeList: ThemeItem[] = getAllThemes();
    for (let i = 0; i < themeList.length; i++) {
      themeOptions.push({ label: themeList[i].name, value: themeList[i].id });
    }
    const themeItem: SettingSectionItem = {
      type: 'select',
      title: t('settings_theme'),
      value: this.themeId,
      options: themeOptions,
      onChange: (value: string) => {
        this.theme = this.getThemeIsDark(value) ? 'dark' : 'light';
        this.applyTheme(value);
        this.showToast(`${t('settings_theme')}: ${this.getOptionLabel(themeOptions, value)}`);
      }
    };
    items.push(themeItem);

    const fontSizeItem: SettingSectionItem = {
      type: 'input',
      title: t('settings_font_size'),
      value: this.fontSize.toString(),
      description: t('settings_font_size_desc'),
      onChange: (value: string) => {
        const num = parseInt(value);
        if (!isNaN(num) && num >= 12 && num <= 20) {
          this.fontSize = num;
          // SettingsService 会同步到 AppStorage 并应用系统字号缩放
          void settingsService.update({ fontSize: num });
          this.showToast(`${t('toast_font_set')}: ${num}`);
        }
      }
    };
    items.push(fontSizeItem);

    const animationItem: SettingSectionItem = {
      type: 'toggle',
      title: t('settings_anim'),
      value: this.showAnimation,
      onChangeToggle: (value: boolean) => {
        this.showAnimation = value;
        void settingsService.update({ showAnimation: value });
      }
    };
    items.push(animationItem);

    return items;
  }

  private buildCustomSourceSettings(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];

    const importItem: SettingSectionItem = {
      type: 'button',
      title: t('settings_custom_source'),
      description: t('settings_custom_source_desc'),
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
    const content = message.trim().length > 0 ? message : t('unknown_error');
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: t('import_source_fail_title'),
        message: content,
        buttons: [
          { text: t('got_it'), color: DesignTokens.accent() },
        ],
      }).catch((error: Error) => {
        hilog.warn(0x0001, 'SettingView', 'showPluginLoadErrorDialog prompt failed: %{public}s',
          error.message || JSON.stringify(error));
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
      this.sourceImportError = t('source_import_fail');
      return;
    }
    if (!this.isValidSourceUrl(url)) {
      this.sourceImportError = t('invalid_url_format');
      return;
    }
    this.sourceImportLoading = true;
    this.sourceImportError = '';
    try {
      const ok = await loadCustomSource(url);
      if (ok) {
        this.showSourceImportDialog = false;
        this.showToast(t('source_import_success'));
      } else {
        const msg = t('source_import_fail');
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
        this.showToast(t('toast_import_cancel'));
        return;
      }
      const selectedUri = uris[0];
      const ok = await loadCustomSource(selectedUri);
      if (ok) {
        this.showSourceImportDialog = false;
        this.showToast(t('source_local_import_success'));
      } else {
        const msg = t('source_local_import_fail');
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
            Text(t('source_import_title'))
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

          TextInput({ placeholder: t('source_import_url_hint'), text: this.sourceImportUrl })
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
            Button(this.sourceImportLoading ? t('source_import_loading') : t('source_import_btn'))
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor(DesignTokens.accent())
              .enabled(!this.sourceImportLoading)
              .onClick(() => {
                void this.importSourceFromUrl();
              })
            Button(this.sourceImportLoading ? t('source_import_processing') : t('source_import_local'))
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

          Text(t('source_import_tip'))
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

    if (this.showInputDialog) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.35)')
          .onClick(() => {
            this.showInputDialog = false;
          })

        Column() {
          Text(tf('input_title_prefix', [this.inputDialogTitle]))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .margin({ bottom: 14 })

          TextInput({ text: this.inputDialogValue })
            .width('100%')
            .height(44)
            .fontSize(14)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .backgroundColor(DesignTokens.mutedFill(this.theme))
            .borderRadius(12)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.inputDialogValue = value;
            })

          Row({ space: 10 }) {
            Button(t('cancel'))
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .backgroundColor(DesignTokens.mutedFill(this.theme))
              .onClick(() => {
                this.showInputDialog = false;
              })
            Button(t('confirm'))
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor(DesignTokens.accent())
              .onClick(() => {
                if (this.inputDialogCallback) {
                  this.inputDialogCallback(this.inputDialogValue);
                }
                this.showInputDialog = false;
              })
          }
          .width('100%')
          .margin({ top: 16 })
        }
        .width('80%')
        .padding(18)
        .backgroundColor(DesignTokens.card(this.theme))
        .borderRadius(16)
        .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
        .onClick(() => {})
      }
      .width('100%')
      .height('100%')
    }

    if (this.showSelectDialog) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.35)')
          .onClick(() => {
            this.showSelectDialog = false;
          })

        Column() {
          Text(this.selectDialogTitle)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .margin({ bottom: 14 })

          Scroll() {
            Column() {
              ForEach(this.selectDialogOptions, (opt: SettingOption, idx: number) => {
                Row() {
                  Text(opt.label)
                    .fontSize(15)
                    .fontColor(opt.value === this.selectDialogValue ? DesignTokens.accent() : DesignTokens.labelPrimary(this.theme))
                    .fontWeight(opt.value === this.selectDialogValue ? FontWeight.Medium : FontWeight.Normal)
                    .layoutWeight(1)
                  if (opt.value === this.selectDialogValue) {
                    Text('✓')
                      .fontSize(16)
                      .fontColor(DesignTokens.accent())
                      .fontWeight(FontWeight.Bold)
                  }
                }
                .width('100%')
                .height(48)
                .padding({ left: 8, right: 8 })
                .onClick(() => {
                  this.selectDialogValue = opt.value;
                  if (this.selectDialogCallback) {
                    this.selectDialogCallback(opt.value);
                  }
                  this.showSelectDialog = false;
                })

                if (idx < this.selectDialogOptions.length - 1) {
                  Divider()
                    .strokeWidth(0.5)
                    .color(DesignTokens.cardBorder(this.theme))
                }
              })
            }
            .width('100%')
          }
          .height(Math.min(this.selectDialogOptions.length * 49, 320))
          .width('100%')

          Button(t('cancel'))
            .width('100%')
            .height(40)
            .fontSize(14)
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .backgroundColor(DesignTokens.mutedFill(this.theme))
            .margin({ top: 12 })
            .onClick(() => {
              this.showSelectDialog = false;
            })
        }
        .width('82%')
        .padding(18)
        .backgroundColor(DesignTokens.card(this.theme))
        .borderRadius(16)
        .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
        .constraintSize({ maxHeight: '75%' })
        .onClick(() => {})
      }
      .width('100%')
      .height('100%')
    }

    if (this.showConfirmOverlay) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.35)')
          .onClick(() => {})

        Column() {
          Text(this.confirmTitle)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .margin({ bottom: 10 })

          Text(this.confirmMessage)
            .fontSize(14)
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .margin({ bottom: 18 })
            .textAlign(TextAlign.Center)

          Row({ space: 10 }) {
            Button(t('cancel'))
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .backgroundColor(DesignTokens.mutedFill(this.theme))
              .onClick(() => {
                this.showConfirmOverlay = false;
                if (this.confirmResolve) {
                  this.confirmResolve(false);
                }
              })
            Button(t('confirm'))
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor(DesignTokens.accent())
              .onClick(() => {
                this.showConfirmOverlay = false;
                if (this.confirmResolve) {
                  this.confirmResolve(true);
                }
              })
          }
          .width('100%')
        }
        .width('80%')
        .padding(20)
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
      title: t('settings_about_lx'),
      onClick: () => {
        navigationService.navigateTo(RouteName.ABOUT);
      }
    };
    items.push(aboutItem);

    const versionItem: SettingSectionItem = {
      type: 'button',
      title: t('settings_version'),
      description: 'v1.0.0 (HarmonyOS)',
      onClick: () => {
        this.showToast('LX Music v1.0.0\nHarmonyOS NEXT');
      }
    };
    items.push(versionItem);

    return items;
  }

  // 备份数据
  async backupData(): Promise<void> {
    try {
      hilog.info(0x0001, 'SettingView', 'Starting data backup...');
      this.showToast(t('toast_backup_running'));

      // 设置备份服务上下文
      const context = this.getUIContext().getHostContext();
      if (context) {
        backupService.setContext(context as common.UIAbilityContext);
      }

      // 创建备份
      const backupFile = await backupService.createBackup(BackupDataType.ALL);

      if (backupFile) {
        hilog.info(0x0001, 'SettingView', 'Data backup completed: %{public}s', backupFile.fileName);
        this.showToast(t('toast_backup_success'));
      } else {
        hilog.error(0x0001, 'SettingView', 'Data backup failed: backup file is null');
        this.showToast(t('toast_backup_fail'));
      }
    } catch (err) {
      hilog.error(0x0001, 'SettingView', 'Data backup failed: %{public}s', JSON.stringify(err));
      this.showToast('备份创建失败: ' + (err instanceof Error ? err.message : t('unknown_error')));
    }
  }

  // 恢复数据
  async restoreData(): Promise<void> {
    try {
      hilog.info(0x0001, 'SettingView', 'Starting data restore...');
      this.showToast(t('toast_restore_running'));

      // 设置备份服务上下文
      const context = this.getUIContext().getHostContext();
      if (context) {
        backupService.setContext(context as common.UIAbilityContext);
      }

      // 选择备份文件
      const backupFile = await backupService.selectBackupFile();

      if (!backupFile) {
        hilog.info(0x0001, 'SettingView', 'Data restore cancelled: no file selected');
        this.showToast(t('toast_restore_cancel'));
        return;
      }

      // 确认恢复操作
      const confirmed = await this.showConfirmDialog(t('restore_confirm_title'),
        tf('confirm_restore_backup', [backupFile.fileName]));
      if (!confirmed) {
        this.showToast(t('toast_restore_cancel'));
        return;
      }

      // 恢复备份
      const success = await backupService.restoreBackup(backupFile);

      if (success) {
        hilog.info(0x0001, 'SettingView', 'Data restore completed: %{public}s', backupFile.fileName);
        this.showToast(t('toast_restore_success'));

        // 重新加载应用数据
        await this.reloadAppData();
      } else {
        hilog.error(0x0001, 'SettingView', 'Data restore failed');
        this.showToast(t('toast_restore_fail'));
      }
    } catch (err) {
      hilog.error(0x0001, 'SettingView', 'Data restore failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_restore_fail') + ': ' + (err instanceof Error ? err.message : t('unknown_error')));
    }
  }

  // 导出歌单
  async exportPlaylists(): Promise<void> {
    try {
      hilog.info(0x0001, 'SettingView', 'Exporting playlists...');
      this.showToast(t('toast_export_running'));

      // 1. 收集所有歌单数据
      const playlistsData = await this.collectPlaylistsData();
      const jsonData = JSON.stringify(playlistsData, null, 2);

      // 2. 使用文件选择器让用户选择保存位置
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const picker = new filePicker.DocumentViewPicker(context);
      const saveOptions = new filePicker.DocumentSaveOptions();
      const fileName = `lxmusic-playlists-${new Date().toISOString().replace(/[:.]/g, '-')}.json`;
      saveOptions.newFileNames = [fileName];
      const uris = await picker.save(saveOptions);
      if (!uris || uris.length === 0) {
        this.showToast(t('toast_export_cancel'));
        return;
      }

      // 3. 写入到用户选择的位置
      const file = fs.openSync(uris[0], fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      try {
        const data = utf8Encode(jsonData);
        fs.writeSync(file.fd, data.buffer as ArrayBuffer);
        fs.fsyncSync(file.fd);
        hilog.info(0x0001, 'SettingView', 'Playlists exported to: %{public}s', uris[0]);
        this.showToast(t('toast_export_success') + ': ' + fileName);
      } finally {
        fs.closeSync(file.fd);
      }
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(0x0001, 'SettingView', 'Playlists export failed: %{public}s', errorMsg);
      this.showToast(t('toast_export_fail') + ': ' + errorMsg);
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
        name: t('default_list_label'),
        type: 'default',
        musicCount: getDefaultList().length,
        musicList: getDefaultList()
      };
      
      const loveList: ExportedPlaylistRow = {
        id: LIST_IDS.LOVE,
        name: t('love_title'),
        type: 'love',
        musicCount: getLoveList().length,
        musicList: getLoveList()
      };
      
      const userLists = getUserList();
      const rows: ExportedPlaylistRow[] = [defaultList, loveList];
      for (let i = 0; i < userLists.length; i++) {
        const list = userLists[i];
        const songs = getUserListMusic(list.id);
        rows.push({
          id: list.id,
          name: list.name,
          type: 'user',
          source: list.source,
          desc: list.desc,
          pic: list.pic,
          count: list.count,
          musicCount: songs.length,
          musicList: songs,
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
      this.showToast(t('toast_import_running'));

      // 1. 使用文件选择器选择JSON文件（不限制后缀以确保兼容性）
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pickerOptions = new filePicker.DocumentSelectOptions();
      const picker = new filePicker.DocumentViewPicker(context);
      const uris = await picker.select(pickerOptions);
      if (!uris || uris.length === 0) {
        this.showToast(t('toast_import_cancel'));
        return;
      }
      const filePath = uris[0];

      // 2. 读取文件内容
      const file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
      try {
        const stat = fs.statSync(file.fd);
        const buffer = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buffer);
        const jsonData = utf8Decode(new Uint8Array(buffer));
        // 3. 解析歌单数据
        const playlistsData = JSON.parse(jsonData) as Record<string, Object>;
        // 4. 验证数据格式
        if (!this.validatePlaylistsData(playlistsData)) {
          this.showToast(t('toast_format_invalid'));
          return;
        }
        // 5. 导入到应用
        const importCount = await this.importPlaylistsData(playlistsData);

        await initListService();
        this.showToast(tf('toast_import_count', [importCount.toString()]));
      } finally {
        fs.closeSync(file.fd);
      }
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(0x0001, 'SettingView', 'Playlists import failed: %{public}s', errorMsg);
      this.showToast(t('toast_import_fail') + ': ' + errorMsg);
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
        const listType = playlist.type as string;
        const songList = Array.isArray(playlist.musicList) ? playlist.musicList as Array<Record<string, Object>> : [];

        try {
          if (listType === 'default') {
            // 导入到默认列表
            for (let m = 0; m < songList.length; m++) {
              await addMusicToList(LIST_IDS.DEFAULT, musicItemFromPlainObject(songList[m] as Object));
            }
            importCount++;
            hilog.info(0x0001, 'SettingView', 'Imported to default list: %{public}d songs', songList.length);
          } else if (listType === 'love') {
            // 导入到我喜欢列表
            for (let m = 0; m < songList.length; m++) {
              await addMusicToList(LIST_IDS.LOVE, musicItemFromPlainObject(songList[m] as Object));
            }
            importCount++;
            hilog.info(0x0001, 'SettingView', 'Imported to love list: %{public}d songs', songList.length);
          } else {
            // 用户自定义歌单
            const newList = await createUserList(playlist.name as string);
            for (let m = 0; m < songList.length; m++) {
              await addMusicToList(newList.id, musicItemFromPlainObject(songList[m] as Object));
            }
            importCount++;
            hilog.info(0x0001, 'SettingView', 'Imported user list: %{public}s (%{public}d songs)',
              playlist.name as string, songList.length);
          }
        } catch (err) {
          hilog.error(0x0001, 'SettingView', 'Failed to import playlist %{public}s: %{public}s',
            playlist.name as string, JSON.stringify(err));
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
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const imageCacheDir = `${context.cacheDir}/images`;
      clearedItems += await this.clearDirectory(imageCacheDir);
      
      // 2. 清除临时文件目录
      const tempDir = `${context.tempDir}`;
      clearedItems += await this.clearDirectory(tempDir);
      
      // 3. 清除搜索历史
      await this.clearSearchHistory();
      clearedItems++;
      
      // 4. 清除播放历史
      await this.clearPlayHistory();
      clearedItems++;

      hilog.info(0x0001, 'SettingView', 'Cache cleared: %{public}d items', clearedItems);
      this.showToast(tf('toast_cache_cleared_count', [clearedItems.toString()]));
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(0x0001, 'SettingView', 'Cache clear failed: %{public}s', errorMsg);
      this.showToast(t('toast_cache_cleared') + ': ' + errorMsg);
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
      // 搜索历史统一由 core/search 管理（存储键 search_history）
      await clearSearchHistoryList();
      hilog.info(0x0001, 'SettingView', 'Search history cleared');
    } catch (err) {
      hilog.error(0x0001, 'SettingView', 'Failed to clear search history: %{public}s', JSON.stringify(err));
    }
  }

  // 清除播放历史
  private async clearPlayHistory(): Promise<void> {
    try {
      await clearPlayHistoryStore();
      hilog.info(0x0001, 'SettingView', 'Play history cleared');
    } catch (err) {
      hilog.error(0x0001, 'SettingView', 'Failed to clear play history: %{public}s', JSON.stringify(err));
    }
  }

  // 显示确认对话框
  private async showConfirmDialog(title: string, message: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      this.confirmTitle = title;
      this.confirmMessage = message;
      this.confirmResolve = resolve;
      this.showConfirmOverlay = true;
    });
  }

  // 恢复后重新加载应用数据
  private async reloadAppData(): Promise<void> {
    try {
      // 备份恢复后：列表状态、设置、下载配置都要重新加载，否则界面还是旧数据
      await initListService();
      await this.loadSettings();
      await this.loadDownloadSettings();
      hilog.info(0x0001, 'SettingView', 'App data reloaded after restore');
    } catch (err) {
      hilog.error(0x0001, 'SettingView', 'Failed to reload app data: %{public}s', JSON.stringify(err));
    }
  }
}
