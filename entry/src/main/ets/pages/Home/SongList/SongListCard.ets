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
import { playCountUnits } from '../../../service/LocalizationService';
import { formatPlayCount } from '../../../utils/FormatTools';
import { isConfirmKey } from '../../../utils/KeyboardTools';
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
    return formatPlayCount(num, playCountUnits());
  }

  private canRenderCover(): boolean {
    return (this.item.img ?? '').trim().length > 0;
  }

  build() {
    Column() {
      this.CoverWithBadge()
      this.CardTexts()
    }
    .width('100%')
    .onClick(() => {
      if (this.onTap) {
        this.onTap();
      }
    })
    // 2in1：卡片悬停高亮 + 回车/空格等同于点一下
    .hoverEffect(HoverEffect.Highlight)
    .focusable(true)
    .onKeyEvent((event: KeyEvent): void => {
      if (isConfirmKey(event) && this.onTap) {
        this.onTap();
      }
    })
  }

  /** 封面 + 播放量角标（封面失败降级为占位图，避免重复解码/重试风暴） */
  @Builder
  CoverWithBadge() {
    Stack() {
      if (this.canRenderCover()) {
        Image(this.lightweightCoverUrl(this.item.img || ''))
          .width('100%')
          .aspectRatio(1)
          .borderRadius(DesignTokens.radiusCover())
          .objectFit(ImageFit.Cover)
          .draggable(false)
          .onError(() => {
            this.item.img = '';
          })
      } else {
        Image($r('app.media.ic_player_cover_placeholder'))
          .width('100%')
          .aspectRatio(1)
          .borderRadius(DesignTokens.radiusCover())
          .objectFit(ImageFit.Cover)
          .draggable(false)
      }

      Row() {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(DesignTokens.fontCaption())
          .fontColor([DesignTokens.onAccent()])
        Text(this.playCountText(this.item.play_count))
          .fontSize(DesignTokens.fontBadge())
          .fontColor(DesignTokens.onAccent())
          .margin({ left: 3 })
      }
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .backgroundColor(DesignTokens.scrim())
      .borderRadius(DesignTokens.radiusCover())
      .position({ x: 6, y: 6 })
    }
    .width('100%')
    .aspectRatio(1)
    // 封面投影：无卡片底色时提供层次（主流音乐 App 的歌单网格做法）
    .shadow(DesignTokens.softShadow())
  }

  /** 歌单名（最多两行）+ 创建者 */
  @Builder
  CardTexts() {
    Column() {
      Text(this.item.name)
        .fontSize(DesignTokens.fontBody())
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .maxLines(2)
        .lineHeight(19)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      Text(this.item.author)
        .fontSize(DesignTokens.fontCaption())
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
}
