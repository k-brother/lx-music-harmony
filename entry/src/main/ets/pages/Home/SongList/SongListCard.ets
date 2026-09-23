/**
 * 歌单网格卡片
 *
 * 从 SongListView 的 @Builder 抽成组件：封面（含尺寸降级与失败占位）、播放量角标、
 * 歌单名与创建者、按压反馈。组件只认「卡片数据 + 点击回调」。
 *
 * 为什么用 @Component 而不是 @Builder：@Builder 的参数不会随状态刷新，
 * 卡片数据（封面/播放量）变化时不会重建；@Prop 在父组件重渲染时会更新。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { t } from '../../../service/LocalizationService';
import { formatPlayCount } from '../../../utils/FormatTools';
import type { SongListItemData } from '../SongListTypes';

@Component
export struct SongListCard {
  @StorageProp('theme') theme: string = 'light';
  @Prop item: SongListItemData;
  onTap?: () => void;

  /** 列表封面用轻量尺寸，别拉 500x500 原图（首屏 9 张能省一大截流量与解码） */
  private lightweightCoverUrl(rawUrl: string): string {
    const url = (rawUrl ?? '').trim();
    if (!url) {
      return '';
    }
    return url
      .replace('/500/', '/150/')
      .replace('/300/', '/150/')
      .replace('T002R500x500M000', 'T002R300x300M000')
      .replace('T001R500x500M000', 'T001R300x300M000')
      .replace('_500.jpg', '_150.jpg')
      .replace('_500.png', '_150.png');
  }

  /** 播放量：接口给的是字符串，统一走 FormatTools */
  private playCountText(count: string): string {
    const num = parseFloat(count);
    if (isNaN(num)) {
      return '0';
    }
    return formatPlayCount(num, t('ten_thousand_unit'), t('billion_unit'));
  }

  private canRenderCover(): boolean {
    return (this.item.img ?? '').trim().length > 0;
  }

  build() {
    Column() {
      Stack() {
        if (this.canRenderCover()) {
          Image(this.lightweightCoverUrl(this.item.img || ''))
            .width('100%')
            .aspectRatio(1)
            .borderRadius(DesignTokens.radiusCover())
            .objectFit(ImageFit.Cover)
            .onError(() => {
              // 单卡封面失败时降级占位，避免重复解码/重试风暴
              this.item.img = '';
            })
        } else {
          Image($r('app.media.ic_player_cover_placeholder'))
            .width('100%')
            .aspectRatio(1)
            .borderRadius(DesignTokens.radiusCover())
            .objectFit(ImageFit.Cover)
        }

        // 播放量角标
        Row() {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(12)
            .fontColor([DesignTokens.onAccent()])
          Text(this.playCountText(this.item.play_count))
            .fontSize(10)
            .fontColor(DesignTokens.onAccent())
            .margin({ left: 3 })
        }
        .padding({ left: 6, right: 6, top: 3, bottom: 3 })
        .backgroundColor('rgba(0, 0, 0, 0.4)')
        .borderRadius(DesignTokens.radiusCover())
        .position({ x: 6, y: 6 })
      }
      .width('100%')
      .aspectRatio(1)
      // 封面投影：无卡片底色时提供层次（主流音乐 App 的歌单网格做法）
      .shadow({ radius: 10, color: 'rgba(0,0,0,0.10)', offsetX: 0, offsetY: 3 })

      Column() {
        Text(this.item.name)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .maxLines(2)
          .lineHeight(19)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(this.item.author)
          .fontSize(12)
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 5 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ top: 8 })
    }
    .width('100%')
    .onClick(() => {
      if (this.onTap) {
        this.onTap();
      }
    })
  }
}
