/**
 * 本地音乐列表行
 *
 * 从 LocalMusicPage 的内联 Row 抽成组件：封面（自定义/占位）、标题、
 * 「歌手 · 专辑」副标题、时长，以及点击播放与长按菜单两个手势。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { isConfirmKey } from '../../utils/KeyboardTools';

@Component
export struct TrackRow {
  @StorageProp('theme') theme: string = 'light';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop durationText: string = '';
  /** 自定义封面 URL（为空则用占位图） */
  @Prop coverUrl: string = '';
  /** 当前正在播放这一行：标题用强调色 */
  @Prop active: boolean = false;
  onTap?: () => void;
  onLongPress?: () => void;

  /** 按压反馈：整行变淡（与其它列表页同一套） */
  @Styles
  pressDim() {
    .opacity(DesignTokens.pressedOpacity())
  }

  build() {
    Row() {
      if (this.coverUrl.length > 0) {
        Image(`file://${this.coverUrl}`)
          .width(52)
          .height(52)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor(DesignTokens.mutedFill(this.theme))
      } else {
        Image($r('app.media.ic_player_cover_placeholder'))
          .width(52)
          .height(52)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
      }

      Column() {
        Text(this.title)
          .fontSize(DesignTokens.fontSubhead())
          .fontWeight(this.active ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.active ? DesignTokens.accent() : DesignTokens.labelPrimary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Start)
        Text(this.subtitle)
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })

      Text(this.durationText)
        .fontSize(DesignTokens.fontCaption())
        .fontColor(DesignTokens.labelTertiary(this.theme))
    }
    .width('100%')
    .padding({
      left: DesignTokens.spaceGutter(),
      right: DesignTokens.spaceGutter(),
      top: DesignTokens.spaceUnit(),
      bottom: DesignTokens.spaceUnit(),
    })
    // 2in1（PC/平板接鼠标）下的悬停反馈：系统标准高亮，触屏设备无副作用
    .hoverEffect(HoverEffect.Highlight)
    .stateStyles({ pressed: this.pressDim })
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
    // 2in1（PC 接鼠标）：右键等同长按，出同一套行菜单
    .onMouse((event: MouseEvent): void => {
      if (event.action === MouseAction.Press && event.button === MouseButton.Right && this.onLongPress) {
        this.onLongPress();
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
