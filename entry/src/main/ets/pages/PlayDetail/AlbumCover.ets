/**
 * 播放页封面
 *
 * 只做展示与手势：
 * - 封面加载失败时回调 onLoadError（页面负责重试 / 降级 URL / 占位）
 * - 支持随页面切换缩小淡出（active=false）
 * - 长按出快捷菜单（分享/收藏/下载等由页面提供）
 */
import { DesignTokens } from '../../theme/DesignTokens';

@Component
export struct AlbumCover {
  @StorageProp('theme') theme: string = 'light';
  @Prop cover: string = '';
  /** 当前是否处于封面页（歌词页时缩小淡出） */
  @Prop active: boolean = true;
  @Prop animationEnabled: boolean = true;
  onLoadError?: () => void;
  onLongPress?: () => void;
  /** 单击封面（窄屏：切到歌词页；宽屏不需要，由页面决定是否响应） */
  onTap?: () => void;

  private canRender(url: string): boolean {
    return url.length > 0
      && (url.startsWith('http') || url.startsWith('file') || url.startsWith('datashare'));
  }

  build() {
    Column() {
      if (this.canRender(this.cover)) {
        Image(this.cover)
          .width('82%')
          .aspectRatio(1)
          .borderRadius(20)
          .objectFit(ImageFit.Cover)
          .onError(() => {
            if (this.onLoadError) {
              this.onLoadError();
            }
          })
      } else {
        Image($r('app.media.ic_player_cover_placeholder'))
          .width('82%')
          .aspectRatio(1)
          .borderRadius(20)
          .objectFit(ImageFit.Cover)
      }
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height('100%')
    // 切到歌词页时封面轻微缩小淡出，形成层次过渡
    .scale({ x: this.active ? 1 : 0.92, y: this.active ? 1 : 0.92 })
    .opacity(this.active ? 1 : 0.65)
    .animation({ duration: this.animationEnabled ? DesignTokens.motionNormal() : 0, curve: Curve.EaseOut })
    .onClick(() => {
      if (this.onTap) {
        this.onTap();
      }
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          if (this.onLongPress) {
            this.onLongPress();
          }
        })
    )
  }
}
