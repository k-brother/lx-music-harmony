/**
 * 设置 → 列表
 *
 * 含「不喜欢列表」管理：查看规则条数、一键清空（走 DialogService，不再手写 ActionMenu 元组）。
 */
import hilog from '@ohos.hilog';
import { settingsService, type AddMusicLocation } from '../../../service/SettingsService';
import { t, tf } from '../../../service/LocalizationService';
import { appActionMenu, appToast } from '../../../service/DialogService';
import { dislikeList } from '../../../core/dislike/DislikeList';
import { Subscription } from '../../../service/Subscription';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import type { SettingOption, SettingSectionItem } from '../../../components/ui/SettingsTypes';

const DOMAIN = 0x0001;
const TAG = 'ListSection';

@Component
export struct ListSection {
  @State addMusicLocation: string = 'top';
  @State autoCleanPlayedList: boolean = false;
  @State listClickPlay: boolean = false;
  @State showListSource: boolean = true;
  @State showListAlbum: boolean = true;
  @State showListDuration: boolean = true;
  @State rememberScrollPosition: boolean = true;
  /** 不喜欢规则条数（打开设置页时刷新） */
  @State dislikeCount: number = 0;

  private settingsWatch: Subscription = new Subscription();

  aboutToAppear() {
    this.loadFromSettings();
    // 外部改动（恢复备份 / 同步下发 / 其它入口）也要刷新本分组
    this.settingsWatch.bindSettings((): void => {
      this.loadFromSettings();
    });
  }

  aboutToDisappear() {
    this.settingsWatch.detach();
  }

  /** 从设置服务读取本分组的当前值 */
  private loadFromSettings(): void {
    const settings = settingsService.get();
    this.addMusicLocation = settings.addMusicLocation;
    this.autoCleanPlayedList = settings.autoCleanPlayedList;
    this.listClickPlay = settings.listClickPlay;
    this.showListSource = settings.showListSource;
    this.showListAlbum = settings.showListAlbum;
    this.showListDuration = settings.showListDuration;
    this.rememberScrollPosition = settings.rememberScrollPosition;
    void this.refreshDislikeCount();  }

  private async refreshDislikeCount(): Promise<void> {
    try {
      await dislikeList.load();
      this.dislikeCount = dislikeList.count();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'refreshDislikeCount failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 不喜欢列表管理：清空规则（带二次确认菜单） */
  private async manageDislikeList(): Promise<void> {
    await this.refreshDislikeCount();
    if (this.dislikeCount === 0) {
      appToast(tf('dislike_count', ['0']));
      return;
    }
    const picked = await appActionMenu(
      tf('dislike_count', [this.dislikeCount.toString()]),
      [t('dislike_clear')],
      { dangerIndexes: [0] });
    if (picked !== 0) {
      return;
    }
    try {
      await dislikeList.clear();
      this.dislikeCount = 0;
      appToast(t('dislike_cleared'));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clear dislike failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_operation_failed'));
    }
  }

  private buildItems(): SettingSectionItem[] {
    const locationOptions: SettingOption[] = [
      { label: t('toast_add_top'), value: 'top' },
      { label: t('toast_add_bottom'), value: 'bottom' },
    ];

    const items: SettingSectionItem[] = [];

    items.push({
      type: 'select',
      title: t('settings_add_location'),
      value: this.addMusicLocation,
      options: locationOptions,
      onChange: (value: string): void => {
        this.addMusicLocation = value;
        void settingsService.update({ addMusicLocation: value as AddMusicLocation });
        appToast(value === 'top' ? t('toast_add_top') : t('toast_add_bottom'));
      },
    });

    items.push({
      type: 'button',
      title: t('dislike_title'),
      description: tf('dislike_count', [this.dislikeCount.toString()]),
      onClick: (): void => {
        void this.manageDislikeList();
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_auto_clean'),
      value: this.autoCleanPlayedList,
      onChangeToggle: (value: boolean): void => {
        this.autoCleanPlayedList = value;
        void settingsService.update({ autoCleanPlayedList: value });
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_list_click_play'),
      description: t('settings_list_click_play_desc'),
      value: this.listClickPlay,
      onChangeToggle: (value: boolean): void => {
        this.listClickPlay = value;
        void settingsService.update({ listClickPlay: value });
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_show_source'),
      value: this.showListSource,
      onChangeToggle: (value: boolean): void => {
        this.showListSource = value;
        void settingsService.update({ showListSource: value });
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_show_album'),
      value: this.showListAlbum,
      onChangeToggle: (value: boolean): void => {
        this.showListAlbum = value;
        void settingsService.update({ showListAlbum: value });
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_show_duration'),
      value: this.showListDuration,
      onChangeToggle: (value: boolean): void => {
        this.showListDuration = value;
        void settingsService.update({ showListDuration: value });
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_remember_scroll'),
      description: t('settings_remember_scroll_desc'),
      value: this.rememberScrollPosition,
      onChangeToggle: (value: boolean): void => {
        this.rememberScrollPosition = value;
        void settingsService.update({ rememberScrollPosition: value });
      },
    });

    return items;
  }

  build() {
    SettingsSection({ title: t('settings_list'), items: this.buildItems() })
  }
}
