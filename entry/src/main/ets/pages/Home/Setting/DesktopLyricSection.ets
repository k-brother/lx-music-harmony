/**
 * 设置 → 桌面歌词
 *
 * 开关 / 预设样式 / 位置 / 颜色（未播放行 + 当前行）/ 文字位置与不透明度 / 背景不透明度 /
 * 字号 / 字重 / 描边宽度与颜色 / 圆角 / 内边距 / 单双行 / 行数 / 宽度 / 行切换动画与方式 /
 * 阴影色 / 锁定穿透。
 * 外观类改动统一调用 DesktopLyricManager.applyAppearance() 让子窗口立即重算。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { selectRow, toggleRow, infoRow } from '../../../components/ui/SettingsRows';
import {
  settingsService,
  type AppSettings,
  type DesktopLyricPosition,
  type SettingsPatch,
  toDlFontWeight,
  toDlAnimStyle,
} from '../../../service/SettingsService';
import { t } from '../../../service/LocalizationService';
import { appToast } from '../../../service/DialogService';
import { DesktopLyricManager } from '../../../components/common/DesktopLyric';
import { Subscription } from '../../../service/Subscription';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import type { SettingOption, SettingSectionItem } from '../../../components/ui/SettingsTypes';

const DOMAIN = 0x0001;
const TAG = 'DesktopLyricSection';
/** 预设样式选择里代表「当前设置不匹配任何预设」的那一项 */
const PRESET_CUSTOM: string = 'custom';

/**
 * 一键预设：把互相耦合的几项（背景/描边/字重/圆角/内边距/动画）打包成一种观感。
 * 单看某一项很难调出"自然"的效果，预设让用户一步到位，再按需微调。
 */
interface LyricStylePreset {
  id: string;
  patch: SettingsPatch;
}

const LYRIC_PRESETS: LyricStylePreset[] = [
  {
    id: 'natural',
    patch: {
      desktopLyricBgAlpha: 0,
      desktopLyricOutlineWidth: 1,
      desktopLyricOutlineColor: '#CC000000',
      desktopLyricShadowColor: '#99000000',
      desktopLyricFontWeight: 'medium',
      desktopLyricCornerRadius: 12,
      desktopLyricPadding: 16,
      desktopLyricAnimStyle: 'slide',
    },
  },
  {
    id: 'minimal',
    patch: {
      desktopLyricBgAlpha: 0,
      desktopLyricOutlineWidth: 0,
      desktopLyricShadowColor: '#00000000',
      desktopLyricFontWeight: 'normal',
      desktopLyricCornerRadius: 0,
      desktopLyricPadding: 8,
      desktopLyricAnimStyle: 'fade',
    },
  },
  {
    id: 'contrast',
    patch: {
      desktopLyricBgAlpha: 55,
      desktopLyricOutlineWidth: 2,
      desktopLyricOutlineColor: '#E6000000',
      desktopLyricShadowColor: '#CC000000',
      desktopLyricFontWeight: 'bold',
      desktopLyricCornerRadius: 8,
      desktopLyricPadding: 20,
      desktopLyricAnimStyle: 'none',
    },
  },
  {
    id: 'ktv',
    patch: {
      desktopLyricBgAlpha: 30,
      desktopLyricOutlineWidth: 1,
      desktopLyricOutlineColor: '#B3000000',
      desktopLyricShadowColor: '#99000000',
      desktopLyricFontWeight: 'bold',
      desktopLyricCornerRadius: 18,
      desktopLyricPadding: 16,
      desktopLyricAnimStyle: 'slide',
      desktopLyricColor: '#FFFFFF',
      desktopLyricPlayedColor: '#07C556',
    },
  },
];

/** 预设名称：用字面量取词条，动态拼键会让 i18n 检查追踪不到引用 */
function presetLabel(id: string): string {
  if (id === 'natural') {
    return t('lyric_preset_natural');
  }
  if (id === 'minimal') {
    return t('lyric_preset_minimal');
  }
  if (id === 'contrast') {
    return t('lyric_preset_contrast');
  }
  if (id === 'ktv') {
    return t('lyric_preset_ktv');
  }
  return t('lyric_preset_custom');
}

