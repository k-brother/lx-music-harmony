/**
 * 播放页顶部栏（标题 + 返回 + 更多，以及封面/歌词切换）
 *
 * 从 PlayDetailPage 的 @Builder 抽成组件：顶部这两块只依赖「显示值 + 回调」，
 * 抽出来后页面 build() 里的层级更短，顶部样式改动也只碰这一处。
 * 注意：动态文案（歌名/歌手/当前 tab）都通过 @Prop 传入，组件自身不持有状态
 * （@Builder 的参数不会随状态刷新，组件 @Prop 会）。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { NavBackButton } from '../../components/common/NavBackButton';
import { SegmentedBar } from '../../components/ui/SegmentedBar';
import { t } from '../../service/LocalizationService';

/** 字体阴影（设置 → 外观 → 字体阴影） */

@Component
export struct PlayDetailTopBar {
  @StorageProp('theme') theme: string = 'light';
  @Prop musicName: string = '';
  @Prop singer: string = '';
  @Prop fontShadow: boolean = false;
  /** 0 = 封面，1 = 歌词 */
  @Prop currentTab: number = 0;
  /** 宽屏（平板横屏 / PC）封面与歌词同屏展示，不再需要「封面/歌词」切换 */
  @Prop showTabSwitch: boolean = true;
  onMore?: () => void;
  onSelectTab?: (tab: number) => void;

  @Builder
  TitleBar() {
    Row() {
      NavBackButton()

      Column() {
        Text(this.musicName.length > 0 ? this.musicName : t('not_playing'))
          .fontSize(DesignTokens.fontTitle())
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textShadow(this.fontShadow ? DesignTokens.textShadowOnArtwork() : undefined)
        if (this.singer.length > 0) {
          Text(this.singer)
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .maxLines(1)
            .textShadow(this.fontShadow ? DesignTokens.textShadowOnArtwork() : undefined)
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Blank()

      Stack() {
        Circle({ width: 34, height: 34 })
          .fill(DesignTokens.mutedFill(this.theme))
        Image($r('app.media.ic_pd_more'))
          .width(16)
          .height(16)
          .fillColor(DesignTokens.labelSecondary(this.theme))
      }
      .responseRegion(DesignTokens.touchRegion(34))
      .onClick(() => {
        if (this.onMore) {
          this.onMore();
        }
      })
    }
    .width('100%')
    .height(60)
    .padding({ left: 14, right: 14, top: 8, bottom: 6 })
    .backgroundColor(DesignTokens.chromeBar(this.theme))
  }

  @Builder
  TabSwitch() {
    Row() {
      SegmentedBar({
        options: [
          { id: 'cover', label: t('play_tab_cover') },
          { id: 'lyric', label: t('play_tab_lyric') },
        ],
        activeId: this.currentTab === 0 ? 'cover' : 'lyric',
        equalWidth: true,
        fontSize: DesignTokens.fontBody(),
        onSelect: (id: string): void => {
          if (this.onSelectTab) {
            this.onSelectTab(id === 'cover' ? 0 : 1);
          }
        },
      })
    }
    .width(176)
    .margin({ top: 8, bottom: 10 })
  }

  build() {
    Column() {
      this.TitleBar()
      // 宽屏封面/歌词同屏，切换控件没有意义，直接不渲染（保留下方留白节奏）
      if (this.showTabSwitch) {
        this.TabSwitch()
      }
    }
    .width('100%')
  }
}
