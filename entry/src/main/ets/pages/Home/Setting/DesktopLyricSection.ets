/**
 * 设置 → 桌面歌词
 *
 * 开关 / 位置 / 颜色（未播放行 + 当前行）/ 文字位置与不透明度 / 背景不透明度 /
 * 字号 / 单双行 / 行数 / 宽度 / 行切换动画 / 阴影色 / 锁定穿透。
 * 外观类改动统一调用 DesktopLyricManager.applyAppearance() 让子窗口立即重算。
 */
import hilog from '@ohos.hilog';
import {
  settingsService,
  type DesktopLyricPosition,
  type SettingsPatch,
} from '../../../service/SettingsService';
import { t } from '../../../service/LocalizationService';
import { appToast } from '../../../service/DialogService';
import { DesktopLyricManager } from '../../../components/common/DesktopLyric';
import { watchSettings } from '../../../service/SettingsWatcher';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import type { SettingOption, SettingSectionItem } from '../../../components/ui/SettingsTypes';

const DOMAIN = 0x0001;
const TAG = 'DesktopLyricSection';


@Component
export struct DesktopLyricSection {
  @State lyricEnabled: boolean = false;
  @State lyricPosition: string = 'top';
  @State unplayColor: string = '#FFFFFF';
  @State playedColor: string = '#07C556';
  @State textPosX: string = 'left';
  @State textPosY: string = 'top';
  @State textOpacity: number = 100;
  @State bgAlpha: number = 0;
  @State lyricFontSize: number = 18;
  @State showNext: boolean = true;
  @State singleLine: boolean = false;
  @State lyricWidth: number = 100;
  @State lyricMaxLines: number = 2;
  @State animEnabled: boolean = true;
  @State lyricShadowColor: string = '#99000000';
  @State locked: boolean = false;

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
    this.lyricEnabled = settings.showDesktopLyric;
    this.lyricPosition = settings.desktopLyricPosition;
    this.unplayColor = settings.desktopLyricColor;
    this.playedColor = settings.desktopLyricPlayedColor;
    this.textPosX = settings.desktopLyricTextPositionX;
    this.textPosY = settings.desktopLyricTextPositionY;
    this.textOpacity = settings.desktopLyricTextOpacity;
    this.bgAlpha = settings.desktopLyricBgAlpha;
    this.lyricFontSize = settings.desktopLyricFontSize;
    this.showNext = settings.desktopLyricShowNext;
    this.singleLine = settings.desktopLyricSingleLine;
    this.lyricWidth = settings.desktopLyricWidth;
    this.lyricMaxLines = settings.desktopLyricMaxLines;
    this.animEnabled = settings.desktopLyricAnim;
    this.lyricShadowColor = settings.desktopLyricShadowColor;
    this.locked = settings.desktopLyricLocked;  }

  /** 外观类设置改动后让子窗口立即重算尺寸/配色 */
  private persistAppearance(patch: SettingsPatch): void {
    settingsService.update(patch).then((): void => {
      DesktopLyricManager.applyAppearance();
    }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'applyAppearance failed: %{public}s', err.message);
    });
  }

  private colorOptions(includeGreenFirst: boolean): SettingOption[] {
    return includeGreenFirst
      ? [
          { label: t('lyric_color_green'), value: '#07C556' },
          { label: t('lyric_color_white'), value: '#FFFFFF' },
          { label: t('lyric_color_blue'), value: '#42A5F5' },
          { label: t('lyric_color_pink'), value: '#EC407A' },
          { label: t('lyric_color_orange'), value: '#FF9800' },
        ]
      : [
          { label: t('lyric_color_white'), value: '#FFFFFF' },
          { label: t('lyric_color_green'), value: '#4CAF50' },
          { label: t('lyric_color_blue'), value: '#42A5F5' },
          { label: t('lyric_color_pink'), value: '#EC407A' },
          { label: t('lyric_color_orange'), value: '#FF9800' },
        ];
  }

  private buildItems(): SettingSectionItem[] {
    const positionOptions: SettingOption[] = [
      { label: t('lyric_pos_top'), value: 'top' },
      { label: t('lyric_pos_middle'), value: 'middle' },
      { label: t('lyric_pos_bottom'), value: 'bottom' },
    ];
    const textPosXOptions: SettingOption[] = [
      { label: t('lyric_text_pos_left'), value: 'left' },
      { label: t('lyric_text_pos_center'), value: 'center' },
      { label: t('lyric_text_pos_right'), value: 'right' },
    ];
    const textPosYOptions: SettingOption[] = [
      { label: t('lyric_text_pos_top'), value: 'top' },
      { label: t('lyric_text_pos_middle'), value: 'middle' },
      { label: t('lyric_text_pos_bottom'), value: 'bottom' },
    ];
    const opacityOptions: SettingOption[] = [
      { label: '100%', value: '100' },
      { label: '85%', value: '85' },
      { label: '70%', value: '70' },
      { label: '55%', value: '55' },
    ];
    const bgOptions: SettingOption[] = [
      { label: t('lyric_bg_transparent'), value: '0' },
      { label: t('lyric_bg_light'), value: '30' },
      { label: t('lyric_bg_medium'), value: '55' },
      { label: t('lyric_bg_solid'), value: '85' },
    ];
    const sizeOptions: SettingOption[] = [
      { label: t('lyric_size_small'), value: '14' },
      { label: t('lyric_size_normal'), value: '18' },
      { label: t('lyric_size_large'), value: '22' },
      { label: t('lyric_size_xlarge'), value: '26' },
    ];
    const widthOptions: SettingOption[] = [
      { label: '50%', value: '50' },
      { label: '70%', value: '70' },
      { label: '90%', value: '90' },
      { label: '100%', value: '100' },
    ];
    const lineOptions: SettingOption[] = [
      { label: '1', value: '1' },
      { label: '2', value: '2' },
      { label: '3', value: '3' },
    ];
    const shadowOptions: SettingOption[] = [
      { label: t('lyric_shadow_black'), value: '#99000000' },
      { label: t('lyric_shadow_none'), value: '#00000000' },
      { label: t('lyric_shadow_white'), value: '#99FFFFFF' },
    ];

    const items: SettingSectionItem[] = [];

    items.push({
      type: 'toggle',
      title: t('desktop_lyric'),
      description: t('desktop_lyric_desc'),
      value: this.lyricEnabled,
      onChangeToggle: (value: boolean): void => {
        this.lyricEnabled = value;
        void settingsService.update({ showDesktopLyric: value });
        void DesktopLyricManager.setEnabled(value);
        appToast(value ? t('toast_desktop_on') : t('toast_desktop_off'));
      },
    });

    items.push({
      type: 'select',
      title: t('lyric_pos_title'),
      value: this.lyricPosition,
      options: positionOptions,
      onChange: (value: string): void => {
        this.lyricPosition = value;
        void settingsService.update({ desktopLyricPosition: value as DesktopLyricPosition });
        DesktopLyricManager.applyPosition(value as DesktopLyricPosition);
      },
    });

    items.push({
      type: 'select',
      title: t('lyric_color_title'),
      value: this.unplayColor,
      options: this.colorOptions(false),
      onChange: (value: string): void => {
        this.unplayColor = value;
        this.persistAppearance({ desktopLyricColor: value });
      },
    });

    items.push({
      type: 'select',
      title: t('lyric_played_color_title'),
      value: this.playedColor,
      options: this.colorOptions(true),
      onChange: (value: string): void => {
        this.playedColor = value;
        this.persistAppearance({ desktopLyricPlayedColor: value });
      },
    });

    items.push({
      type: 'select',
      title: t('lyric_text_position_x'),
      value: this.textPosX,
      options: textPosXOptions,
      onChange: (value: string): void => {
        this.textPosX = value;
        this.persistAppearance({
          desktopLyricTextPositionX: value === 'right' ? 'right' : (value === 'left' ? 'left' : 'center'),
        });
      },
    });

    items.push({
      type: 'select',
      title: t('lyric_text_position_y'),
      value: this.textPosY,
      options: textPosYOptions,
      onChange: (value: string): void => {
        this.textPosY = value;
        this.persistAppearance({
          desktopLyricTextPositionY: value === 'top' ? 'top' : (value === 'bottom' ? 'bottom' : 'middle'),
        });
      },
    });

    items.push({
      type: 'select',
      title: t('lyric_text_opacity'),
      value: this.textOpacity.toString(),
      options: opacityOptions,
      onChange: (value: string): void => {
        const opacity = parseInt(value);
        if (isNaN(opacity)) {
          return;
        }
        this.textOpacity = opacity;
        this.persistAppearance({ desktopLyricTextOpacity: opacity });
      },
    });

    items.push({
      type: 'select',
      title: t('lyric_bg_title'),
      value: this.bgAlpha.toString(),
      options: bgOptions,
      onChange: (value: string): void => {
        const alpha = parseInt(value);
        if (isNaN(alpha)) {
          return;
        }
        this.bgAlpha = alpha;
        this.persistAppearance({ desktopLyricBgAlpha: alpha });
      },
    });

    items.push({
      type: 'select',
      title: t('lyric_size_title'),
      value: this.lyricFontSize.toString(),
      options: sizeOptions,
      onChange: (value: string): void => {
        const size = parseInt(value);
        if (isNaN(size)) {
          return;
        }
        this.lyricFontSize = size;
        this.persistAppearance({ desktopLyricFontSize: size });
      },
    });

    items.push({
      type: 'toggle',
      title: t('lyric_show_next'),
      value: this.showNext,
      onChangeToggle: (value: boolean): void => {
        this.showNext = value;
        this.persistAppearance({ desktopLyricShowNext: value });
      },
    });

    items.push({
      type: 'toggle',
      title: t('lyric_single_line'),
      description: t('lyric_single_line_desc'),
      value: this.singleLine,
      onChangeToggle: (value: boolean): void => {
        this.singleLine = value;
        this.persistAppearance({ desktopLyricSingleLine: value });
      },
    });

    items.push({
      type: 'select',
      title: t('lyric_width'),
      value: this.lyricWidth.toString(),
      options: widthOptions,
      onChange: (value: string): void => {
        const width = parseInt(value);
        if (isNaN(width)) {
          return;
        }
        this.lyricWidth = width;
        this.persistAppearance({ desktopLyricWidth: width });
      },
    });

    items.push({
      type: 'select',
      title: t('lyric_max_lines'),
      value: this.lyricMaxLines.toString(),
      options: lineOptions,
      onChange: (value: string): void => {
        const lines = parseInt(value);
        if (isNaN(lines)) {
          return;
        }
        this.lyricMaxLines = lines;
        this.persistAppearance({ desktopLyricMaxLines: lines });
      },
    });

    items.push({
      type: 'toggle',
      title: t('lyric_anim'),
      value: this.animEnabled,
      onChangeToggle: (value: boolean): void => {
        this.animEnabled = value;
        void settingsService.update({ desktopLyricAnim: value });
      },
    });

    items.push({
      type: 'select',
      title: t('lyric_shadow_title'),
      value: this.lyricShadowColor,
      options: shadowOptions,
      onChange: (value: string): void => {
        this.lyricShadowColor = value;
        this.persistAppearance({ desktopLyricShadowColor: value });
      },
    });

    items.push({
      type: 'toggle',
      title: t('lyric_lock_title'),
      description: t('lyric_lock_desc'),
      value: this.locked,
      onChangeToggle: (value: boolean): void => {
        this.locked = value;
        void settingsService.update({ desktopLyricLocked: value });
        DesktopLyricManager.setLocked(value);
      },
    });

    return items;
  }

  build() {
    SettingsSection({
      title: t('settings_desktop_lyric'),
      items: this.buildItems(),
    })
  }
}