/** patch 里声明的每一项都要与当前设置一致 */
function presetMatches(patch: SettingsPatch, settings: AppSettings): boolean {
  if (patch.desktopLyricBgAlpha !== undefined && patch.desktopLyricBgAlpha !== settings.desktopLyricBgAlpha) {
    return false;
  }
  if (patch.desktopLyricOutlineWidth !== undefined
    && patch.desktopLyricOutlineWidth !== settings.desktopLyricOutlineWidth) {
    return false;
  }
  if (patch.desktopLyricOutlineColor !== undefined
    && patch.desktopLyricOutlineColor !== settings.desktopLyricOutlineColor) {
    return false;
  }
  if (patch.desktopLyricShadowColor !== undefined
    && patch.desktopLyricShadowColor !== settings.desktopLyricShadowColor) {
    return false;
  }
  if (patch.desktopLyricFontWeight !== undefined
    && patch.desktopLyricFontWeight !== settings.desktopLyricFontWeight) {
    return false;
  }
  if (patch.desktopLyricCornerRadius !== undefined
    && patch.desktopLyricCornerRadius !== settings.desktopLyricCornerRadius) {
    return false;
  }
  if (patch.desktopLyricPadding !== undefined && patch.desktopLyricPadding !== settings.desktopLyricPadding) {
    return false;
  }
  if (patch.desktopLyricAnimStyle !== undefined && patch.desktopLyricAnimStyle !== settings.desktopLyricAnimStyle) {
    return false;
  }
  if (patch.desktopLyricColor !== undefined && patch.desktopLyricColor !== settings.desktopLyricColor) {
    return false;
  }
  if (patch.desktopLyricPlayedColor !== undefined
    && patch.desktopLyricPlayedColor !== settings.desktopLyricPlayedColor) {
    return false;
  }
  return true;
}

