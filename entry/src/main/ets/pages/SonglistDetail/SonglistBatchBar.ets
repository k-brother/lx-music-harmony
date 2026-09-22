/**
 * 歌单多选批量操作栏
 *
 * 固定在列表底部：已选数量、全选/取消全选、批量操作（添加到列表 / 下载 / 移出）。
 * 「移出」只在本地歌单出现（在线歌单是只读的，移出无意义）。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t, tf } from '../../service/LocalizationService';

@Component
export struct SonglistBatchBar {
  @StorageProp('theme') theme: string = 'light';
  @Prop selectedCount: number = 0;
  @Prop totalCount: number = 0;
  /** 本地歌单才允许移出 */
  @Prop removable: boolean = false;
  @Prop busy: boolean = false;
  onToggleSelectAll?: () => void;
  onAddToList?: () => void;
  onDownload?: () => void;
  onRemove?: () => void;

  build() {
    Column() {
      Row() {
        Text(tf('list_selected_count', [this.selectedCount.toString()]))
          .fontSize(13)
          .fontColor(DesignTokens.labelSecondary(this.theme))

        Blank()

        Text(this.selectedCount === this.totalCount ? t('list_deselect_all') : t('list_select_all'))
          .fontSize(13)
          .fontColor(DesignTokens.accent())
          .padding({ left: 8, right: 4, top: 4, bottom: 4 })
          .onClick(() => {
            if (this.onToggleSelectAll) {
              this.onToggleSelectAll();
            }
          })
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 8 })

      Row({ space: 8 }) {
        Button(t('player_add_to_list'))
          .layoutWeight(1)
          .height(DesignTokens.touchTarget())
          .fontSize(13)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .backgroundColor(DesignTokens.mutedFill(this.theme))
          .enabled(!this.busy)
          .onClick(() => {
            if (this.onAddToList) {
              this.onAddToList();
            }
          })
        Button(t('player_download'))
          .layoutWeight(1)
          .height(DesignTokens.touchTarget())
          .fontSize(13)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .backgroundColor(DesignTokens.mutedFill(this.theme))
          .enabled(!this.busy)
          .onClick(() => {
            if (this.onDownload) {
              this.onDownload();
            }
          })
        if (this.removable) {
          Button(t('list_remove_songs'))
            .layoutWeight(1)
            .height(DesignTokens.touchTarget())
            .fontSize(13)
            .fontColor('#FFFFFF')
            .backgroundColor(DesignTokens.danger())
            .enabled(!this.busy)
            .onClick(() => {
              if (this.onRemove) {
                this.onRemove();
              }
            })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 12 })
    .backgroundColor(DesignTokens.chromeBar(this.theme))
    .border({ width: { top: 0.5 }, color: { top: DesignTokens.hairlineSeparator(this.theme) } })
  }
}
