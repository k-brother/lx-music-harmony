/**
 * 设置 → 关于
 *
 * 含运行日志（详细日志开关 + 进入日志页）、关于页、许可协议回看、版本信息。
 * 许可协议弹层由本组件自持，避免污染页面状态。
 */
import { settingsService } from '../../../service/SettingsService';
import { t, tf } from '../../../service/LocalizationService';
import { navigationService, RouteName } from '../../../service/NavigationService';
import { appToast } from '../../../service/DialogService';
import { logService } from '../../../service/LogService';
import { APP_VERSION } from '../../../service/VersionCheckService';
import { PactDialog } from '../../../components/common/PactDialog';
import { watchSettings } from '../../../service/SettingsWatcher';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import type { SettingSectionItem } from '../../../components/ui/SettingsTypes';

@Component
export struct AboutSection {
  @State enableVerboseLog: boolean = false;
  @State logCount: number = 0;
  @State showPact: boolean = false;

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
          logService.setVerbose(value);
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
    ];
  }

  build() {
    Stack() {
      SettingsSection({ title: t('settings_about'), items: this.buildItems() })

      if (this.showPact) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0, 0, 0, 0.45)')

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
