/**
 * 设置 → 桌面歌词
 *
 * 开关 / 位置 / 颜色（未播放行 + 当前行）/ 文字位置与不透明度 / 背景不透明度 /
 * 字号 / 单双行 / 行数 / 宽度 / 行切换动画 / 阴影色 / 锁定穿透。
 * 外观类改动统一调用 DesktopLyricManager.applyAppearance() 让子窗口立即重算。
 */
import hilog from '@ohos.hilog';
import { selectRow, toggleRow, infoRow } from '../../../components/ui/SettingsRows';
import {
  settingsService,
  type DesktopLyricPosition,
  type SettingsPatch,
} from '../../../service/SettingsService';
import { t } from '../../../service/LocalizationService';
import { appToast } from '../../../service/DialogService';
import { DesktopLyricManager } from '../../../components/common/DesktopLyric';
import { Subscription } from '../../../service/Subscription';
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
  /** 是否由系统原生歌词接管（决定提示文案） */
  @State usingSystemLyric: boolean = false;

  private settingsWatch: Subscription = new Subscription();

  aboutToAppear() {
    this.loadFromSettings();
    this.usingSystemLyric = DesktopLyricManager.isUsingSystemLyric();
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

  /** 分组装配：状态说明 / 位置颜色 / 文字样式 / 行为（原 272 行单函数按用途拆开） */
  private buildItems(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];
    this.appendStatusItems(items);
    this.appendPositionItems(items);
    this.appendTextItems(items);
    this.appendBehaviorItems(items);
    return items;
  }

  /** 当前是系统原生歌词还是内置浮窗 + 总开关 */
  private appendStatusItems(items: SettingSectionItem[]): void {
    // 系统原生歌词接管时，外观项由系统统一控制（跟随系统主题/位置），
    // 这里给用户一句明确说明，避免"改了字号颜色却没反应"的困惑。
    if (this.lyricEnabled) {
      items.push(infoRow(
        this.usingSystemLyric ? t('desktop_lyric_system_mode') : t('desktop_lyric_builtin_mode'),
        '',
        this.usingSystemLyric ? t('desktop_lyric_system_mode_desc') : t('desktop_lyric_builtin_mode_desc'),
      ));
    }

    items.push(toggleRow(t('desktop_lyric'), this.lyricEnabled, (value: boolean): void => {
      this.lyricEnabled = value;
      this.usingSystemLyric = false;
      void settingsService.update({ showDesktopLyric: value });
      DesktopLyricManager.setEnabled(value).then((): void => {
        this.usingSystemLyric = DesktopLyricManager.isUsingSystemLyric();
      }).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'toggle desktop lyric failed: %{public}s', err.message);
      });
      appToast(value ? t('toast_desktop_on') : t('toast_desktop_off'));
    }, t('desktop_lyric_desc')));
  }

  /** 位置与颜色：窗口位置 / 未播放色 / 已播放色 / 文字水平与垂直对齐 */
  private appendPositionItems(items: SettingSectionItem[]): void {
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

    items.push(selectRow(t('lyric_pos_title'), this.lyricPosition, positionOptions, (value: string): void => {
      this.lyricPosition = value;
      void settingsService.update({ desktopLyricPosition: value as DesktopLyricPosition });
      DesktopLyricManager.applyPosition(value as DesktopLyricPosition);
    }));

    items.push(selectRow(t('lyric_color_title'), this.unplayColor, this.colorOptions(false), (value: string): void => {
      this.unplayColor = value;
      this.persistAppearance({ desktopLyricColor: value });
    }));

    items.push(selectRow(t('lyric_played_color_title'), this.playedColor, this.colorOptions(true), (value: string): void => {
      this.playedColor = value;
      this.persistAppearance({ desktopLyricPlayedColor: value });
    }));

    items.push(selectRow(t('lyric_text_position_x'), this.textPosX, textPosXOptions, (value: string): void => {
      this.textPosX = value;
      this.persistAppearance({
        desktopLyricTextPositionX: value === 'right' ? 'right' : (value === 'left' ? 'left' : 'center'),
      });
    }));

    items.push(selectRow(t('lyric_text_position_y'), this.textPosY, textPosYOptions, (value: string): void => {
      this.textPosY = value;
      this.persistAppearance({
        desktopLyricTextPositionY: value === 'top' ? 'top' : (value === 'bottom' ? 'bottom' : 'middle'),
      });
    }));
  }

  /** 文字样式：不透明度 / 背景 / 字号 / 下一句 / 单行 / 宽度 / 最大行数 */
  private appendTextItems(items: SettingSectionItem[]): void {
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

    items.push(selectRow(t('lyric_text_opacity'), this.textOpacity.toString(), opacityOptions, (value: string): void => {
      const opacity = parseInt(value);
      if (isNaN(opacity)) {
        return;
      }
      this.textOpacity = opacity;
      this.persistAppearance({ desktopLyricTextOpacity: opacity });
    }));

    items.push(selectRow(t('lyric_bg_title'), this.bgAlpha.toString(), bgOptions, (value: string): void => {
      const alpha = parseInt(value);
      if (isNaN(alpha)) {
        return;
      }
      this.bgAlpha = alpha;
      this.persistAppearance({ desktopLyricBgAlpha: alpha });
    }));

    items.push(selectRow(t('lyric_size_title'), this.lyricFontSize.toString(), sizeOptions, (value: string): void => {
      const size = parseInt(value);
      if (isNaN(size)) {
        return;
      }
      this.lyricFontSize = size;
      this.persistAppearance({ desktopLyricFontSize: size });
    }));

    items.push(toggleRow(t('lyric_show_next'), this.showNext, (value: boolean): void => {
      this.showNext = value;
      this.persistAppearance({ desktopLyricShowNext: value });
    }));

    items.push(toggleRow(t('lyric_single_line'), this.singleLine, (value: boolean): void => {
      this.singleLine = value;
      this.persistAppearance({ desktopLyricSingleLine: value });
    }, t('lyric_single_line_desc')));

    items.push(selectRow(t('lyric_width'), this.lyricWidth.toString(), widthOptions, (value: string): void => {
      const width = parseInt(value);
      if (isNaN(width)) {
        return;
      }
      this.lyricWidth = width;
      this.persistAppearance({ desktopLyricWidth: width });
    }));

    items.push(selectRow(t('lyric_max_lines'), this.lyricMaxLines.toString(), lineOptions, (value: string): void => {
      const lines = parseInt(value);
      if (isNaN(lines)) {
        return;
      }
      this.lyricMaxLines = lines;
      this.persistAppearance({ desktopLyricMaxLines: lines });
    }));
  }

  /** 行为：动画 / 文字阴影 / 锁定穿透 */
  private appendBehaviorItems(items: SettingSectionItem[]): void {
    const shadowOptions: SettingOption[] = [
      { label: t('lyric_shadow_black'), value: '#99000000' },
      { label: t('lyric_shadow_none'), value: '#00000000' },
      { label: t('lyric_shadow_white'), value: '#99FFFFFF' },
    ];

    items.push(toggleRow(t('lyric_anim'), this.animEnabled, (value: boolean): void => {
      this.animEnabled = value;
      void settingsService.update({ desktopLyricAnim: value });
    }));

    items.push(selectRow(t('lyric_shadow_title'), this.lyricShadowColor, shadowOptions, (value: string): void => {
      this.lyricShadowColor = value;
      this.persistAppearance({ desktopLyricShadowColor: value });
    }));

    items.push(toggleRow(t('lyric_lock_title'), this.locked, (value: boolean): void => {
      this.locked = value;
      void settingsService.update({ desktopLyricLocked: value });
      DesktopLyricManager.setLocked(value);
    }, t('lyric_lock_desc')));
  }

  build() {
    SettingsSection({
      title: t('settings_desktop_lyric'),
      items: this.buildItems(),
    })
  }
}
