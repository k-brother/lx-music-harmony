/**
 * 设置 → 关于
 *
 * 含运行日志（详细日志开关 + 进入日志页）、关于页、许可协议回看、版本信息。
 * 许可协议弹层由本组件自持，避免污染页面状态。
 */
import { settingsService } from '../../../service/SettingsService';
import { t, tf } from '../../../service/LocalizationService';
import { navigationService, RouteName } from '../../../service/NavigationService';
import { appConfirm, appToast } from '../../../service/DialogService';
import { logService } from '../../../service/LogService';
import { APP_VERSION } from '../../../service/VersionCheckService';
import { PactDialog } from '../../../components/common/PactDialog';
import { Subscription } from '../../../service/Subscription';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import type { SettingSectionItem } from '../../../components/ui/SettingsTypes';
import { DesignTokens } from '../../../theme/DesignTokens';

@Component
export struct AboutSection {
  @State enableVerboseLog: boolean = false;
  @State logCount: number = 0;
  @State showPact: boolean = false;

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
    this.enableVerboseLog = settingsService.get().enableVerboseLog;
    try {
      this.logCount = logService.count();
    } catch (err) {
      this.logCount = 0;
    }  }

  private buildItems(): SettingSectionItem[] {
    return [
      {
        type: 'toggle',
        title: t('settings_log_verbose'),
        description: t('settings_log_verbose_desc'),
        value: this.enableVerboseLog,
        onChangeToggle: (value: boolean): void => {
          this.enableVerboseLog = value;
          void settingsService.update({ enableVerboseLog: value });
        },
      },
      {
        type: 'button',
        title: t('settings_logs'),
        description: tf('settings_logs_desc', [this.logCount.toString()]),
        onClick: (): void => {
          navigationService.navigateTo(RouteName.LOGS);
        },
      },
      {
        type: 'button',
        title: t('settings_about_lx'),
        onClick: (): void => {
          navigationService.navigateTo(RouteName.ABOUT);
        },
      },
      {
        type: 'button',
        title: t('pact_title'),
        onClick: (): void => {
          this.showPact = true;
        },
      },
      {
        type: 'button',
        title: t('settings_version'),
        description: `v${APP_VERSION} (HarmonyOS)`,
        onClick: (): void => {
          appToast(`LX Music v${APP_VERSION}\nHarmonyOS NEXT`);
        },
      },
      {
        type: 'button',
        title: t('settings_reset'),
        description: t('settings_reset_desc'),
        danger: true,
        onClick: (): void => {
          void this.resetSettings();
        },
      },
    ];
  }

  /**
   * 恢复默认设置。
   *
   * 危险操作：二次确认后整包写回默认值（SettingsService.resetToDefaults）。
   * 已同意过协议的状态不会被回退，避免用户莫名其妙被重新拦住。
   */
  private async resetSettings(): Promise<void> {
    const confirmed = await appConfirm(
      t('settings_reset'),
      t('confirm_reset_settings'),
      { danger: true });
    if (!confirmed) {
      return;
    }
    await settingsService.resetToDefaults();
    appToast(t('toast_settings_reset'));
    this.loadFromSettings();
  }

  build() {
    Stack() {
      SettingsSection({ title: t('settings_about'), items: this.buildItems() })

      if (this.showPact) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(DesignTokens.maskColor())

          PactDialog({
            readonlyMode: true,
            visible: true,
            onClose: (): void => {
              this.showPact = false;
            },
          })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
  }
}
