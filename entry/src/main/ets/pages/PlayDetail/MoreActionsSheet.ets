/**
 * 播放页「更多操作」面板
 *
 * 页面把动作分组（图标 + 文案 + key）传进来，组件只负责呈现与回调：
 * 这样「动作有哪些、文案怎么变」留在页面（它知道播放状态），
 * 「面板长什么样、怎么收起」收敛在这里。
 *
 * 为什么要分组：这一栏有 14 个动作，平铺时要一个个找；
 * 按「歌曲 / 播放 / 歌词 / 保存」分组后与华为音乐、Apple Music 的「⋯」菜单一致，
 * 用户知道去哪一类里找（分组标题用小号次级色，不抢主文案）。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { isConfirmKey } from '../../utils/KeyboardTools';
import { BottomSheet } from '../../components/ui/BottomSheet';

/** 一行动作 */
export interface PlayActionRow {
  key: string;
  icon: Resource;
  label: string;
}

/** 一个分组（标题 + 动作） */
export interface PlayActionSection {
  title: string;
  rows: PlayActionRow[];
}

@Component
export struct MoreActionsSheet {
  @StorageProp('theme') theme: string = 'light';
  @Link visible: boolean;
  @Prop title: string = '';
  @Prop sections: PlayActionSection[] = [];
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
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(DesignTokens.touchTarget())
    .alignItems(VerticalAlign.Center)
    // 2in1：面板行同样给悬停反馈 + 键盘可聚焦（PC 上没有电容按压，反馈全靠它）
    .hoverEffect(HoverEffect.Highlight)
    .focusable(true)
    .onKeyEvent((event: KeyEvent): void => {
      if (isConfirmKey(event)) {
        this.visible = false;
        if (this.onPick) {
          this.onPick(action.key);
        }
      }
    })
    .onClick(() => {
      this.visible = false;
      if (this.onPick) {
        this.onPick(action.key);
      }
    })
  }

  @Builder
  SectionHeader(title: string) {
    Text(title)
      .fontSize(DesignTokens.fontCaption())
      .fontColor(DesignTokens.labelTertiary(this.theme))
      .width('100%')
      .padding({ left: 2, top: 14, bottom: 6 })
  }

  @Builder
  Content() {
    Scroll() {
      Column() {
        ForEach(this.sections, (section: PlayActionSection) => {
          this.SectionHeader(section.title)
          ForEach(section.rows, (action: PlayActionRow) => {
            this.Row(action)
          }, (action: PlayActionRow) => action.key)
        }, (section: PlayActionSection) => section.title)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    // Scroll 默认 align 是 Center：动作少时整块会被居中，面板上下留白（顶部对齐）
    .align(Alignment.TopStart)
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
