/**
 * 播放页「更多操作」面板
 *
 * 页面把动作列表（图标 + 文案 + key）传进来，组件只负责呈现与回调：
 * 这样「动作有哪些、文案怎么变」留在页面（它知道播放状态），
 * 「面板长什么样、怎么收起」收敛在这里。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { BottomSheet } from '../../components/ui/BottomSheet';

/** 一行动作 */
export interface PlayActionRow {
  key: string;
  icon: Resource;
  label: string;
}

@Component
export struct MoreActionsSheet {
  @StorageProp('theme') theme: string = 'light';
  @Link visible: boolean;
  @Prop title: string = '';
  @Prop rows: PlayActionRow[] = [];
  onPick?: (key: string) => void;

  @Builder
  Row(action: PlayActionRow) {
    Row({ space: 10 }) {
      Stack() {
        Circle({ width: 26, height: 26 })
          .fill(DesignTokens.mutedFill(this.theme))
        Image(action.icon)
          .width(14)
          .height(14)
          .fillColor(DesignTokens.labelSecondary(this.theme))
      }

      Text(action.label)
        .fontSize(15)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(DesignTokens.touchTarget())
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.visible = false;
      if (this.onPick) {
        this.onPick(action.key);
      }
    })
  }

  @Builder
  Content() {
    Scroll() {
      Column() {
        ForEach(this.rows, (action: PlayActionRow) => {
          this.Row(action)
        }, (action: PlayActionRow) => action.key)
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxHeight: 420 })
    .scrollBar(BarState.Off)
  }

  build() {
    BottomSheet({
      visible: $visible,
      title: this.title,
      sheetSize: 'large',
      content: (): void => {
        this.Content();
      },
    })
  }
}