/** 由当前外观项反推预设：全部命中才算命中，否则显示「自定义」 */
function matchPreset(settings: AppSettings): string {
  for (const preset of LYRIC_PRESETS) {
    if (presetMatches(preset.patch, settings)) {
      return preset.id;
    }
  }
  return PRESET_CUSTOM;
}


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
  @State lyricOutlineWidth: number = 1;
  @State lyricOutlineColor: string = '#CC000000';
  @State lyricFontWeight: string = 'medium';
  @State cornerRadius: number = 12;
  @State panelPadding: number = 16;
  @State animStyle: string = 'slide';
  /** 当前匹配到的预设 id（不落盘，由各外观项反推） */
  @State presetId: string = PRESET_CUSTOM;
  @State locked: boolean = false;
  /** 是否由系统原生歌词接管（决定提示文案） */
  @State usingSystemLyric: boolean = false;

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
    this.lyricOutlineWidth = settings.desktopLyricOutlineWidth;
    this.lyricOutlineColor = settings.desktopLyricOutlineColor;
    this.lyricFontWeight = settings.desktopLyricFontWeight;
    this.cornerRadius = settings.desktopLyricCornerRadius;
    this.panelPadding = settings.desktopLyricPadding;
    this.animStyle = settings.desktopLyricAnimStyle;
    this.locked = settings.desktopLyricLocked;
    this.presetId = matchPreset(settings);
    // 系统歌词接管状态由 DesktopLyricManager 持有：用户在系统侧关掉歌词时，
    // 这里会随设置变化事件一起刷新，提示文案不会停在「正在使用系统原生歌词」
    this.usingSystemLyric = DesktopLyricManager.isUsingSystemLyric();
  }

  /** 应用预设：一次性写入整套外观，再同步本地状态 */
  private applyPreset(presetId: string): void {
    if (presetId === PRESET_CUSTOM) {
      return;
    }
    const preset: LyricStylePreset | undefined = LYRIC_PRESETS.find(
      (item: LyricStylePreset): boolean => item.id === presetId);
    if (!preset) {
      return;
    }
    this.persistAppearance(preset.patch, (): void => {
      this.loadFromSettings();
      appToast(t('toast_lyric_preset_applied'));
    });
  }

  /** 外观类设置改动后让子窗口立即重算尺寸/配色 */
  private persistAppearance(patch: SettingsPatch, after?: () => void): void {
    settingsService.update(patch).then((): void => {
      DesktopLyricManager.applyAppearance();
      if (after) {
        after();
      }
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

  /**
   * 每一类设置项各成一张卡片：开关与状态 / 位置与颜色 / 文字与排版 / 外观样式 / 行为。
   *
   * 原来这 24 项挤在同一张卡片里，找「描边宽度」要顺着屏幕翻半天；
   * 装配函数本来就按用途拆好了（appendStatusItems 等），这里只是让卡片跟它们一一对应。
   * 分组口径见各组函数的注释。
   */
  private statusItems(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];
    this.appendStatusItems(items);
    return items;
  }

  private positionItems(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];
    this.appendPositionItems(items);
    return items;
  }

  private textItems(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];
    this.appendTextItems(items);
    return items;
  }

  private styleItems(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];
    this.appendStyleItems(items);
    return items;
  }

  private behaviorItems(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];
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

  /**
   * 描边与观感：预设 / 描边宽度与颜色 / 字重 / 圆角 / 内边距。
   * 这几项共同决定"没有黑底也自然"的效果，所以放在一起，先给预设再给细项。
   */
  private appendStyleItems(items: SettingSectionItem[]): void {
    const presetOptions: SettingOption[] = LYRIC_PRESETS.map((preset: LyricStylePreset): SettingOption => {
      return { label: presetLabel(preset.id), value: preset.id };
    });
    presetOptions.push({ label: presetLabel(PRESET_CUSTOM), value: PRESET_CUSTOM });

    const outlineOptions: SettingOption[] = [
      { label: t('lyric_outline_off'), value: '0' },
      { label: '1', value: '1' },
      { label: '2', value: '2' },
      { label: '3', value: '3' },
    ];
    const outlineColorOptions: SettingOption[] = [
      { label: t('lyric_shadow_black'), value: '#CC000000' },
      { label: t('lyric_shadow_white'), value: '#CCFFFFFF' },
      { label: t('lyric_shadow_none'), value: '#00000000' },
    ];
    const weightOptions: SettingOption[] = [
      { label: t('lyric_weight_light'), value: 'light' },
      { label: t('lyric_weight_normal'), value: 'normal' },
      { label: t('lyric_weight_medium'), value: 'medium' },
      { label: t('lyric_weight_bold'), value: 'bold' },
    ];
    const radiusOptions: SettingOption[] = [
      { label: '0', value: '0' },
      { label: '8', value: '8' },
      { label: '12', value: '12' },
      { label: '20', value: '20' },
    ];
    const paddingOptions: SettingOption[] = [
      { label: '0', value: '0' },
      { label: '8', value: '8' },
      { label: '16', value: '16' },
      { label: '24', value: '24' },
    ];

    items.push(selectRow(t('lyric_preset_title'), this.presetId, presetOptions, (value: string): void => {
      this.applyPreset(value);
    }, t('lyric_preset_desc')));

    items.push(selectRow(t('lyric_outline_width'), this.lyricOutlineWidth.toString(), outlineOptions,
      (value: string): void => {
        const width = parseInt(value);
        if (isNaN(width)) {
          return;
        }
        this.lyricOutlineWidth = width;
        this.persistAppearance({ desktopLyricOutlineWidth: width });
      }));

    items.push(selectRow(t('lyric_outline_color'), this.lyricOutlineColor, outlineColorOptions, (value: string): void => {
      this.lyricOutlineColor = value;
      this.persistAppearance({ desktopLyricOutlineColor: value });
    }));

    items.push(selectRow(t('lyric_font_weight'), this.lyricFontWeight, weightOptions, (value: string): void => {
      this.lyricFontWeight = value;
      this.persistAppearance({ desktopLyricFontWeight: toDlFontWeight(value) });
    }));

    items.push(selectRow(t('lyric_corner_radius'), this.cornerRadius.toString(), radiusOptions,
      (value: string): void => {
        const radius = parseInt(value);
        if (isNaN(radius)) {
          return;
        }
        this.cornerRadius = radius;
        this.persistAppearance({ desktopLyricCornerRadius: radius });
      }));

    items.push(selectRow(t('lyric_padding'), this.panelPadding.toString(), paddingOptions,
      (value: string): void => {
        const padding = parseInt(value);
        if (isNaN(padding)) {
          return;
        }
        this.panelPadding = padding;
        this.persistAppearance({ desktopLyricPadding: padding });
      }));
  }

  /** 行为：动画 / 动画方式 / 文字阴影 / 锁定穿透 */
  private appendBehaviorItems(items: SettingSectionItem[]): void {
    const shadowOptions: SettingOption[] = [
      { label: t('lyric_shadow_black'), value: '#99000000' },
      { label: t('lyric_shadow_none'), value: '#00000000' },
      { label: t('lyric_shadow_white'), value: '#99FFFFFF' },
    ];
    const animStyleOptions: SettingOption[] = [
      { label: t('lyric_anim_slide'), value: 'slide' },
      { label: t('lyric_anim_fade'), value: 'fade' },
      { label: t('lyric_anim_none'), value: 'none' },
    ];

    items.push(toggleRow(t('lyric_anim'), this.animEnabled, (value: boolean): void => {
      this.animEnabled = value;
      this.persistAppearance({ desktopLyricAnim: value });
    }));

    items.push(selectRow(t('lyric_anim_style'), this.animStyle, animStyleOptions, (value: string): void => {
      this.animStyle = value;
      this.persistAppearance({ desktopLyricAnimStyle: toDlAnimStyle(value) });
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
    Column() {
      SettingsSection({ title: t('settings_desktop_lyric'), items: this.statusItems() })
      SettingsSection({ title: t('lyric_group_position'), items: this.positionItems() })
      SettingsSection({ title: t('lyric_group_text'), items: this.textItems() })
      SettingsSection({ title: t('lyric_group_style'), items: this.styleItems() })
      SettingsSection({ title: t('lyric_group_behavior'), items: this.behaviorItems() })
    }
    .width('100%')
  }
}
