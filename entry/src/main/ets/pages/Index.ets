// Index 页面 - 应用入口页面，使用 Navigation 组件
import hilog from '@ohos.hilog';
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
    try {
      this.getUIContext().getPromptAction().showDialog({
        title: t('confirm_exit'),
        message: t('confirm_exit_msg'),
        buttons: [
          { text: t('cancel'), color: '#8E8E93' },
          { text: t('confirm'), color: '#E63946' },
        ],
      }, (err: BusinessError, data: PromptDialogResult) => {
        this.exitDialogShowing = false;
        if (err) {
          hilog.warn(DOMAIN, TAG, 'Exit confirm dialog failed: %{public}s', err.message);
          return;
        }
        if (data.index === 1) {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
          context.terminateSelf().catch((terminateErr: BusinessError) => {
            hilog.error(DOMAIN, TAG, 'terminateSelf failed: %{public}s', terminateErr.message);
          });
        }
      });
    } catch (err) {
      this.exitDialogShowing = false;
      hilog.error(DOMAIN, TAG, 'showExitConfirm failed: %{public}s', JSON.stringify(err));
    }
    return true;
  }

  build() {
    Column() {
      NavIndex()
    }
  }
}
