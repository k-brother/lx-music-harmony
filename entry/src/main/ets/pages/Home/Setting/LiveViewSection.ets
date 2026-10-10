/**
 * 设置 → 实况窗
 *
 * 总开关 + 系统约束说明。开启后经 LiveViewService.syncEnabled() 即时生效：
 * 播放中会立即补创建实况窗，关闭则立即销毁（不需要等下一次播放事件）。
 * 另受系统「实况窗」总开关约束，系统侧关闭时本开关无效（服务里 best-effort 跳过）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { toggleRow, infoRow } from '../../../components/ui/SettingsRows';
import { settingsService } from '../../../service/SettingsService';
import { t } from '../../../service/LocalizationService';
import { appToast } from '../../../service/DialogService';
import { liveViewService } from '../../../service/LiveViewService';
import { Subscription } from '../../../service/Subscription';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import type { SettingSectionItem } from '../../../components/ui/SettingsTypes';

const DOMAIN = 0x0001;
const TAG = 'LiveViewSection';

@Component
export struct LiveViewSection {
  @State liveViewEnabled: boolean = false;
  private settingsWatch: Subscription = new Subscription();

  aboutToAppear() {
    this.loadFromSettings();
    // 外部改动（恢复备份 / 同步下发）也要刷新本分组
    this.settingsWatch.bindSettings((): void => {
      this.loadFromSettings();
    });
  }

  aboutToDisappear() {
    this.settingsWatch.detach();
  }

  private loadFromSettings(): void {
    this.liveViewEnabled = settingsService.get().enableLiveView;
  }

  private buildItems(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];
    items.push(toggleRow(t('live_view'), this.liveViewEnabled, (value: boolean): void => {
      this.liveViewEnabled = value;
      void settingsService.update({ enableLiveView: value }).then((): void => {
        liveViewService.syncEnabled();
      }).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'update enableLiveView failed: %{public}s', err.message);
      });
      appToast(value ? t('toast_live_view_on') : t('toast_live_view_off'));
    }, t('live_view_desc')));
    if (this.liveViewEnabled) {
      items.push(infoRow(t('live_view_hint'), '', t('live_view_hint_desc')));
    }
    return items;
  }

  build() {
    SettingsSection({
      title: t('settings_live_view'),
      items: this.buildItems(),
    })
  }
}
