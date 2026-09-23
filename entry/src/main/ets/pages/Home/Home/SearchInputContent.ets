/**
 * 搜索输入态内容：联想词 / 热搜 / 搜索历史
 *
 * 从 HomePage 抽成组件：三种列表的取舍逻辑（一有输入就顶掉热搜与历史）与商业 App 一致，
 * 数据与四个点击回调由页面传入，组件不持有业务状态。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { t } from '../../../service/LocalizationService';
import type { HotSearchItem } from '../../../core/search/search';

@Component
export struct SearchInputContent {
  @StorageProp('theme') theme: string = 'light';
  @Prop searchText: string = '';
  @Prop tips: string[] = [];
  @Prop history: string[] = [];
  @Prop hotList: HotSearchItem[] = [];
  @Prop showHotSearch: boolean = true;
  @Prop showHistory: boolean = false;
  onTipClick?: (tip: string) => void;
  onHotClick?: (keyword: string) => void;
  onHistoryClick?: (keyword: string) => void;
  onClearHistory?: () => void;

  build() {
    Column() {
    Column() {
      // 联想词：一有输入就顶掉热搜/历史，与主流音乐 App 一致
      if (this.tips.length > 0 && this.searchText.trim().length > 0) {
        List() {
          ForEach(this.tips, (tip: string) => {
            ListItem() {
              Row() {
                SymbolGlyph($r('sys.symbol.magnifyingglass'))
                  .fontSize(18)
                  .fontColor([DesignTokens.labelTertiary(this.theme)])
                  .margin({ right: 10 })

                Text(tip)
                  .fontSize(16)
                  .fontColor(DesignTokens.labelPrimary(this.theme))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                SymbolGlyph($r('sys.symbol.arrow_up_left'))
                  .fontSize(17)
                  .fontColor([DesignTokens.labelTertiary(this.theme)])
              }
              .width('100%')
              .padding({
                left: DesignTokens.spaceGutter(),
                right: DesignTokens.spaceGutter(),
                top: 12,
                bottom: 12,
              })
              .alignItems(VerticalAlign.Center)
              .border({ width: { bottom: 0.33 }, color: DesignTokens.hairlineSeparator(this.theme) })
              .onClick(() => {
                if (this.onTipClick) { this.onTipClick(tip); }
              })
            }
          }, (tip: string) => tip)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }

      // 搜索历史：显示开关与条数分别由「设置 → 搜索设置」决定（对齐安卓版 search.isShowHistorySearch）
      if (this.tips.length === 0 && this.showHistory && this.history.length > 0) {
        Row() {
          Text(t('search_history'))
            .fontSize(13)
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)

          Text(t('search_clear_history'))
            .fontSize(13)
            .fontColor(DesignTokens.accent())
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .onClick(() => {
              if (this.onClearHistory) { this.onClearHistory(); }
            })
        }
        .width('100%')
        .padding({ left: DesignTokens.spaceGutter(), right: DesignTokens.spaceGutter() - 8, top: 8, bottom: 6 })

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.history, (word: string) => {
            Text(word)
              .fontSize(14)
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .backgroundColor(DesignTokens.mutedFill(this.theme))
              .borderRadius(14)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .margin({ right: 8, bottom: 8 })
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => {
                if (this.onHistoryClick) { this.onHistoryClick(word); }
              })
          }, (word: string) => word)
        }
        .width('100%')
        .padding({ left: DesignTokens.spaceGutter(), right: DesignTokens.spaceGutter() })
      }

      if (this.tips.length === 0 && this.showHotSearch) {
      // 热搜标题（小号大写感：次级标签样式）
      Row() {
        Text(t('search_hot'))
          .fontSize(13)
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .fontWeight(FontWeight.Medium)
      }
      .width('100%')
      .padding({ left: DesignTokens.spaceGutter(), top: 8, bottom: 6 })

      // 热搜列表
      List() {
        ForEach(this.hotList, (item: HotSearchItem) => {
          ListItem() {
            Row() {
              Text((item.index).toString())
                .fontSize(15)
                .fontColor(item.index <= 3 ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme))
                .fontWeight(item.index <= 3 ? FontWeight.Medium : FontWeight.Normal)
                .width(28)

              Text(item.title)
                .fontSize(16)
                .fontColor(DesignTokens.labelPrimary(this.theme))
                .layoutWeight(1)

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(17)
                .fontColor([DesignTokens.labelTertiary(this.theme)])
            }
            .width('100%')
            .padding({
              left: DesignTokens.spaceGutter(),
              right: DesignTokens.spaceGutter(),
              top: 12,
              bottom: 12,
            })
            .border({ width: { bottom: 0.33 }, color: DesignTokens.hairlineSeparator(this.theme) })
            .onClick(() => {
              if (this.onHotClick) { this.onHotClick(item.title); }
            })
          }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(DesignTokens.pageBg(this.theme))
      } else if (this.history.length === 0) {
        Column() {
          Text(t('search_no_hot'))
            .fontSize(15)
            .fontColor(DesignTokens.labelSecondary(this.theme))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  /** 搜索类型胶囊 */
  }
}
