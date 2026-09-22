/**
 * 设置页（编排层）
 *
 * 2971 行 → ~120 行：页面只负责「按顺序摆放分组组件 + 统一外边距」，
 * 每个分组的视觉/状态/交互/持久化都在 pages/Home/Setting/ 下的组件里，
 * 分组自身通过 SettingsSection（分组卡片）与 DialogService（确认/菜单/提示）统一呈现。
 *
 * 之所以这样拆：
 * - 原来 40 个 @State + 12 个构造器 + 备份导入导出混在一个页面里，改一处要读整页；
 * - 现在「某个设置不生效」只需要看对应分组那 100~200 行，定位成本低一个数量级；
 * - 新增设置项 = 加一个分组组件或往现有分组的 items 里加一项，不会互相踩状态。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { BasicSection } from './Setting/BasicSection';
import { PlaybackSection } from './Setting/PlaybackSection';
import { DownloadSection } from './Setting/DownloadSection';
import { SearchSection } from './Setting/SearchSection';
import { ListSection } from './Setting/ListSection';
import { StorageSection } from './Setting/StorageSection';
import { BackupSection } from './Setting/BackupSection';
import { SyncSection } from './Setting/SyncSection';
import { AppearanceSection } from './Setting/AppearanceSection';
import { DesktopLyricSection } from './Setting/DesktopLyricSection';
import { CustomSourceSection } from './Setting/CustomSourceSection';
import { AboutSection } from './Setting/AboutSection';

@Component
export struct SettingView {
  @StorageProp('theme') theme: string = 'light';

  build() {
    Scroll() {
      Column() {
        BasicSection()
        PlaybackSection()
        DownloadSection()
        SearchSection()
        ListSection()
        StorageSection()
        BackupSection()
        SyncSection()
        AppearanceSection()
        DesktopLyricSection()
        CustomSourceSection()
        AboutSection()
      }
      .width('100%')
      // 分组卡片左右留白（8pt 网格，和商业化设置页一致）
      .padding({ left: DesignTokens.spaceGutter(), right: DesignTokens.spaceGutter(), bottom: 28 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }
}
