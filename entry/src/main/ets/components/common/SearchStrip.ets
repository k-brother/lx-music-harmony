/**
 * 统一搜索条：灰底圆角 + 放大镜 + 单行输入（歌单主页 / 排行榜等共用）
 * 父组件在 aboutToAppear 中向 actions 赋值回调（ArkTS 不宜用函数型 @Prop）
 */
import { DesignTokens } from '../../theme/DesignTokens';

/** 父组件持有同一实例并赋值三个回调 */
export class SearchStripActions {
  onMagnifierClick: () => void = () => {};
  onSubmit: () => void = () => {};
  onTextChange: (t: string) => void = () => {};
}

const EMPTY_SEARCH_STRIP_ACTIONS: SearchStripActions = new SearchStripActions();

@Component
export struct SearchStrip {
  @StorageProp('theme') theme: string = 'light';
  @Link text: string;
  @Prop placeholder: string = '';
  /** 水平外边距（与父级 padding 配合可对齐到同一视觉边距） */
  @Prop marginH: number = 16;
  @Prop marginV: number = 6;
  /** true: 点击整条进入搜索页；false: 直接在条内输入 */
  @Prop tapToOpenOnly: boolean = false;
  @Prop actions: SearchStripActions = EMPTY_SEARCH_STRIP_ACTIONS;

  build() {
    Row() {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(20)
        .fontColor([DesignTokens.labelSecondary(this.theme)])
        .margin({ left: 10, right: 6 })
        .onClick(() => {
          this.actions.onMagnifierClick();
        })
      if (this.tapToOpenOnly) {
        Text(this.text.trim().length > 0 ? this.text : this.placeholder)
          .layoutWeight(1)
          .fontSize(16)
          .fontColor(this.text.trim().length > 0 ? DesignTokens.labelPrimary(this.theme) : DesignTokens.labelTertiary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ right: 10 })
      } else {
        TextInput({ placeholder: this.placeholder, text: this.text })
          .layoutWeight(1)
          .height(DesignTokens.heightSearchField())
          .backgroundColor('rgba(0,0,0,0)')
          .fontSize(16)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .placeholderColor(DesignTokens.labelTertiary(this.theme))
          .padding({ right: 10 })
          .onChange((value: string) => {
            this.text = value;
            this.actions.onTextChange(value);
          })
          .onSubmit(() => {
            this.actions.onSubmit();
          })
      }
    }
    .width('100%')
    .height(DesignTokens.heightSearchField())
    .margin({ left: this.marginH, right: this.marginH, top: this.marginV, bottom: this.marginV })
    .backgroundColor(DesignTokens.mutedFill(this.theme))
    .borderRadius(DesignTokens.radiusSearch())
    .border({ width: 0.5, color: DesignTokens.searchFieldBorder(this.theme) })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      if (this.tapToOpenOnly) {
        this.actions.onMagnifierClick();
      }
    })
  }
}
