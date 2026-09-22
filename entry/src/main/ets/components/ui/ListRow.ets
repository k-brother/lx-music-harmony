/**
 * 统一列表行（SongRow / SimpleRow）
 *
 * 全应用列表「会长得一样」：序号或封面、主标题、副标题、右侧内容、按压反馈、分割线内缩。
 * 各页面只需传数据与回调，不再各自拼 Row/Circle/Text。
 *
 * 用法（ArkTS V1 回调通过非装饰成员传入）：
 *   ListRow({
 *     index: i + 1,
 *     title: song.name,
 *     subtitle: song.singer,
 *     cover: song.pic,
 *     showIndex: true,
 *     onTap: () => this.play(i),
 *   })
 */
import { DesignTokens } from '../../theme/DesignTokens';

@Component
export struct ListRow {
  @StorageProp('theme') theme: string = 'light';
  /** 序号（showIndex 为 true 时展示；<=0 表示不展示） */
  @Prop index: number = 0;
  @Prop title: string = '';
  @Prop subtitle: string = '';
  /** 封面地址（为空且 showIndex=false 时显示占位图标） */
  @Prop cover: string = '';
  /** 右侧附加文本（时长/来源等） */
  @Prop trailingText: string = '';
  @Prop showIndex: boolean = true;
  /** 当前播放高亮 */
  @Prop active: boolean = false;
  /** 是否显示分割线（最后一行传 false） */
  @Prop divider: boolean = true;
  /** 主标题占两行（副标题较长时用） */
  @Prop twoLine: boolean = false;
  onTap?: () => void;
  onLongPress?: () => void;

  @Styles
  pressed() {
    .opacity(DesignTokens.pressedOpacity())
  }

  build() {
    Column() {
      Row() {
        if (this.showIndex) {
          Text(this.index > 0 ? this.index.toString() : '')
            .fontSize(DesignTokens.fontCaption())
            .fontColor(this.active ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme))
            .width(28)
            .textAlign(TextAlign.Center)
        } else if (this.cover.length > 0) {
          Image(this.cover)
            .width(DesignTokens.rowCover())
            .height(DesignTokens.rowCover())
            .borderRadius(DesignTokens.radiusCover())
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Image($r('sys.symbol.music_note_list'))
              .width(20)
              .height(20)
              .fillColor(DesignTokens.labelTertiary(this.theme))
          }
          .width(DesignTokens.rowCover())
          .height(DesignTokens.rowCover())
          .borderRadius(DesignTokens.radiusCover())
          .backgroundColor(DesignTokens.mutedFill(this.theme))
          .justifyContent(FlexAlign.Center)
        }

        Column({ space: 2 }) {
          Text(this.title)
            .fontSize(DesignTokens.fontTitle())
            .fontColor(this.active ? DesignTokens.accent() : DesignTokens.labelPrimary(this.theme))
            .maxLines(this.twoLine ? 2 : 1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          if (this.subtitle.length > 0) {
            Text(this.subtitle)
              .fontSize(DesignTokens.fontCaption())
              .fontColor(DesignTokens.labelTertiary(this.theme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 10, right: 8 })

        if (this.trailingText.length > 0) {
          Text(this.trailingText)
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelTertiary(this.theme))
        }

        // 右侧动作插槽
        if (this.trailing) {
          this.trailing()
        }
      }
      .width('100%')
      .height(this.twoLine || this.subtitle.length > 0 ? DesignTokens.rowHeightTwoLine() : DesignTokens.rowHeight())
      .alignItems(VerticalAlign.Center)

      if (this.divider) {
        Divider()
          .strokeWidth(0.5)
          .color(DesignTokens.cardBorder(this.theme))
          .margin({ left: DesignTokens.rowInset() })
      }
    }
    .width('100%')
    .stateStyles({ pressed: this.pressed })
    .onClick(() => {
      if (this.onTap) {
        this.onTap();
      }
    })
    .gesture(LongPressGesture().onAction(() => {
      if (this.onLongPress) {
        this.onLongPress();
      }
    }))
  }

  @BuilderParam trailing?: () => void;
}
