/**
 * 设置 → 基础
 *
 * 分组组件约定（全部分组一致）：
 * - 状态由本组件自持，进入时从 settingsService 读，变更即写回（settingsService 负责镜像 AppStorage 与广播事件）
 * - 视觉与交互交给 SettingsSection（分组卡片 + 按压 + 选择/输入面板）
 * - 提示统一走 DialogService
 */
import { settingsService, type StartupPage, type SourceNameType, type ShareType } from '../../../service/SettingsService';
import { t } from '../../../service/LocalizationService';
import { setLanguage } from '../../../service/LocalizationService';
import { navigationService, RouteName } from '../../../service/NavigationService';
import { appToast } from '../../../service/DialogService';
import { watchSettings } from '../../../service/SettingsWatcher';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import type { SettingOption, SettingSectionItem } from '../../../components/ui/SettingsTypes';

@Component
export struct BasicSection {
  @StorageLink('language') language: string = 'zh-CN';
  @State startupPage: string = 'home';
  @State showExitDialog: boolean = true;
  @State sourceNameType: string = 'alias';
  @State shareType: string = 'system';
  @State allowProgressBarSeek: boolean = true;

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
    this.language = settings.language;
    this.startupPage = settings.startupPage;
    this.showExitDialog = settings.showExitDialog;
    this.sourceNameType = settings.sourceNameType;
    this.shareType = settings.shareType;
    this.allowProgressBarSeek = settings.allowProgressBarSeek;  }

  private buildItems(): SettingSectionItem[] {
    const languageOptions: SettingOption[] = [
      { label: '简体中文', value: 'zh-CN' },
      { label: 'English', value: 'en-US' },
    ];
    const startupOptions: SettingOption[] = [
      { label: t('songlist_title'), value: 'home' },
      { label: t('player_title'), value: 'playdetail' },
    ];
    const sourceNameOptions: SettingOption[] = [
      { label: t('settings_source_name_alias'), value: 'alias' },
      { label: t('settings_source_name_real'), value: 'real' },
    ];
    const shareOptions: SettingOption[] = [
      { label: t('settings_share_system'), value: 'system' },
      { label: t('settings_share_clipboard'), value: 'clipboard' },
    ];

    const items: SettingSectionItem[] = [];

    items.push({
      type: 'select',
      title: t('settings_language'),
      value: this.language,
      options: languageOptions,
      onChange: (value: string): void => {
        setLanguage(value);
        this.language = value;
        void settingsService.update({ language: value });
        appToast(value === 'zh-CN' ? t('toast_lang_zh') : 'Switched to English');
        // 语言切换后回到首页触发整树重建，避免残留旧文案
        navigationService.backTo(RouteName.HOME);
      },
    });

    items.push({
      type: 'select',
      title: t('settings_startup_page'),
      value: this.startupPage,
      options: startupOptions,
      onChange: (value: string): void => {
        this.startupPage = value;
        void settingsService.update({ startupPage: value as StartupPage });
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_exit_confirm'),
      value: this.showExitDialog,
      onChangeToggle: (value: boolean): void => {
        this.showExitDialog = value;
        void settingsService.update({ showExitDialog: value });
      },
    });

    items.push({
      type: 'select',
      title: t('settings_source_name'),
      description: t('settings_source_name_desc'),
      value: this.sourceNameType,
      options: sourceNameOptions,
      onChange: (value: string): void => {
        this.sourceNameType = value;
        void settingsService.update({ sourceNameType: value as SourceNameType });
        appToast(`${t('settings_source_name')}: ${this.labelOf(sourceNameOptions, value)}`);
      },
    });

    items.push({
      type: 'select',
      title: t('settings_share_type'),
      description: t('settings_share_type_desc'),
      value: this.shareType,
      options: shareOptions,
      onChange: (value: string): void => {
        this.shareType = value;
        void settingsService.update({ shareType: value as ShareType });
        appToast(`${t('settings_share_type')}: ${this.labelOf(shareOptions, value)}`);
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_allow_seek'),
      description: t('settings_allow_seek_desc'),
      value: this.allowProgressBarSeek,
      onChangeToggle: (value: boolean): void => {
        this.allowProgressBarSeek = value;
        void settingsService.update({ allowProgressBarSeek: value });
      },
    });

    return items;
  }

  private labelOf(options: SettingOption[], value: string): string {
    for (let i = 0; i < options.length; i++) {
      if (options[i].value === value) {
        return options[i].label;
      }
    }
    return value;
  }

  build() {
    SettingsSection({ title: t('settings_basic'), items: this.buildItems() })
  }
}
