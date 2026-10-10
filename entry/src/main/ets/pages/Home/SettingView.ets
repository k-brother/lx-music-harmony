/**
 * 设置页（首页 = 分类入口）
 *
 * 首页只回答一个问题：「要调的那项属于哪一类」。每行点进一个二级页
 * （pages/Home/Setting/SettingsCategoryPage），具体设置项都在那边，
 * 所以设置项加到几十上百项，这一页也不会跟着变长。
 *
 * 分类目录（有哪些分类、顺序、文案）在 pages/Home/Setting/SettingsCatalog，
 * 这里只负责摆放；分组组件本身仍然在 pages/Home/Setting/ 下，没有被搬动。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { NavBar } from '../../components/ui/NavBar';
import { t } from '../../service/LocalizationService';
import { Breakpoints } from '../../theme/Breakpoints';
import { navigateTo } from '../../service/NavigationService';
import { SettingsSection } from '../../components/ui/SettingsSection';
import { buttonRow } from '../../components/ui/SettingsRows';
import type { SettingSectionItem } from '../../components/ui/SettingsTypes';
import {
  settingsHomeGroups,
  type SettingsCategoryGroup,
} from './Setting/SettingsCatalog';

@Component
export struct SettingView {
  @StorageProp('theme') theme: string = 'light';
  /** 一多：窗口宽度（vp），大屏时内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
  /** 语言版本号：分类文案是运行时算出来的，切语言后要跟着重渲染 */
  @StorageProp('langVersion') langVersion: number = 0;

  /** 一张卡片的行：每个分类一行，右侧箭头，点进对应二级页 */
  private buildRows(group: SettingsCategoryGroup): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];
    for (let i = 0; i < group.rows.length; i++) {
      const row = group.rows[i];
      items.push(buttonRow(row.title, (): void => {
        navigateTo(row.route);
      }, { description: row.desc }));
    }
    return items;
  }

  @Builder
  CategoryGroups() {
    ForEach(settingsHomeGroups(), (group: SettingsCategoryGroup, index: number) => {
      SettingsSection({
        title: group.title,
        items: this.buildRows(group),
      })
    }, (group: SettingsCategoryGroup, index: number): string => `${index}_${group.title}`)
  }

  build() {
    Column() {
      // 统一顶部栏：与其它二级页同一套（返回 + 居中标题 + 沉浸式安全区）
      NavBar({ title: t('settings_title') })

      Scroll() {
        Column() {
          this.CategoryGroups()
        }
        .width('100%')
        // 分组卡片左右留白（8pt 网格）；大屏额外居中，避免卡片被拉满整屏
        .padding({
          left: DesignTokens.spaceGutter() + Breakpoints.contentInset(this.windowWidthVp),
          right: DesignTokens.spaceGutter() + Breakpoints.contentInset(this.windowWidthVp),
          bottom: 28,
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
    // 顶部/底部安全区都由页面自己绘制（深色模式下底部手势区不能透出系统白底）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
