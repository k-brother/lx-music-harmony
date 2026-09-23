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
      await settingsService.update({
        themeId,
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

    items.push({
      type: 'toggle',
      title: t('settings_auto_theme'),
      description: t('settings_auto_theme_desc'),
      value: this.autoTheme,
      onChangeToggle: (value: boolean): void => {
        this.autoTheme = value;
        void settingsService.update({ autoTheme: value }).then((): void => {
          void applyAutoTheme();
        });
      },
    });

    if (this.autoTheme) {
      items.push({
        type: 'select',
        title: t('settings_theme_light'),
        value: this.themeLightId,
        options: lightOptions,
        onChange: (value: string): void => {
          this.themeLightId = value;
          void settingsService.update({ themeLightId: value }).then((): void => {
            void applyAutoTheme();
          });
        },
      });
      items.push({
        type: 'select',
        title: t('settings_theme_dark'),
        value: this.themeDarkId,
        options: darkOptions,
        onChange: (value: string): void => {
          this.themeDarkId = value;
          void settingsService.update({ themeDarkId: value }).then((): void => {
            void applyAutoTheme();
          });
        },
      });
    } else {
      items.push({
        type: 'toggle',
        title: t('settings_dark_mode'),
        value: this.theme === 'dark',
        onChangeToggle: (value: boolean): void => {
          void this.applyTheme(value ? DARK_THEME_ID : DEFAULT_THEME_ID);
          appToast(value ? t('toast_theme_dark') : t('toast_theme_light'));
        },
      });
      items.push({
        type: 'select',
        title: t('settings_theme'),
        value: this.themeId,
        options: allOptions,
        onChange: (value: string): void => {
          void this.applyTheme(value);
          appToast(`${t('settings_theme')}: ${labelOfOption(allOptions, value)}`);
        },
      });
    }

    items.push({
      type: 'toggle',
      title: t('settings_dynamic_bg'),
      description: t('settings_dynamic_bg_desc'),
      value: this.dynamicBg,
      onChangeToggle: (value: boolean): void => {
        this.dynamicBg = value;
        void settingsService.update({ dynamicBg: value });
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_font_shadow'),
      description: t('settings_font_shadow_desc'),
      value: this.fontShadow,
      onChangeToggle: (value: boolean): void => {
        this.fontShadow = value;
        void settingsService.update({ fontShadow: value });
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_hide_bg_dark'),
      description: t('settings_hide_bg_dark_desc'),
      value: this.hideBgDark,
      onChangeToggle: (value: boolean): void => {
        this.hideBgDark = value;
        void settingsService.update({ hideBgDark: value });
      },
    });

    items.push({
      type: 'input',
      title: t('settings_font_size'),
      description: t('settings_font_size_desc'),
      value: this.fontSize.toString(),
      onChange: (value: string): void => {
        const size = parseInt(value);
        if (isNaN(size) || size < 12 || size > 20) {
          appToast(t('settings_font_size_desc'));
          return;
        }
        this.fontSize = size;
        void settingsService.update({ fontSize: size });
        appToast(`${t('toast_font_set')}: ${size}`);
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_anim'),
      value: this.showAnimation,
      onChangeToggle: (value: boolean): void => {
        this.showAnimation = value;
        void settingsService.update({ showAnimation: value });
      },
    });

    return items;
  }


  build() {
    SettingsSection({ title: t('settings_appearance'), items: this.buildItems() })
  }
}
