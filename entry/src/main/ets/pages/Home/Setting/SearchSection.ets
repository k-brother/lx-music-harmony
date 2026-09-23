/**
 * 设置 → 搜索
 */
import { settingsService } from '../../../service/SettingsService';
import { t, tf } from '../../../service/LocalizationService';
import { appToast } from '../../../service/DialogService';
import { Subscription } from '../../../service/Subscription';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import type { SettingOption, SettingSectionItem } from '../../../components/ui/SettingsTypes';
import { toggleRow, selectRow, inputRow } from '../../../components/ui/SettingsRows';

@Component
export struct SearchSection {
  @State searchSource: string = 'kw';
  @State showHotSearch: boolean = true;
  @State showSearchHistory: boolean = false;
  @State searchHistoryCount: number = 20;

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
    this.searchSource = settings.searchSource;
    this.showHotSearch = settings.showHotSearch;
    this.showSearchHistory = settings.showSearchHistory;
    this.searchHistoryCount = settings.searchHistoryCount;  }

  private buildItems(): SettingSectionItem[] {
    const sourceOptions: SettingOption[] = [
      { label: t('source_kw'), value: 'kw' },
      { label: t('source_tx'), value: 'tx' },
      { label: t('source_wy'), value: 'wy' },
      { label: t('source_kg'), value: 'kg' },
      { label: t('source_mg'), value: 'mg' },
    ];

    const items: SettingSectionItem[] = [];

    items.push(selectRow(t('settings_search_source'), this.searchSource, sourceOptions, (value: string): void => {
      this.searchSource = value;
      void settingsService.update({ searchSource: value });
    }));

    items.push(toggleRow(t('settings_show_hot'), this.showHotSearch, (value: boolean): void => {
      this.showHotSearch = value;
      void settingsService.update({ showHotSearch: value });
    }));

    items.push(toggleRow(t('settings_show_history'), this.showSearchHistory, (value: boolean): void => {
      this.showSearchHistory = value;
      void settingsService.update({ showSearchHistory: value });
    }, t('settings_show_history_desc')));

    items.push(inputRow(t('settings_search_history'), this.searchHistoryCount.toString(), (value: string): void => {
      const count = parseInt(value);
      if (isNaN(count) || count <= 0) {
        appToast(t('unknown_error'));
        return;
      }
      this.searchHistoryCount = count;
      void settingsService.update({ searchHistoryCount: count });
      appToast(tf('toast_history_max', [count.toString()]));
    }, t('settings_search_history_desc')));

    return items;
  }

  build() {
    SettingsSection({ title: t('settings_search'), items: this.buildItems() })
  }
}
