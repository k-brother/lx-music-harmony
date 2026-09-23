/**
 * 播放队列面板
 *
 * 展示当前队列并高亮正在播放的一首，点击任意一首直接切歌。
 * 覆盖安卓 mini 播放条长按 `jumpListPosition()` 的意图，
 * 且对搜索结果、本地音乐这类"没有所属列表 id"的队列同样可用。
 *
 * 排序交互（真机发现系统拖放方案不可靠后重做）：
 *  - 原来用 ListItem 的 `onDragStart/onDrop`：真机上拖动不生效，还会把拖动误判成点击切歌；
 *  - 现在改为主流 App 的做法 —— 行尾「≡」手柄 + PanGesture：
 *    按住手柄上下拖，被拖的行跟手并浮起，松手按跨过的行数落位（跨几行就走几行），
 *    拖拽只发生在手柄上，不会和「长按整行删除」「点击整行切歌」冲突。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DesignTokens } from '../../theme/DesignTokens';
import { t, tf } from '../../service/LocalizationService';
import { LazyDataSource } from '../../utils/LazyDataSource';
import { BottomSheet } from '../../components/ui/BottomSheet';
import { appActionMenu } from '../../service/DialogService';
import { hapticService } from '../../service/HapticService';
import type { SongInfo } from '../../service/PlayerService';
import { isConfirmKey } from '../../utils/KeyboardTools';

@Component
export struct QueueSheet {
  @StorageProp('theme') theme: string = 'light';
  @Link @Watch('onVisibleChanged') visible: boolean;
  /** 队列可能上千首：@Watch 同步 LazyForEach 数据源，避免一次性建满所有行 */
  @Prop @Watch('onQueueChanged') queue: SongInfo[] = [];
  private queueSource: LazyDataSource<SongInfo> = new LazyDataSource<SongInfo>();
  /** 列表滚动控制：打开面板时定位到当前播放（队列上百首时很重要） */
  private listScroller: Scroller = new Scroller();
  private scrollTimer: number = -1;
  @Prop currentIndex: number = -1;
  onPick?: (index: number) => void;
  /** 拖动排序（长按行拖动） */
  onMove?: (from: number, to: number) => void;
  /** 长按菜单里选择「从队列移除」 */
  onRemove?: (index: number) => void;

  /** 正在被拖动的行下标（-1 表示没有拖拽） */
  @State dragFromIndex: number = -1;
  /** 拖动中的手指位移（px，用于让行跟手） */
  @State dragOffset: number = 0;
  /** 松手后会落到哪一行（-1 表示无） */
  @State dragTargetIndex: number = -1;
  /** 是否正在拖拽（拖拽期间禁用列表滚动，否则行会跟着手指滚走） */
  @State dragging: boolean = false;
  /** 按下时的屏幕 Y（px） */
  private dragStartY: number = 0;

  /**
   * 一行的高度（vp）。
   * TouchEvent 的 screenY 与 DesignTokens 的行高同为 vp 单位
   * （真机实测：注入了 240px 的滑动，screenY 只增加 ~71，正好是 1/密度，
   * 所以这里不能再乘密度，否则跨行数会被低估 3 倍而「拖了却不动」）。
   */
  private rowPitchVp(): number {
    return Math.max(1, DesignTokens.rowHeightTwoLine());
  }

  /** 手柄按下：记录起始行 */
  private beginDrag(index: number): void {
    hilog.info(0x0001, 'QueueSheet', 'drag start: index=%{public}d', index);
    hapticService.light();
    this.dragging = true;
    this.dragFromIndex = index;
    this.dragTargetIndex = index;
    this.dragOffset = 0;
  }

  /** 手柄拖动：跟手 + 实时算目标行（不立刻改数据，避免每帧重排列表） */
  private updateDrag(index: number, offsetY: number): void {
    this.dragOffset = offsetY;
    const pitch = this.rowPitchVp();
    const crossed = Math.round(offsetY / pitch);
    const target = Math.max(0, Math.min(this.queue.length - 1, index + crossed));
    this.dragTargetIndex = target;
  }

  /** 松手：跨过行数不为 0 才真正重排 */
  private endDrag(): void {
    const from = this.dragFromIndex;
    const to = this.dragTargetIndex;
    hilog.info(0x0001, 'QueueSheet', 'drag end: %{public}d -> %{public}d (offset=%{public}d)',
      from, to, Math.round(this.dragOffset));
    this.dragFromIndex = -1;
    this.dragOffset = 0;
    this.dragTargetIndex = -1;
    this.dragging = false;
    if (from < 0 || to < 0 || from === to) {
      return;
    }
    hapticService.light();
    if (this.onMove) {
      this.onMove(from, to);
    }
  }

  /** 行尾拖拽手柄 */
  aboutToAppear(): void {
    this.queueSource.reload(this.queue);
  }

  aboutToDisappear(): void {
    this.clearScrollTimer();
  }

  /** 队列变化（切歌、拖拽重排、删除）时同步渲染数据源 */
  onQueueChanged(): void {
    this.queueSource.reload(this.queue);
  }

  /**
   * 打开面板时定位到「正在播放」那一首。
   * 主流播放器都会这么做：队列上百首时，从顶部开始找当前曲目很折磨。
   * 延迟一小会儿是因为面板刚弹出时列表还没完成布局，直接 scrollToIndex 会被忽略。
   */
  onVisibleChanged(): void {
    this.clearScrollTimer();
    if (!this.visible) {
      return;
    }
    this.scrollTimer = setTimeout((): void => {
      this.scrollTimer = -1;
      this.scrollToCurrent();
    }, 150);
  }

  /** 滚动到当前曲目（留一行上下文，视觉上不贴顶） */
  private scrollToCurrent(): void {
    if (this.currentIndex < 0 || this.queue.length === 0) {
      return;
    }
    const target: number = Math.max(0, this.currentIndex - 1);
    try {
      this.listScroller.scrollToIndex(target, true);
    } catch (err) {
      hilog.warn(0x0001, 'QueueSheet', 'scrollToCurrent failed: %{public}s', JSON.stringify(err));
    }
  }

  private clearScrollTimer(): void {
    if (this.scrollTimer !== -1) {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = -1;
    }
  }

  @Builder
  DragHandle(index: number) {
    SymbolGlyph($r('sys.symbol.line_3_horizontal'))
      .fontSize(DesignTokens.fontLarge())
      .fontColor([DesignTokens.labelTertiary(this.theme)])
      .responseRegion(DesignTokens.touchRegion(20))
      // 吞掉点击：否则按下手柄松手时，事件会落到整行上触发「切歌」
      .accessibilityText(t('a11y_drag_handle'))
      .onClick(() => {})
      // 直接用原始触摸事件：手柄嵌在 List 里，PanGesture（含 priorityGesture）
      // 会被列表的滚动识别器抢走/取消，真机上表现为「拖不动、还切了歌」。
      // 这里在按下时禁用列表滚动（见 List 的 enableScrollInteraction），
      // 用 screenY 差值算跨了几行，松手才真正重排。
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          const touch = event.touches.length > 0 ? event.touches[0] : undefined;
          this.dragStartY = touch ? touch.screenY : 0;
          this.beginDrag(index);
        } else if (event.type === TouchType.Move) {
          const touch = event.touches.length > 0 ? event.touches[0] : undefined;
          if (touch) {
            this.updateDrag(index, touch.screenY - this.dragStartY);
          }
        } else if (event.type === TouchType.Up) {
          // 松手那一帧的位置要补算一次：Move 事件可能被合并，
          // 只用最后一个 Move 会低估位移（真机上表现为「拖了一行却回到原位」）。
          const last = event.changedTouches.length > 0 ? event.changedTouches[0] : undefined;
          if (last) {
            this.updateDrag(index, last.screenY - this.dragStartY);
          }
          this.endDrag();
        } else {
          // Cancel：直接复位，不重排
          this.endDrag();
        }
      })
  }

  @Builder
  Row(song: SongInfo, index: number) {
    Row() {
      Text((index + 1).toString())
        .fontSize(DesignTokens.fontCaption())
        .fontColor(index === this.currentIndex ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme))
        .width(24)
        .textAlign(TextAlign.Center)

      Column({ space: 2 }) {
        Text(song.title)
          .fontSize(DesignTokens.fontSubhead())
          .fontColor(index === this.currentIndex ? DesignTokens.accent() : DesignTokens.labelPrimary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(song.artist)
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 8 })

      if (index === this.currentIndex) {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(DesignTokens.fontHeadline())
          .fontColor([DesignTokens.accent()])
      }

      this.DragHandle(index)
    }
    .width('100%')
    .height(DesignTokens.rowHeightTwoLine())
    .alignItems(VerticalAlign.Center)
    // 拖动中的行：跟手位移 + 浮起，让用户看清自己抓的是哪一行
    .translate({ y: this.dragFromIndex === index ? this.dragOffset : 0 })
    .scale(this.dragFromIndex === index ? { x: 1.02, y: 1.02 } : { x: 1, y: 1 })
    .backgroundColor(this.dragFromIndex === index || this.dragTargetIndex === index
      ? DesignTokens.cardHover(this.theme)
      : Color.Transparent)
    .borderRadius(this.dragFromIndex === index ? 10 : 0)
    .shadow(this.dragFromIndex === index ? DesignTokens.cardShadow(this.theme) : undefined)
    .zIndex(this.dragFromIndex === index ? 1 : 0)
    .accessibilityText(t('a11y_play'))
    // 2in1：队列行给悬停反馈 + 键盘可聚焦（回车 = 切到这首）
    .hoverEffect(HoverEffect.Highlight)
    .focusable(true)
    .onKeyEvent((event: KeyEvent): void => {
      if (isConfirmKey(event)) {
        this.visible = false;
        if (this.onPick) {
          this.onPick(index);
        }
      }
    })
    .onClick(() => {
      this.visible = false;
      if (this.onPick) {
        this.onPick(index);
      }
    })
    .gesture(LongPressGesture().onAction(() => {
      void this.openRowMenu(index);
    }))
  }

  /** 长按行：与主流播放器一致，给出「从队列移除」 */
  private async openRowMenu(index: number): Promise<void> {
    if (!this.onRemove) {
      return;
    }
    const song = this.queue[index];
    if (!song) {
      return;
    }
    const picked = await appActionMenu(`${song.title} - ${song.artist}`, [
      t('play_queue_remove'),
    ]);
    if (picked === 0) {
      this.visible = false;
      this.onRemove(index);
    }
  }

  @Builder
  Content() {
    if (this.queue.length === 0) {
      Text(t('list_empty'))
        .fontSize(DesignTokens.fontBody())
        .fontColor(DesignTokens.labelSecondary(this.theme))
        .padding({ top: 20, bottom: 20 })
    } else {
      List({ scroller: this.listScroller }) {
        LazyForEach(this.queueSource, (song: SongInfo, index: number) => {
          ListItem() {
            this.Row(song, index)
          }
          // 侧滑移除：与长按菜单同一个动作，商业播放器的常见手势
          .swipeAction({
            end: {
              builder: (): void => {
                this.RemoveAction(index);
              },
              onAction: (): void => {
                if (this.onRemove) {
                  this.onRemove(index);
                }
              },
              actionAreaDistance: 56,
            },
          })
        }, (song: SongInfo, index: number) => `${song.id}_${index}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      // 预建可视区外的若干行，滚动更顺（LazyForEach 的配套项）
      .cachedCount(6)
      // 拖拽排序期间锁住滚动，避免列表跟着手指滚
      .enableScrollInteraction(!this.dragging)
    }
  }

  /** 侧滑露出的「移除」按钮 */
  @Builder
  RemoveAction(index: number) {
    Row() {
      Text(t('play_queue_remove'))
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(DesignTokens.onAccent())
        .fontWeight(FontWeight.Medium)
    }
    .width(96)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(DesignTokens.danger())
    .onClick(() => {
      if (this.onRemove) {
        this.onRemove(index);
      }
    })
  }

  build() {
    BottomSheet({
      visible: $visible,
      title: tf('play_queue_count', [this.queue.length.toString()]),
      sheetSize: 'large',
      // 队列上百首时的必备入口：一键回到正在播放那一首
      trailing: (): void => {
        this.ScrollToCurrentAction();
      },
      content: (): void => {
        this.Content();
      },
    })
  }

  /** 标题栏右侧：定位到当前播放 */
  @Builder
  ScrollToCurrentAction() {
    Stack() {
      Circle({ width: 30, height: 30 })
        .fill(DesignTokens.mutedFill(this.theme))
      SymbolGlyph($r('sys.symbol.dart_target'))
        .fontSize(DesignTokens.fontSubhead())
        .fontColor([DesignTokens.labelSecondary(this.theme)])
    }
    .width(DesignTokens.touchTarget())
    .height(DesignTokens.touchTarget())
    .accessibilityText(t('a11y_scroll_to_current'))
    .onClick(() => {
      hapticService.selection();
      this.scrollToCurrent();
    })
  }
}
