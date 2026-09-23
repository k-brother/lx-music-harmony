/**
 * 榜单详情头部
 *
 * 与 SonglistDetailHeader 同一套观感：
 * 展开态 = 封面（右下角带来源角标）+ 「播放全部」+ 曲目数；
 * 滚动到顶后切成收缩态 = 只留「播放全部」+ 来源角标。
 *
 * 从 BoardDetailPage 的 @Builder 抽成组件的原因之一：那里把「播放全部」
 * 按钮写了两遍（展开态、收缩态各一份），改样式容易改漏。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t, tf } from '../../service/LocalizationService';

@Component
export struct BoardDetailHeader {
  @StorageProp('theme') theme: string = 'light';
  /** 榜单封面（空则用占位图） */
  @Prop cover: string = '';
  /** 音源简写（kw/kg/...），作为来源角标 */
  @Prop sourceTag: string = '';
  @Prop songCount: number = 0;
  /** 滚动收缩态 */
  @Prop compact: boolean = false;
  onPlayAll?: () => void;

  @State coverFailed: boolean = false;

  private canRenderCover(url: string): boolean {
    return url.length > 0 && (url.startsWith('http') || url.startsWith('file') || url.startsWith('datashare'));
  }

  private showCover(): boolean {
    return !this.coverFailed && this.canRenderCover(this.cover);
  }

  /** 来源角标：小号强调色胶囊 */
  @Builder
  SourceBadge() {
    Text(this.sourceTag.toUpperCase())
      .fontSize(DesignTokens.fontBadge())
      .fontColor(DesignTokens.onAccent())
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor(DesignTokens.accent())
      .borderRadius(9)
  }

  /** 播放全部：展开态与收缩态共用一份（此前写了两遍） */
  @Builder
  PlayAllButton() {
    Row({ space: 5 }) {
      Image($r('app.media.ic_pd_play'))
        .width(14)
        .height(14)
        .fillColor(DesignTokens.onAccent())
      Text(t('play_all'))
        .fontSize(DesignTokens.fontBody())
        .fontColor(DesignTokens.onAccent())
        .fontWeight(FontWeight.Medium)
    }
    .height(38)
    .width(112)
    .backgroundColor(DesignTokens.accent())
    .borderRadius(19)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.onPlayAll) {
        this.onPlayAll();
      }
    })
  }

  build() {
    Column({ space: this.compact ? 6 : 10 }) {
      if (!this.compact) {
        Row() {
          Stack() {
            if (this.showCover()) {
              Image(this.cover)
                .width(106)
                .height(106)
                .borderRadius(12)
                .objectFit(ImageFit.Cover)
                .onError(() => {
                  this.coverFailed = true;
                })
            } else {
              Image($r('app.media.ic_player_cover_placeholder'))
                .width(106)
                .height(106)
                .borderRadius(12)
                .objectFit(ImageFit.Cover)
            }

            // 展开态：来源角标压在封面右下角（收缩态那份在下方行里）
            // @Builder 不能链式修饰，包一层容器来留白
            Row() {
              this.SourceBadge()
            }
            .margin({ right: 6, bottom: 6 })
          }
          .width(106)
          .height(106)
          .align(Alignment.BottomEnd)

          Column({ space: 10 }) {
            this.PlayAllButton()
            Text(tf('count_songs', [this.songCount.toString()]))
              .fontSize(DesignTokens.fontCaption())
              .fontColor(DesignTokens.labelSecondary(this.theme))
          }
          .alignItems(HorizontalAlign.End)
          .layoutWeight(1)
          .margin({ left: 14 })
        }
        .width('100%')
      }

      // 收缩态：滚动后替代大封面那一行（高度为 0 时不占位）
      Row({ space: 8 }) {
        this.PlayAllButton()
        this.SourceBadge()
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)
      .opacity(this.compact ? 1 : 0)
      .height(this.compact ? 38 : 0)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .border({ width: 0.33, color: DesignTokens.cardBorder(this.theme) })
    .margin({ left: 12, right: 12, top: 4, bottom: 8 })
  }
}
