/**
 * 设置 → 外观
 *
 * 主题体系（16 套）+ 自动跟随系统（浅色/深色主题分别指定）+ 动态背景/字体阴影/深色隐藏背景
 * + 字号 / 动画。主题应用统一走 ThemeService。
 */
import hilog from '@ohos.hilog';
import { settingsService } from '../../../service/SettingsService';
import { t } from '../../../service/LocalizationService';
import { appToast } from '../../../service/DialogService';
import { applyThemeById, applyAutoTheme, getAllThemes } from '../../../service/ThemeService';
import { DEFAULT_THEME_ID } from '../../../core/theme/themes';
import { Subscription } from '../../../service/Subscription';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import { labelOfOption, type SettingOption, type SettingSectionItem } from '../../../components/ui/SettingsTypes';
import { toggleRow, selectRow, inputRow } from '../../../components/ui/SettingsRows';
import type { ThemeItem } from '../../../types/ThemeTypes';

const DOMAIN = 0x0001;
const TAG = 'AppearanceSection';
/** 内置深色主题 id（与 core/theme/themes 中的 black 对应） */
const DARK_THEME_ID = 'black';

@Component
export struct AppearanceSection {
  @StorageProp('theme') theme: string = 'light';
  @State autoTheme: boolean = false;
  @State themeId: string = DEFAULT_THEME_ID;
  @State themeLightId: string = DEFAULT_THEME_ID;
  @State themeDarkId: string = DARK_THEME_ID;
  @State dynamicBg: boolean = false;
  @State fontShadow: boolean = false;
  @State hideBgDark: boolean = false;
  @State fontSize: number = 14;
  @State showAnimation: boolean = true;

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
    this.autoTheme = settings.autoTheme;
    this.themeId = settings.themeId;
    this.themeLightId = settings.themeLightId;
    this.themeDarkId = settings.themeDarkId;
    this.dynamicBg = settings.dynamicBg;
    this.fontShadow = settings.fontShadow;
    this.hideBgDark = settings.hideBgDark;
    this.fontSize = settings.fontSize;
    this.showAnimation = settings.showAnimation;  }

  /** 切换主题（手动模式下使用） */
  private async applyTheme(themeId: string): Promise<void> {
    try {
      await applyThemeById(themeId);
      this.themeId = themeId;
      // 手动选主题意味着不再跟随系统（否则系统一变色/下一次同步就会把它覆盖掉）
      this.autoTheme = false;
      await settingsService.update({
        themeId,
        autoTheme: false,
        themeMode: this.theme === 'dark' ? 'dark' : 'light',
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'applyTheme failed: %{public}s', JSON.stringify(err));
    }
  }

  private buildItems(): SettingSectionItem[] {
    const themeItems: ThemeItem[] = getAllThemes();
    const allOptions: SettingOption[] = [];
    const lightOptions: SettingOption[] = [];
    const darkOptions: SettingOption[] = [];
    for (let i = 0; i < themeItems.length; i++) {
      const option: SettingOption = { label: themeItems[i].name, value: themeItems[i].id };
      allOptions.push(option);
      if (themeItems[i].isDark) {
        darkOptions.push({ label: themeItems[i].name, value: themeItems[i].id });
      } else {
        lightOptions.push({ label: themeItems[i].name, value: themeItems[i].id });
      }
    }

    const items: SettingSectionItem[] = [];

    items.push(toggleRow(t('settings_auto_theme'), this.autoTheme, (value: boolean): void => {
      this.autoTheme = value;
      void settingsService.update({ autoTheme: value }).then((): void => {
        void applyAutoTheme();
      });
    }, t('settings_auto_theme_desc')));

    if (this.autoTheme) {
      items.push(selectRow(t('settings_theme_light'), this.themeLightId, lightOptions, (value: string): void => {
        this.themeLightId = value;
        void settingsService.update({ themeLightId: value }).then((): void => {
          void applyAutoTheme();
        });
      }));
      items.push(selectRow(t('settings_theme_dark'), this.themeDarkId, darkOptions, (value: string): void => {
        this.themeDarkId = value;
        void settingsService.update({ themeDarkId: value }).then((): void => {
          void applyAutoTheme();
        });
      }));
    } else {
      items.push(toggleRow(t('settings_dark_mode'), this.theme === 'dark', (value: boolean): void => {
        void this.applyTheme(value ? DARK_THEME_ID : DEFAULT_THEME_ID);
        appToast(value ? t('toast_theme_dark') : t('toast_theme_light'));
      }));
      items.push(selectRow(t('settings_theme'), this.themeId, allOptions, (value: string): void => {
        void this.applyTheme(value);
        appToast(`${t('settings_theme')}: ${labelOfOption(allOptions, value)}`);
      }));
    }

    items.push(toggleRow(t('settings_dynamic_bg'), this.dynamicBg, (value: boolean): void => {
      this.dynamicBg = value;
      void settingsService.update({ dynamicBg: value });
    }, t('settings_dynamic_bg_desc')));

    items.push(toggleRow(t('settings_font_shadow'), this.fontShadow, (value: boolean): void => {
      this.fontShadow = value;
      void settingsService.update({ fontShadow: value });
    }, t('settings_font_shadow_desc')));

    items.push(toggleRow(t('settings_hide_bg_dark'), this.hideBgDark, (value: boolean): void => {
      this.hideBgDark = value;
      void settingsService.update({ hideBgDark: value });
    }, t('settings_hide_bg_dark_desc')));

    items.push(inputRow(t('settings_font_size'), this.fontSize.toString(), (value: string): void => {
      const size = parseInt(value);
      if (isNaN(size) || size < 12 || size > 20) {
        appToast(t('settings_font_size_desc'));
        return;
      }
      this.fontSize = size;
      void settingsService.update({ fontSize: size });
      appToast(`${t('toast_font_set')}: ${size}`);
    }, t('settings_font_size_desc')));

    items.push(toggleRow(t('settings_anim'), this.showAnimation, (value: boolean): void => {
      this.showAnimation = value;
      void settingsService.update({ showAnimation: value });
    }));

    return items;
  }


  build() {
    SettingsSection({ title: t('settings_appearance'), items: this.buildItems() })
  }
}
