/**
 * 排行榜搜索覆盖层
 *
 * 从 LeaderboardView 的 @Builder 抽成组件：顶部搜索框 + 取消，下面是榜单名匹配结果。
 * 列表数据与两个回调由页面传入；输入框用 @Link 承接（与 SearchStrip 一致的做法）。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { t } from '../../../service/LocalizationService';
import { SearchStrip, SearchStripActions } from '../../../components/common/SearchStrip';
import type { BoardItem } from '../../../store/leaderboard/LeaderboardStoreState';

@Component
export struct LeaderboardSearchOverlay {
  @StorageProp('theme') theme: string = 'light';
  @Link searchText: string;
  @Prop boards: BoardItem[] = [];
  /** 榜单总数为 0 时文案用「暂无数据」，否则是「没有匹配结果」 */
  @Prop allEmpty: boolean = false;
  @Prop searchActions: SearchStripActions = new SearchStripActions();
  onCancel?: () => void;
  onOpenBoard?: (board: BoardItem) => void;

  build() {
    Column() {
      Row() {
        SearchStrip({
          text: $searchText,
          placeholder: t('search_board_hint'),
          marginH: 0,
          marginV: 0,
          actions: this.searchActions,
        })
          .layoutWeight(1)
        Text(t('cancel'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.accent())
          .padding({ left: 12, right: 0, top: 8, bottom: 8 })
          .onClick(() => {
            if (this.onCancel) {
              this.onCancel();
            }
          })
      }
      .width('100%')
      .padding({
        left: DesignTokens.spaceGutter(),
        right: DesignTokens.spaceGutter(),
        top: 10,
        bottom: 8,
      })
      .alignItems(VerticalAlign.Center)

      if (this.boards.length === 0) {
        Column() {
          Text(this.allEmpty ? t('no_data') : t('no_data'))
            .fontSize(15)
            .fontColor(DesignTokens.labelSecondary(this.theme))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.boards, (board: BoardItem) => {
            ListItem() {
              Row() {
                Text(board.name.length > 0 ? board.name : t('board_item'))
                  .layoutWeight(1)
                  .fontSize(16)
                  .fontColor(DesignTokens.labelPrimary(this.theme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(t('leaderboard_title'))
                  .fontSize(12)
                  .fontColor(DesignTokens.labelTertiary(this.theme))
                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(17)
                  .fontColor([DesignTokens.labelTertiary(this.theme)])
                  .margin({ left: 6 })
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
                if (this.onOpenBoard) {
                  this.onOpenBoard(board);
                }
              })
            }
          }, (board: BoardItem) => board.id)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }
}
