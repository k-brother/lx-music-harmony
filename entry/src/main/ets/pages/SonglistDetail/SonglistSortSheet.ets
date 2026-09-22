/**
 * 歌单排序面板（底部面板）
 *
 * 排序字段（歌曲名/歌手/专辑/时长/音源）× 排序方式（升序/降序/随机）。
 * 选中态用强调色胶囊，确认后由页面执行排序（applySort）。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { BottomSheet } from '../../components/ui/BottomSheet';
import { SettingsSection } from '../../components/ui/SettingsSection';
import type { SettingOption, SettingSectionItem } from '../../components/ui/SettingsTypes';

@Component
export struct SonglistSortSheet {
  @StorageProp('theme') theme: string = 'light';
  @Link visible: boolean;
  @Prop field: string = 'name';
  @Prop order: string = 'up';
  /** 确认排序（页面负责排序与落库） */
  onApply?: (field: string, order: string) => void;

  @State draftField: string = 'name';
  @State draftOrder: string = 'up';

  aboutToAppear() {
    this.draftField = this.field;
    this.draftOrder = this.order;
  }

  private fieldOptions(): SettingOption[] {
    return [
      { label: t('list_sort_by_name'), value: 'name' },
      { label: t('list_sort_by_singer'), value: 'singer' },
      { label: t('list_sort_by_album'), value: 'album' },
      { label: t('list_sort_by_time'), value: 'time' },
      { label: t('list_sort_by_source'), value: 'source' },
    ];
  }

  private orderOptions(): SettingOption[] {
    return [
      { label: t('list_sort_up'), value: 'up' },
      { label: t('list_sort_down'), value: 'down' },
      { label: t('list_sort_random'), value: 'random' },
    ];
  }

  private buildItems(): SettingSectionItem[] {
    return [
      {
        type: 'select',
        title: t('list_sort_by_field'),
        value: this.draftField,
        options: this.fieldOptions(),
        onChange: (value: string): void => {
          this.draftField = value;
        },
      },
      {
        type: 'select',
        title: t('list_sort_by_type'),
        value: this.draftOrder,
        options: this.orderOptions(),
        onChange: (value: string): void => {
          this.draftOrder = value;
        },
      },
    ];
  }

  @Builder
  Content() {
    Column() {
      // 排序方式用胶囊直接切换（比再点一层面板更快）
      Row({ space: 8 }) {
        ForEach(this.orderOptions(), (option: SettingOption) => {
          Text(option.label)
            .fontSize(13)
            .fontColor(this.draftOrder === option.value ? '#FFFFFF' : DesignTokens.labelPrimary(this.theme))
            .backgroundColor(this.draftOrder === option.value
              ? DesignTokens.accent()
              : DesignTokens.mutedFill(this.theme))
            .borderRadius(DesignTokens.radiusPill())
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .onClick(() => {
              this.draftOrder = option.value;
            })
        }, (option: SettingOption) => option.value)
      }
      .width('100%')
      .margin({ bottom: 12 })

      SettingsSection({ title: '', items: this.buildItems() })

      Row({ space: 12 }) {
        Button(t('cancel'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(DesignTokens.touchTarget())
          .fontSize(16)
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .backgroundColor(DesignTokens.mutedFill(this.theme))
          .onClick(() => {
            this.visible = false;
          })
        Button(t('confirm'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(DesignTokens.touchTarget())
          .fontSize(16)
          .fontColor('#FFFFFF')
          .backgroundColor(DesignTokens.accent())
          .onClick(() => {
            this.visible = false;
            if (this.onApply) {
              this.onApply(this.draftField, this.draftOrder);
            }
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
  }

  build() {
    BottomSheet({
      visible: $visible,
      title: t('list_sort'),
      content: (): void => {
        this.Content();
      },
    })
  }
}
