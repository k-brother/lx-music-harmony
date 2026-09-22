/**
 * 自建歌单卡片（「我的」页）
 *
 * 封面/占位图 + 名称 + 歌曲数（+ 绑定在线歌单时的来源角标）+ 播放按钮 + 同步按钮 + 箭头。
 * 行尾动作与歌单详情、自建歌单管理页保持同一套：⋮ 菜单里的「同步」在这里提为直接入口。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
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
          Image($r('sys.symbol.music_note_list'))
            .width(24)
            .height(24)
            .fillColor(DesignTokens.labelTertiary(this.theme))
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
        Image($r('sys.symbol.arrow_clockwise'))
          .width(20)
          .height(20)
          .fillColor(DesignTokens.accent())
          .padding(10)
          .responseRegion(DesignTokens.touchRegion(40))
          .onClick(() => {
            if (this.onSync) {
              this.onSync();
            }
          })
      }

      Image($r('sys.symbol.play_circle'))
        .width(30)
        .height(30)
        .fillColor(DesignTokens.accent())
        .responseRegion(DesignTokens.touchRegion(30))
        .onClick(() => {
          if (this.onPlay) {
            this.onPlay();
          }
        })

      Image($r('sys.symbol.chevron_right'))
        .width(14)
        .height(14)
        .fillColor(DesignTokens.labelTertiary(this.theme))
        .margin({ left: 8 })
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
