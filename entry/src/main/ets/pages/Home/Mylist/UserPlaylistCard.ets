/**
 * 自建歌单卡片（「我的」页）
 *
 * 封面/占位图 + 名称 + 歌曲数（+ 绑定在线歌单时的来源角标）+ 播放按钮 + 同步按钮 + 箭头。
 * 行尾动作与歌单详情、自建歌单管理页保持同一套：⋮ 菜单里的「同步」在这里提为直接入口。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { t } from '../../../service/LocalizationService';
import { tf, sourceLabel } from '../../../service/LocalizationService';

@Component
export struct UserPlaylistCard {
  @StorageProp('theme') theme: string = 'light';
  @Prop name: string = '';
  @Prop count: number = 0;
  @Prop pic: string = '';
  /** 绑定在线歌单时非空：显示来源角标并提供同步入口 */
  @Prop bindingSource: string = '';
  @Prop bindingListId: string = '';
  onOpen?: () => void;
  onPlay?: () => void;
  onSync?: () => void;
  /** 更多操作（重命名 / 删除 / 更新内容），与「全部歌单」页同一套菜单 */
  onMenu?: () => void;

  @Styles
  pressed() {
    .opacity(DesignTokens.pressedOpacity())
  }

  build() {
    Row() {
      if (this.pic.length > 0) {
        Image(this.pic)
          .width(52)
          .height(52)
          .borderRadius(DesignTokens.radiusCover())
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music_note_list'))
            .fontSize(29)
            .fontColor([DesignTokens.labelTertiary(this.theme)])
        }
        .width(52)
        .height(52)
        .borderRadius(DesignTokens.radiusCover())
        .backgroundColor(DesignTokens.mutedFill(this.theme))
        .justifyContent(FlexAlign.Center)
      }

      Column({ space: 6 }) {
        Text(this.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Row() {
          Text(tf('count_songs_unit', [this.count.toString()]))
            .fontSize(13)
            .fontColor(DesignTokens.labelTertiary(this.theme))
          if (this.bindingListId.length > 0) {
            Text(tf('list_bound_online', [sourceLabel(this.bindingSource)]))
              .fontSize(11)
              .fontColor(DesignTokens.accent())
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(8)
              .border({ width: 1, color: DesignTokens.accent() })
              .margin({ left: 8 })
          }
        }
      }
      .layoutWeight(1)
      .padding({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      if (this.bindingListId.length > 0) {
        SymbolGlyph($r('sys.symbol.arrow_clockwise'))
          .fontSize(24)
          .fontColor([DesignTokens.accent()])
          .padding(10)
          .responseRegion(DesignTokens.touchRegion(40))
          .accessibilityText(t('a11y_refresh'))
          .onClick(() => {
            if (this.onSync) {
              this.onSync();
            }
          })
      }

      SymbolGlyph($r('sys.symbol.play_circle'))
        .fontSize(36)
        .fontColor([DesignTokens.accent()])
        .responseRegion(DesignTokens.touchRegion(30))
        .accessibilityText(t('a11y_play'))
        .onClick(() => {
          if (this.onPlay) {
            this.onPlay();
          }
        })

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(17)
        .fontColor([DesignTokens.labelTertiary(this.theme)])
        .margin({ left: 8 })

      // 更多操作：此前卡片只有「播放/同步」，重命名与删除只能去「全部歌单」页操作
      Image($r('app.media.ic_pd_more'))
        .width(18)
        .height(18)
        .fillColor(DesignTokens.labelSecondary(this.theme))
        .margin({ left: 6 })
        .responseRegion(DesignTokens.touchRegion(20))
        .accessibilityText(t('a11y_more'))
        .onClick(() => {
          if (this.onMenu) {
            this.onMenu();
          }
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .shadow(DesignTokens.cardShadow(this.theme))
    .alignItems(VerticalAlign.Center)
    .stateStyles({ pressed: this.pressed })
    .onClick(() => {
      if (this.onOpen) {
        this.onOpen();
      }
    })
  }
}
