/**
 * 统一底部面板（Bottom Sheet）
 *
 * 取代各页面手写的「Stack + 半透明遮罩 + 圆角 Column」。
 *
 * 实现要点：底层用系统 `bindSheet`，把面板交给窗口级浮层渲染。
 * 早期版本自己画满屏 Stack，挂在页面 Column 里会把正文挤扁；
 * 改成 `position({x:0,y:0})` 后又会被 Scroll 容器裁剪（设置页点选项没反应就是这个原因）。
 * `bindSheet` 由系统承载，挂在任何位置都不会被裁剪，并自带遮罩、圆角、
 * 下拉关闭与安全区处理，与系统应用的手感一致。
 */
import { DesignTokens } from '../../theme/DesignTokens';

@Component
export struct BottomSheet {
  @StorageProp('theme') theme: string = 'light';
  /** 控制显示（由父页面 @State 双向绑定） */
  @Link visible: boolean;
  /** 面板内容 */
  @BuilderParam content: () => void;
  /** 标题（可空） */
  @Prop title: string = '';
  /** 展开高度档位：medium（半屏，默认）/ large（接近全屏） */
  @Prop sheetSize: string = 'medium';
  /** 被关闭（点遮罩/下拉）时的回调，用于区分「取消」与「完成」 */
  onDismiss?: () => void;

  @Builder
  SheetContent() {
    Column() {
      if (this.title.length > 0) {
        Text(this.title)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ bottom: 10 })
      }

      this.content()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 16 })
  }

  build() {
    // 锚点：真正的面板由 bindSheet 渲染在窗口浮层上。
    // 锚点需要是有效尺寸的节点，否则 bindSheet 不会挂载（这里是 1×1 的透明占位）。
    Column()
      .width(1)
      .height(1)
      .opacity(0)
      .bindSheet($$this.visible, this.SheetContent(), {
        height: this.sheetSize === 'large' ? SheetSize.LARGE : SheetSize.MEDIUM,
        dragBar: true,
        showClose: false,
        backgroundColor: DesignTokens.card(this.theme),
        maskColor: DesignTokens.maskColor(),
        onDisappear: (): void => {
          if (this.onDismiss) {
            this.onDismiss();
          }
        },
      })
  }
}
