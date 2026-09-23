/**
 * 歌单详情头部
 *
 * 展开态：大封面 + 标题/作者/播放量/歌曲数 + 「播放全部 / 收藏」按钮
 * 收缩态：只留操作按钮 + 来源角标 + 歌曲数（滚动时切换，参考主流播放器）
 *
 * 组件只负责展示与回调，列表信息与收藏状态由页面传入。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t, tf, playCountUnits } from '../../service/LocalizationService';
import { formatPlayCount } from '../../utils/FormatTools';

@Component
export struct SonglistDetailHeader {
  @StorageProp('theme') theme: string = 'light';
  @Prop listName: string = '';
  @Prop creator: string = '';
  @Prop description: string = '';
  @Prop cover: string = '';
  @Prop sourceLabel: string = '';
  @Prop songCount: number = 0;
  @Prop playCount: number = 0;
  /** 滚动收缩态 */
  @Prop compact: boolean = false;
  onPlayAll?: () => void;
  onCollect?: () => void;

  @State coverFailed: boolean = false;

  /**
   * 播放量展示：实现与单位文案统一走 utils/FormatTools + 词条
   * （此前这里自己写了一份 `(count/10000).toFixed(1)万`，英文界面下也会带「万」）
   */
  private formatPlayCount(count: number): string {
    return formatPlayCount(count, playCountUnits());
  }

  private canRenderCover(url: string): boolean {
    return url.length > 0 && (url.startsWith('http') || url.startsWith('file') || url.startsWith('datashare'));
  }

  /**
   * 是否展示「创建者」。
   *
   * 源给的作者字段有时是账号 id 而不是昵称（酷我老接口返回 `kw2144087549`），
   * 这种值展示出来就是一行乱码，直接不显示该行；空值同样不显示。
   */
  private showCreator(): boolean {
    const name: string = this.creator;
    if (name.length === 0) {
      return false;
    }
    if (/^\d+$/.test(name)) {
      return false;
    }
    if (/^[a-z]{1,4}\d{5,}$/i.test(name)) {
      return false;
    }
    return true;
  }

  @Builder
  private PlayAllButton() {
    Row({ space: 5 }) {
      Image($r('app.media.ic_pd_play'))
        .width(14)
        .height(14)
        .fillColor(DesignTokens.onAccent())
      Text(t('play_all'))
        .fontSize(DesignTokens.fontCaption())
        .fontColor(DesignTokens.onAccent())
        .fontWeight(FontWeight.Medium)
    }
    .height(34)
    .width('100%')
    .backgroundColor(DesignTokens.accent())
    .borderRadius(17)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.onPlayAll) {
        this.onPlayAll();
      }
    })
  }

  @Builder
  private CollectButton() {
    Row({ space: 5 }) {
      Image($r('app.media.ic_common_heart'))
        .width(14)
        .height(14)
        .fillColor(DesignTokens.labelPrimary(this.theme))
      Text(t('player_love'))
        .fontSize(DesignTokens.fontCaption())
        .fontColor(DesignTokens.labelPrimary(this.theme))
    }
    .height(34)
    .width('100%')
    .backgroundColor(DesignTokens.mutedFill(this.theme))
    .borderRadius(17)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      if (this.onCollect) {
        this.onCollect();
      }
    })
  }

  @Builder
  private SourceBadge() {
    Text(this.sourceLabel)
      .fontSize(DesignTokens.fontBadge())
      .fontColor(DesignTokens.onAccent())
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .backgroundColor(DesignTokens.accent())
      .borderRadius(9)
  }

  build() {
    Column() {
      if (!this.compact) {
        this.ExpandedRow()
      } else {
        this.CompactRow()
      }

      if (this.description.length > 0) {
        Text(this.description)
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .lineHeight(19)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: this.compact ? 6 : 10 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(14)
    .border({ width: 0.33, color: DesignTokens.cardBorder(this.theme) })
    .margin({ left: 12, right: 12, top: 8, bottom: 10 })
  }

  /** 展开态：大封面 + 名称/作者/播放量 + 操作按钮列 */
  @Builder
  ExpandedRow() {
    Row() {
      Stack() {
        if (!this.coverFailed && this.canRenderCover(this.cover)) {
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
        this.SourceBadge()
      }
      .width(106)
      .height(106)
      .align(Alignment.BottomEnd)

      // 标题/作者/播放量独占右侧整列：按钮不再挤占这里的宽度
      // （此前两个 112vp 按钮压在右侧，作者行只剩 86vp，被截成「创建者: …」）
      Column({ space: 6 }) {
        Text(this.listName)
          .fontSize(DesignTokens.fontTitle())
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .fontWeight(FontWeight.Medium)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        // 创建者：源没给作者（或给的是账号 id）时整行不渲染
        if (this.showCreator()) {
          Text(`${t('songlist_creator')}: ${this.creator}`)
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }

        Row() {
          Text(tf('count_play', [this.formatPlayCount(this.playCount)]))
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelSecondary(this.theme))
          Text(tf('count_songs', [this.songCount.toString()]))
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .margin({ left: 8 })
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 14 })
    }
    .width('100%')

    // 操作按钮整行平分：图标 + 文案居中，触控目标够大且不会挤正文
    Row({ space: 10 }) {
      Column() {
        this.PlayAllButton()
      }
      .layoutWeight(1)

      Column() {
        this.CollectButton()
      }
      .layoutWeight(1)
    }
    .width('100%')
    .margin({ top: 12 })
  }

  /** 收缩态：操作按钮 + 曲目数（滚动后替代大封面那一行） */
  @Builder
  CompactRow() {
      Row() {
        Row({ space: 8 }) {
          // 按钮本身是 width('100%')（展开态整行平分用），这里给固定宽度容器
          Column() {
            this.PlayAllButton()
          }
          .width(104)
          Column() {
            this.CollectButton()
          }
          .width(104)
          this.SourceBadge()
        }
        Text(tf('count_songs', [this.songCount.toString()]))
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelSecondary(this.theme))
      }
      .width('100%')
      .margin({ top: 4 })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
  }

}
