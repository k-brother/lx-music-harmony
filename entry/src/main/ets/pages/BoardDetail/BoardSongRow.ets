/**
 * 榜单详情的歌曲行
 *
 * 与歌单详情的行保持同一套观感（序号 / 歌名 / 歌手 / 当前播放高亮 / 分割线内缩），
 * 但多一个「下载」入口，所以单独成组件而不是直接用 UI Kit 的 ListRow
 * （ArkTS 不允许在 ForEach 的独立函数里用 this，trailing 回调传不进去）。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { isConfirmKey } from '../../utils/KeyboardTools';
import { t } from '../../service/LocalizationService';
import { composeRowDurationText, composeRowSubtitle } from '../../core/list/RowTexts';

@Component
export struct BoardSongRow {
  @StorageProp('theme') theme: string = 'light';
  @Prop index: number = 0;
  @Prop title: string = '';
  @Prop singer: string = '';
  @Prop album: string = '';
  @Prop sourceId: string = '';
  /** 时长（秒）：按「设置 → 列表 → 显示时长」决定是否展示 */
  @Prop durationSeconds: number = 0;
  /** 是否是当前播放的那首（高亮） */
  @Prop active: boolean = false;
  @Prop divider: boolean = true;
  /** 设置 → 列表 */
  @StorageProp('showListAlbum') showListAlbum: boolean = true;
  @StorageProp('showListSource') showListSource: boolean = true;
  @StorageProp('showListDuration') showListDuration: boolean = true;
  onTap?: () => void;
  onDownload?: () => void;

  /** 副标题与时长都走统一拼装（列表显示设置在这里生效） */
  private subtitleText(): string {
    return composeRowSubtitle(this.singer, this.album, this.sourceId, this.showListAlbum, this.showListSource);
  }

  private durationText(): string {
    return composeRowDurationText(this.durationSeconds, this.showListDuration);
  }

  build() {
    Column() {
      Row() {
        Text(this.index.toString())
          .fontSize(DesignTokens.fontCaption())
          .fontColor(this.active ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme))
          .width(28)
          .textAlign(TextAlign.Center)

        Column({ space: 2 }) {
          Text(this.title)
            .fontSize(DesignTokens.fontBody())
            .fontColor(this.active ? DesignTokens.accent() : DesignTokens.labelPrimary(this.theme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.subtitleText().length > 0) {
            Text(this.subtitleText())
              .fontSize(DesignTokens.fontCaption())
              .fontColor(DesignTokens.labelSecondary(this.theme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 10, right: 10 })

        if (this.durationText().length > 0) {
          Text(this.durationText())
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .margin({ right: 6 })
        }

        Stack() {
          Circle({ width: 28, height: 28 })
            .fill(DesignTokens.mutedFill(this.theme))
          Image($r('app.media.ic_common_download'))
            .width(14)
            .height(14)
            .fillColor(DesignTokens.labelSecondary(this.theme))
        }
        .responseRegion(DesignTokens.touchRegion(28))
        .accessibilityText(t('a11y_download'))
        .onClick(() => {
          if (this.onDownload) {
            this.onDownload();
          }
        })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)

      if (this.divider) {
        Divider()
          .strokeWidth(0.5)
          .color(DesignTokens.hairlineSeparator(this.theme))
          .margin({ left: 48, right: 10 })
      }
    }
    .width('100%')
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(12)
    .border({ width: 0.33, color: DesignTokens.cardBorder(this.theme) })
    // 2in1（PC/平板接鼠标）下的悬停反馈：整行高亮
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      if (this.onTap) {
        this.onTap();
      }
    })
    // 2in1（PC 接键盘）：回车/空格等同于点一下
    .focusable(true)
    .onKeyEvent((event: KeyEvent): void => {
      if (isConfirmKey(event) && this.onTap) {
        this.onTap();
      }
    })
  }
}
