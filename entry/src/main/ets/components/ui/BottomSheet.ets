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

/**
 * 关闭面板：先收起，再通知调用方（顺序固定，避免回调里读到的还是「打开」态）。
 *
 * 各个面板组件都写了同一段 `this.visible = false; if (this.onCancel) ...`，
 * 这里收成一个函数，写法统一为 `this.visible = dismissSheet(this.onCancel);`
 */
export function dismissSheet(onDismiss?: () => void): boolean {
  if (onDismiss) {
    onDismiss();
  }
  return false;
}

@Component
export struct BottomSheet {
  @StorageProp('theme') theme: string = 'light';
  /** 控制显示（由父页面 @State 双向绑定） */
  @Link visible: boolean;
  /** 面板内容 */
  @BuilderParam content: () => void;
  /** 标题（可空） */
  @Prop title: string = '';
  /** 标题栏右侧动作（可空）：面板里常用的「定位到当前/清空」等入口 */
  @BuilderParam trailing?: () => void;
  /**
   * 展开高度档位：
   * - content（默认）：高度 = 内容高度（选项/表单有几行就是多高，不留白）
   * - large：接近全屏（队列、更多操作、换源这类内容多的面板）
   */
  @Prop sheetSize: string = 'content';
  /** 被关闭（点遮罩/下拉）时的回调，用于区分「取消」与「完成」 */
  onDismiss?: () => void;

  @Builder
  SheetContent() {
      Column() {
      if (this.title.length > 0 || this.trailing) {
        // 标题保持居中：右侧动作叠在标题栏上，而不是把标题挤到一边
        Stack({ alignContent: Alignment.End }) {
          Text(this.title)
            .fontSize(DesignTokens.fontHeadline())
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ bottom: 10 })
          if (this.trailing) {
            this.trailing()
          }
        }
        .width('100%')
      }

      this.content()
      }
      .width('100%')
      // 内容高度交给内容自己决定：
      // 写死 height('100%') 会把面板顶成整屏（选项少时下面一大片空白）；
      // 面板整体高度由 bindSheet 的 FIT_CONTENT 按这里的内容量出来。
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
        // 高度 = 内容高度；声明 large 的面板仍按大面板展示
        height: this.sheetSize === 'large' ? SheetSize.LARGE : SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        // 玻璃材质：面板是浮在页面内容之上的 chrome，交给系统材质（bindSheet 的 blurStyle
        // 是官方给面板用的模糊通路，任何设备都有；底色半透明让下面的内容透出来）
        backgroundColor: DesignTokens.glassFill(this.theme),
        blurStyle: BlurStyle.COMPONENT_THICK,
        maskColor: DesignTokens.maskColor(),
        onDisappear: (): void => {
          if (this.onDismiss) {
            this.onDismiss();
          }
        },
      })
  }
}
