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
import { isConfirmKey } from '../../utils/KeyboardTools';
import { composeRowDurationText, composeRowSubtitle } from '../../core/list/RowTexts';

@Component
export struct ListRow {
  @StorageProp('theme') theme: string = 'light';
  /** 序号（showIndex 为 true 时展示；<=0 表示不展示） */
  @Prop index: number = 0;
  @Prop title: string = '';
  /** 直传副标题（自定义文案，如下载状态）；与结构化字段二选一 */
  @Prop subtitle: string = '';
  /**
   * 结构化副标题：歌手 / 专辑 / 音源。
   * 传了就由组件按「设置 → 列表 → 显示专辑 / 显示音源」统一裁剪，
   * 各页面不用再各自拼字符串（此前只有一个页面响应这两个设置）。
   */
  @Prop singer: string = '';
  @Prop album: string = '';
  @Prop sourceId: string = '';
  /** 结构化时长（秒）：传了就按「设置 → 列表 → 显示时长」决定是否显示 */
  @Prop durationSeconds: number = 0;
  /** 封面地址（为空且 showIndex=false 时显示占位图标） */
  @Prop cover: string = '';
  /** 右侧附加文本（时长/来源等） */
  @Prop trailingText: string = '';
  /** 设置 → 列表 */
  @StorageProp('showListAlbum') showListAlbum: boolean = true;
  @StorageProp('showListSource') showListSource: boolean = true;
  @StorageProp('showListDuration') showListDuration: boolean = true;
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

  /** 副标题：结构化字段优先（带设置裁剪），否则用调用方直传的文本 */
  private rowSubtitle(): string {
    if (this.singer.length === 0 && this.album.length === 0 && this.sourceId.length === 0) {
      return this.subtitle;
    }
    return composeRowSubtitle(this.singer, this.album, this.sourceId, this.showListAlbum, this.showListSource);
  }

  /** 右侧时长：结构化时长优先，否则用调用方直传的文本 */
  private rowTrailingText(): string {
    if (this.durationSeconds > 0) {
      return composeRowDurationText(this.durationSeconds, this.showListDuration);
    }
    return this.trailingText;
  }

  /** 行首：序号 / 封面 / 占位图标（三者互斥） */
  @Builder
  RowLeading() {
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
        SymbolGlyph($r('sys.symbol.music_note_list'))
          .fontSize(DesignTokens.fontDisplay())
          .fontColor([DesignTokens.labelTertiary(this.theme)])
      }
      .width(DesignTokens.rowCover())
      .height(DesignTokens.rowCover())
      .borderRadius(DesignTokens.radiusCover())
      .backgroundColor(DesignTokens.mutedFill(this.theme))
      .justifyContent(FlexAlign.Center)
    }
  }

  /** 主标题 + 副标题（副标题是否显示专辑/音源由 RowTexts 统一裁剪） */
  @Builder
  RowTitles() {
    Column({ space: 2 }) {
      Text(this.title)
        .fontSize(DesignTokens.fontTitle())
        .fontColor(this.active ? DesignTokens.accent() : DesignTokens.labelPrimary(this.theme))
        .maxLines(this.twoLine ? 2 : 1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      if (this.rowSubtitle().length > 0) {
        Text(this.rowSubtitle())
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
  }

  /** 行尾：时长文本 + 页面自定义动作插槽 */
  @Builder
  RowTrailing() {
    if (this.rowTrailingText().length > 0) {
      Text(this.rowTrailingText())
        .fontSize(DesignTokens.fontCaption())
        .fontColor(DesignTokens.labelTertiary(this.theme))
    }
    if (this.trailing) {
      this.trailing()
    }
  }

  build() {
    Column() {
      Row() {
        this.RowLeading()
        this.RowTitles()
        this.RowTrailing()
      }
      .width('100%')
      .height(this.twoLine || this.rowSubtitle().length > 0
        ? DesignTokens.rowHeightTwoLine() : DesignTokens.rowHeight())
      .alignItems(VerticalAlign.Center)

      if (this.divider) {
        Divider()
          .strokeWidth(0.5)
          .color(DesignTokens.cardBorder(this.theme))
          .margin({ left: DesignTokens.rowInset() })
      }
    }
    .width('100%')
    // 2in1（PC/平板接鼠标）下的悬停反馈：系统标准高亮，触屏设备无副作用
    .hoverEffect(HoverEffect.Highlight)
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
    // 2in1（PC 接鼠标）：右键等同长按，直接出同一套行菜单
    .onMouse((event: MouseEvent): void => {
      if (event.action === MouseAction.Press && event.button === MouseButton.Right && this.onLongPress) {
        this.onLongPress();
      }
    })
    // 2in1（PC 接键盘）：列表行可聚焦，回车/空格等同于点一下
    .focusable(true)
    .onKeyEvent((event: KeyEvent): void => {
      if (isConfirmKey(event) && this.onTap) {
        this.onTap();
      }
    })
  }

  @BuilderParam trailing?: () => void;
}
