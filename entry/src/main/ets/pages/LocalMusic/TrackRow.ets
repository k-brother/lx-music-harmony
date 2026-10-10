/**
 * 本地音乐列表行
 *
 * 从 LocalMusicPage 的内联 Row 抽成组件：封面（自定义/占位）、标题、
 * 「歌手 · 专辑」副标题、时长，以及点击播放与长按菜单两个手势。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { isConfirmKey } from '../../utils/KeyboardTools';
import { composeRowDurationText, composeRowSubtitle } from '../../core/list/RowTexts';

@Component
export struct TrackRow {
  @StorageProp('theme') theme: string = 'light';
  @Prop title: string = '';
  /** 直传副标题（自定义文案用） */
  @Prop subtitle: string = '';
  /** 结构化副标题与时长：传了就按「设置 → 列表」统一裁剪 */
  @Prop singer: string = '';
  @Prop album: string = '';
  @Prop sourceId: string = '';
  @Prop durationSeconds: number = 0;
  @Prop durationText: string = '';
  /** 自定义封面 URL（为空则用占位图） */
  @Prop coverUrl: string = '';
  /** 当前正在播放这一行：标题用强调色 */
  @Prop active: boolean = false;
  /** 设置 → 列表 */
  @StorageProp('showListAlbum') showListAlbum: boolean = true;
  @StorageProp('showListSource') showListSource: boolean = true;
  @StorageProp('showListDuration') showListDuration: boolean = true;
  onTap?: () => void;
  onLongPress?: () => void;

  /** 副标题：结构化字段优先（带设置裁剪），否则用调用方直传的文本 */
  private subtitleText(): string {
    if (this.singer.length === 0 && this.album.length === 0 && this.sourceId.length === 0) {
      return this.subtitle;
    }
    return composeRowSubtitle(this.singer, this.album, this.sourceId, this.showListAlbum, this.showListSource);
  }

  /** 右侧时长：结构化时长优先（受设置控制），否则用调用方直传的文本 */
  private trailingTimeText(): string {
    if (this.durationSeconds > 0) {
      return composeRowDurationText(this.durationSeconds, this.showListDuration);
    }
    return this.durationText;
  }

  /** 按压反馈：整行变淡（与其它列表页同一套） */
  @Styles
  pressDim() {
    .opacity(DesignTokens.pressedOpacity())
  }

  build() {
    Row() {
      this.Cover()
      this.TitleBlock()
      this.TrailingTime()
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

  /** 封面：本地文件优先，缺失时用占位图（两者尺寸一致，避免行高跳动） */
  @Builder
  Cover() {
    if (this.coverUrl.length > 0) {
      Image(`file://${this.coverUrl}`)
        .width(52)
        .height(52)
        .borderRadius(8)
        .objectFit(ImageFit.Cover)
        .draggable(false)
        .backgroundColor(DesignTokens.mutedFill(this.theme))
    } else {
      Image($r('app.media.ic_player_cover_placeholder'))
        .width(52)
        .height(52)
        .borderRadius(8)
        .objectFit(ImageFit.Cover)
        .draggable(false)
    }
  }

  /** 歌名 + 副标题（副标题内容由 RowTexts 按「设置 → 列表」裁剪） */
  @Builder
  TitleBlock() {
    Column() {
      Text(this.title)
        .fontSize(DesignTokens.fontSubhead())
        .fontWeight(this.active ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.active ? DesignTokens.accent() : DesignTokens.labelPrimary(this.theme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .textAlign(TextAlign.Start)
      if (this.subtitleText().length > 0) {
        Text(this.subtitleText())
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ top: 4 })
      }
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .margin({ left: 12 })
  }

  /** 右侧时长（关闭「显示时长」时整块不渲染） */
  @Builder
  TrailingTime() {
    if (this.trailingTimeText().length > 0) {
      Text(this.trailingTimeText())
        .fontSize(DesignTokens.fontCaption())
        .fontColor(DesignTokens.labelTertiary(this.theme))
    }
  }
}
