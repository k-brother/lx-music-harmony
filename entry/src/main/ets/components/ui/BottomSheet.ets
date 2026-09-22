/**
 * 统一底部面板（Bottom Sheet）
 *
 * 取代各页面手写的「Stack + 半透明遮罩 + 圆角 Column + onClick 空实现」：
 * - 遮罩点击关闭、面板内点击不冒泡
 * - 圆角、拖拽把手、安全区底部内边距统一
 * - 出现/消失带统一动效（translate + opacity），符合商业化 App 的手感
 *
 * 布局约定：面板必须「脱离文档流」覆盖在页面上。
 * 早期版本无论 visible 真假都渲染一个满屏 Stack，调用方把它放进页面 Column 后
 * 会把正文挤扁、面板本身也被顶到屏幕外（歌单排序面板点开无反应就是这个原因），
 * 因此这里用 `visible` 条件渲染 + `position({x:0,y:0})` 固定为浮层。
 */
import { DesignTokens } from '../../theme/DesignTokens';

@Component
export struct BottomSheet {
  @StorageProp('theme') theme: string = 'light';
  /** 控制显示（由父页面 @State 双向绑定） */
  @Link visible: boolean;
  /** 面板内容 */
  @BuilderParam content: () => void;
  /** 标题（可空；为空时不显示标题行和把手） */
  @Prop title: string = '';
  /** 面板最大高度占比（字符串百分比，默认 70%） */
  @Prop maxHeightPercent: string = '70%';

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.42)')
          .onClick(() => {
            this.visible = false;
          })

        Column() {
          // 拖拽把手（视觉暗示可下拉关闭）
          Row()
            .width(36)
            .height(4)
            .borderRadius(2)
            .backgroundColor(DesignTokens.mutedFill(this.theme))
            .margin({ top: 8, bottom: 6 })

          if (this.title.length > 0) {
            Text(this.title)
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ bottom: 8 })
          }

          this.content()
        }
        .width('100%')
        .constraintSize({ maxHeight: this.maxHeightPercent })
        .padding({ left: 16, right: 16, bottom: 16 })
        .backgroundColor(DesignTokens.card(this.theme))
        .borderRadius({ topLeft: DesignTokens.radiusSheet(), topRight: DesignTokens.radiusSheet() })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        .onClick(() => {
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: DesignTokens.motionNormal() })
          .combine(TransitionEffect.translate({ y: 40 }).animation({ duration: DesignTokens.motionNormal(), curve: Curve.EaseOut })))
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .zIndex(100)
    }
  }
}
