/**
 * 设置 → 播放
 *
 * 播放行为（自动播放 / 音质 / 播放模式 / 音量）、音频（焦点 / Offload / 缓存上限）、
 * 播控（封面 / 蓝牙歌词）、歌词简繁、睡眠定时（含"播完再退"与取消等待）。
 */
import hilog from '@ohos.hilog';
import { settingsService, type PlayMode } from '../../../service/SettingsService';
import { t } from '../../../service/LocalizationService';
import { appToast } from '../../../service/DialogService';
import { playerService } from '../../../service/PlayerService';
import { sleepTimerService, type SleepTimerState } from '../../../service/SleepTimerService';
import { watchSettings } from '../../../service/SettingsWatcher';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import type { SettingOption, SettingSectionItem } from '../../../components/ui/SettingsTypes';
import type { Quality } from '../../../types/MusicTypes';

const DOMAIN = 0x0001;
const TAG = 'PlaybackSection';

@Component
export struct PlaybackSection {
  @State autoPlay: boolean = false;
  @State playQuality: string = '128k';
  @State playMode: string = 'listLoop';
  @State volume: number = 80;
  @State savePlayTime: boolean = true;
  @State showNotificationImage: boolean = true;
  @State showBluetoothLyric: boolean = false;
  @State s2tMode: string = 'off';
  @State audioFocus: boolean = true;
  @State audioOffload: boolean = false;
  @State playerCacheSizeMb: number = 4;
  @State sleepTimerEnabled: boolean = false;
  @State sleepTimerMinutes: number = 30;
  @State sleepWaitTrackEnd: boolean = true;
  /** 定时到点后正在等当前歌曲播完（此时开关语义变为"取消退出"） */
  @State waitingTrackEnd: boolean = false;
  private sleepUnsub: (() => void) | null = null;

  private settingsUnsub: (() => void) | null = null;

  aboutToAppear() {
    this.loadFromSettings();
    // 外部改动（恢复备份 / 同步下发 / 播放页改设置）也要刷新本分组
    this.settingsUnsub = watchSettings((): void => {
      this.loadFromSettings();
    });
    this.sleepUnsub = sleepTimerService.onStateChange((state: SleepTimerState): void => {
      this.sleepTimerEnabled = state.enabled || state.waitingTrackEnd;
      this.waitingTrackEnd = state.waitingTrackEnd;
    });
  }

  /** 从设置服务读取本分组的当前值 */
  private loadFromSettings(): void {
    const settings = settingsService.get();
    this.autoPlay = settings.autoPlay;
    this.playQuality = settings.playQuality;
    this.playMode = settings.playMode;
    this.volume = settings.volume;
    this.savePlayTime = settings.savePlayTime;
    this.showNotificationImage = settings.showNotificationImage;
    this.showBluetoothLyric = settings.showBluetoothLyric;
    this.s2tMode = settings.s2tMode;
    this.audioFocus = settings.audioFocus;
    this.audioOffload = settings.audioOffload;
    this.playerCacheSizeMb = settings.playerCacheSizeMb;
    this.sleepTimerEnabled = settings.sleepTimerEnabled;
    this.sleepTimerMinutes = settings.sleepTimerMinutes;
    this.sleepWaitTrackEnd = settings.sleepTimerWaitTrackEnd;
  }

  aboutToDisappear() {
    if (this.sleepUnsub) {
      this.sleepUnsub();
      this.sleepUnsub = null;
    }
    if (this.settingsUnsub) {
      this.settingsUnsub();
      this.settingsUnsub = null;
    }
  }

