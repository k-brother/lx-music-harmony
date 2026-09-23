// Index 页面 - 应用入口页面，使用 Navigation 组件
import hilog from '@ohos.hilog';
import { appConfirm } from '../service/DialogService';
import type { BusinessError } from '@kit.BasicServicesKit';
import type { common } from '@kit.AbilityKit';
import { NavIndex } from './NavIndex';
import { t } from '../service/LocalizationService';
import { settingsService } from '../service/SettingsService';

const TAG = 'Index';
const DOMAIN = 0x0001;

/** PromptAction 对话框回调数据 */
interface PromptDialogResult {
  index: number;
}

@Entry
@Component
struct Index {
  /** 退出确认弹窗是否正在显示，避免重复弹出 */
  private exitDialogShowing: boolean = false;

  aboutToAppear() {
    hilog.info(DOMAIN, TAG, 'Index page appearing - loading NavIndex with Navigation component');
  }

  /**
   * 返回键：开启「退出确认对话框」时先确认，否则交给系统默认行为（退到后台）。
   */
  onBackPress(): boolean {
    if (!settingsService.get().showExitDialog) {
      return false;
    }
    if (this.exitDialogShowing) {
      return true;
    }
    this.exitDialogShowing = true;
    // 统一走 DialogService 的危险确认；确认后退出应用（颜色不再硬编码）
    appConfirm(t('confirm_exit'), t('confirm_exit_msg'),
      { danger: true, confirmText: t('confirm') }).then((confirmed: boolean): void => {
      this.exitDialogShowing = false;
      if (!confirmed) {
        return;
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.terminateSelf().catch((terminateErr: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'terminateSelf failed: %{public}s', terminateErr.message);
      });
    }).catch((err: Error): void => {
      this.exitDialogShowing = false;
      hilog.warn(DOMAIN, TAG, 'Exit confirm dialog failed: %{public}s', err.message);
    });
    return true;
  }

  build() {
    Column() {
      NavIndex()
    }
  }
}
