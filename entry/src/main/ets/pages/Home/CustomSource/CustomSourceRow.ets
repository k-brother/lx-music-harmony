/**
 * 自定义源行（启用开关 / 使用中角标 / 更新 / 删除）
 *
 * 从 CustomSourceView 抽成组件：用 @Prop 接收该行数据（启用态属于会变的状态，
 * 不能走 @Builder 参数），三个动作只回调 id，由页面去调 PluginManager。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { t } from '../../../service/LocalizationService';

@Component
export struct CustomSourceRow {
  @StorageProp('theme') theme: string = 'light';
  @Prop sourceId: string = '';
  @Prop sourceName: string = '';
  @Prop sourceUrl: string = '';
  @Prop version: string = '';
  @Prop author: string = '';
  /** 启用中（不能叫 enabled：与组件内置属性重名） */
  @Prop isEnabled: boolean = false;
  /** 有任一源在切换中时禁用开关，避免并发操作 */
  @Prop busy: boolean = false;
  onToggle?: (sourceId: string, enabled: boolean) => void;
  onUpdate?: (sourceId: string) => void;
  onRemove?: (sourceId: string) => void;

  private subtitle(): string {
    if (this.version.length > 0) {
      const authorPart: string = this.author.length > 0
        ? `  ${t('label_author_colon')} ${this.author}`
        : '';
      return `${t('label_version_colon')} ${this.version}${authorPart}`;
    }
    return this.sourceUrl;
  }

  build() {
    Column() {
      Row() {
        Column() {
          Row() {
            Text(this.sourceName.length > 0 ? this.sourceName : this.sourceUrl)
              .fontSize(15)
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (this.isEnabled) {
              Text(t('custom_source_in_use'))
                .fontSize(10)
                .fontColor(DesignTokens.accent())
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(8)
                .border({ width: 1, color: DesignTokens.accent() })
                .margin({ left: 6 })
            }
          }
          .width('100%')

          Text(this.subtitle())
            .fontSize(11)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.isEnabled })
          .enabled(!this.busy)
          .onChange((isOn: boolean) => {
            if (isOn === this.isEnabled) {
              return;
            }
            if (this.onToggle) {
              this.onToggle(this.sourceId, isOn);
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row({ space: 16 }) {
        Text(t('custom_source_update'))
          .fontSize(13)
          .fontColor(DesignTokens.accent())
          .padding({ top: 6, bottom: 2, right: 8 })
          .onClick(() => {
            if (this.onUpdate) {
              this.onUpdate(this.sourceId);
            }
          })
        Text(t('delete'))
          .fontSize(13)
          .fontColor(DesignTokens.danger())
          .padding({ top: 6, bottom: 2 })
          .onClick(() => {
            if (this.onRemove) {
              this.onRemove(this.sourceId);
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(10)
    .border({ width: 0.33, color: DesignTokens.cardBorder(this.theme) })
    .margin({ left: 16, right: 16, bottom: 8 })
  }
}