  private buildItems(): SettingSectionItem[] {
    const qualityOptions: SettingOption[] = [
      { label: t('quality_128k'), value: '128k' },
      { label: t('quality_320k'), value: '320k' },
      { label: t('quality_flac'), value: 'flac' },
      { label: t('quality_flac24bit'), value: 'flac24bit' },
    ];
    const playModeOptions: SettingOption[] = [
      { label: t('mode_list_loop'), value: 'listLoop' },
      { label: t('mode_single_loop'), value: 'singleLoop' },
      { label: t('mode_random'), value: 'random' },
      { label: t('mode_sequential'), value: 'sequential' },
    ];
    const cacheOptions: SettingOption[] = [
      { label: '1 MB', value: '1' },
      { label: '2 MB', value: '2' },
      { label: '4 MB', value: '4' },
      { label: '8 MB', value: '8' },
      { label: '16 MB', value: '16' },
    ];
    const s2tOptions: SettingOption[] = [
      { label: t('settings_s2t_off'), value: 'off' },
      { label: t('settings_s2t_to_traditional'), value: 's2t' },
      { label: t('settings_s2t_to_simplified'), value: 't2s' },
    ];

    const items: SettingSectionItem[] = [];

    items.push({
      type: 'toggle',
      title: t('settings_auto_play'),
      value: this.autoPlay,
      onChangeToggle: (value: boolean): void => {
        this.autoPlay = value;
        void settingsService.update({ autoPlay: value });
      },
    });

    items.push({
      type: 'select',
      title: t('settings_high_quality'),
      description: t('settings_high_quality_desc'),
      value: this.playQuality,
      options: qualityOptions,
      onChange: (value: string): void => {
        this.playQuality = value;
        void settingsService.update({ playQuality: value as Quality });
        appToast(`${t('settings_high_quality')}: ${this.labelOf(qualityOptions, value)}`);
      },
    });

    items.push({
      type: 'select',
      title: t('settings_play_mode'),
      value: this.playMode,
      options: playModeOptions,
      onChange: (value: string): void => {
        this.playMode = value;
        playerService.setPlayMode(value as PlayMode);
        void settingsService.update({ playMode: value as PlayMode });
        appToast(t('toast_mode_changed'));
      },
    });

    items.push({
      type: 'input',
      title: t('settings_volume'),
      description: t('settings_volume_desc'),
      value: this.volume.toString(),
      onChange: (value: string): void => {
        const volume = parseInt(value);
        if (isNaN(volume) || volume < 0 || volume > 100) {
          appToast(t('settings_volume_desc'));
          return;
        }
        this.volume = volume;
        void settingsService.update({ volume });
        playerService.setVolume(volume / 100).catch((err: Error) => {
          hilog.warn(DOMAIN, TAG, 'setVolume failed: %{public}s', err.message);
        });
        appToast(`${t('toast_volume_set')} ${volume}`);
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_save_play_time'),
      description: t('settings_save_play_time_desc'),
      value: this.savePlayTime,
      onChangeToggle: (value: boolean): void => {
        this.savePlayTime = value;
        void settingsService.update({ savePlayTime: value });
        if (!value) {
          playerService.clearSavedProgress();
        }
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_audio_focus'),
      description: t('settings_audio_focus_desc'),
      value: this.audioFocus,
      onChangeToggle: (value: boolean): void => {
        this.audioFocus = value;
        void settingsService.update({ audioFocus: value });
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_audio_offload'),
      description: t('settings_audio_offload_desc'),
      value: this.audioOffload,
      onChangeToggle: (value: boolean): void => {
        this.audioOffload = value;
        void settingsService.update({ audioOffload: value });
      },
    });

    items.push({
      type: 'select',
      title: t('settings_cache_size'),
      description: t('settings_cache_size_desc'),
      value: this.playerCacheSizeMb.toString(),
      options: cacheOptions,
      onChange: (value: string): void => {
        const mb = parseInt(value);
        if (isNaN(mb)) {
          return;
        }
        this.playerCacheSizeMb = mb;
        void settingsService.update({ playerCacheSizeMb: mb });
        appToast(`${t('settings_cache_size')}: ${mb} MB`);
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_notification_image'),
      description: t('settings_notification_image_desc'),
      value: this.showNotificationImage,
      onChangeToggle: (value: boolean): void => {
        this.showNotificationImage = value;
        void settingsService.update({ showNotificationImage: value });
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_bluetooth_lyric'),
      description: t('settings_bluetooth_lyric_desc'),
      value: this.showBluetoothLyric,
      onChangeToggle: (value: boolean): void => {
        this.showBluetoothLyric = value;
        void settingsService.update({ showBluetoothLyric: value });
      },
    });

    items.push({
      type: 'select',
      title: t('settings_s2t'),
      description: t('settings_s2t_desc'),
      value: this.s2tMode,
      options: s2tOptions,
      onChange: (value: string): void => {
        this.s2tMode = value;
        void settingsService.update({ s2tMode: value === 's2t' ? 's2t' : (value === 't2s' ? 't2s' : 'off') });
        // 正在播放时立即生效，无需重新请求歌词
        playerService.applyLyricConversion();
        appToast(`${t('settings_s2t')}: ${this.labelOf(s2tOptions, value)}`);
      },
    });

    return items;
  }

  /** 睡眠定时单独一组（含等待播完的取消入口） */
  private buildSleepItems(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];

    items.push({
      type: 'toggle',
      title: this.waitingTrackEnd ? t('sleep_cancel_wait') : t('settings_sleep_timer'),
      description: this.waitingTrackEnd ? t('sleep_waiting_track') : '',
      value: this.sleepTimerEnabled,
      onChangeToggle: (value: boolean): void => {
        if (this.waitingTrackEnd) {
          // 等待播完时，开关语义是"取消退出"
          sleepTimerService.cancelPendingExit();
          this.waitingTrackEnd = false;
          this.sleepTimerEnabled = false;
          appToast(t('toast_sleep_cancel'));
          return;
        }
        this.sleepTimerEnabled = value;
        if (value) {
          sleepTimerService.start(this.sleepTimerMinutes);
          appToast(`${t('toast_sleep_set')} ${this.sleepTimerMinutes} ${t('toast_sleep_start')}`);
        } else {
          sleepTimerService.stop();
          appToast(t('toast_sleep_cancel'));
        }
      },
    });

    items.push({
      type: 'input',
      title: t('settings_sleep_minutes'),
      description: t('settings_sleep_minutes_desc'),
      value: this.sleepTimerMinutes.toString(),
      onChange: (value: string): void => {
        const minutes = parseInt(value);
        if (isNaN(minutes) || minutes <= 0) {
          appToast(t('settings_sleep_minutes_desc'));
          return;
        }
        this.sleepTimerMinutes = minutes;
        void settingsService.update({ sleepTimerMinutes: minutes });
        sleepTimerService.setMinutes(minutes);
        appToast(`${t('toast_sleep_set')} ${minutes} ${t('settings_sleep_minutes')}`);
      },
    });

    items.push({
      type: 'toggle',
      title: t('settings_sleep_wait_track'),
      description: t('settings_sleep_wait_track_desc'),
      value: this.sleepWaitTrackEnd,
      onChangeToggle: (value: boolean): void => {
        this.sleepWaitTrackEnd = value;
        void settingsService.update({ sleepTimerWaitTrackEnd: value });
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
    Column() {
      SettingsSection({ title: t('settings_playback'), items: this.buildItems() })
      SettingsSection({ title: t('settings_sleep_timer'), items: this.buildSleepItems() })
    }
    .width('100%')
  }
}
