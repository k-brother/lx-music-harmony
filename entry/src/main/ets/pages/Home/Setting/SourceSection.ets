/**
 * 设置 → 音源
 *
 * 设置页只放两行：自动跨源开关 + 音源管理入口。
 * 管理面板（启用/停用/上下排序）走 BottomSheet，行内就是全部操作。
 *
 * 顺序语义集中在 core/music/SourcePolicy.ets：
 * 搜索聚合与播放失败换源读同一份「用户顺序 ∩ 未停用」视图，
 * 这里只负责把三个设置值读进来、写回去。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { t, tf, sourceLabel } from '../../../service/LocalizationService';
import { settingsService } from '../../../service/SettingsService';
import { appToast } from '../../../service/DialogService';
import { hapticService } from '../../../service/HapticService';
import { Subscription } from '../../../service/Subscription';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import { BottomSheet } from '../../../components/ui/BottomSheet';
import type { SettingSectionItem } from '../../../components/ui/SettingsTypes';
import { toggleRow, buttonRow } from '../../../components/ui/SettingsRows';
import { SUPPORTED_SOURCES } from '../../../types/MusicSource';
import type { BuiltinSource } from '../../../types/MusicSource';

@Component
export struct SourceSection {
  @StorageProp('theme') theme: string = 'light';
  @State autoSwitch: boolean = true;
  /** 用户排序后的全部音源（含已停用的，停用状态另存一份列表） */
  @State sourceOrder: BuiltinSource[] = [];
  @State disabledSources: BuiltinSource[] = [];
  @State showManage: boolean = false;

  private settingsWatch: Subscription = new Subscription();

  aboutToAppear() {
    this.loadFromSettings();
    // 外部改动（恢复默认 / 同步下发）也要刷新本分组
    this.settingsWatch.bindSettings((): void => {
      this.loadFromSettings();
    });
  }

  aboutToDisappear() {
    this.settingsWatch.detach();
  }

  private loadFromSettings(): void {
    const settings = settingsService.get();
    this.autoSwitch = settings.autoSourceSwitch;
    this.sourceOrder = this.fullOrder(settings.sourceOrder);
    this.disabledSources = settings.disabledSources.slice();
  }

  /** 排序列表兜底：设置里缺失的源按默认顺序补在末尾，避免新源上线后 invisible */
  private fullOrder(order: BuiltinSource[]): BuiltinSource[] {
    const merged: BuiltinSource[] = order.slice();
    for (let i = 0; i < SUPPORTED_SOURCES.length; i++) {
      const id = SUPPORTED_SOURCES[i] as BuiltinSource;
      if (merged.indexOf(id) < 0) {
        merged.push(id);
      }
    }
    return merged;
  }

  private isEnabled(id: BuiltinSource): boolean {
    return this.disabledSources.indexOf(id) < 0;
  }

  private enabledCount(): number {
    return this.sourceOrder.length - this.disabledSources.length;
  }

  private persist(): void {
    void settingsService.update({
      sourceOrder: this.sourceOrder.slice(),
      disabledSources: this.disabledSources.slice(),
      autoSourceSwitch: this.autoSwitch,
    });
  }

  private setEnabled(id: BuiltinSource, enabled: boolean): void {
    if (!enabled && this.enabledCount() <= 1) {
      appToast(t('source_last_enabled'));
      return;
    }
    const next = this.disabledSources.slice();
    const at = next.indexOf(id);
    if (enabled && at >= 0) {
      next.splice(at, 1);
    } else if (!enabled && at < 0) {
      next.push(id);
    }
    this.disabledSources = next;
    this.persist();
  }

  /** 上移/下移：交换位置后整体重赋值（@State 数组元素交换不触发刷新） */
  private move(id: BuiltinSource, delta: number): void {
    const at = this.sourceOrder.indexOf(id);
    const to = at + delta;
    if (at < 0 || to < 0 || to >= this.sourceOrder.length) {
      return;
    }
    const next = this.sourceOrder.slice();
    const tmp: BuiltinSource = next[at];
    next[at] = next[to];
    next[to] = tmp;
    this.sourceOrder = next;
    hapticService.light();
    this.persist();
  }

  private buildItems(): SettingSectionItem[] {
    const items: SettingSectionItem[] = [];
    items.push(toggleRow(
      t('settings_auto_source_switch'), this.autoSwitch,
      (value: boolean): void => {
        this.autoSwitch = value;
        this.persist();
      },
      t('settings_auto_source_switch_desc')));
    items.push(buttonRow(
      t('settings_source_manage'),
      (): void => {
        this.showManage = true;
      },
      { description: tf('settings_source_manage_desc', [String(this.enabledCount()), String(this.sourceOrder.length)]) }));
    return items;
  }

  /** 能不能沿 delta 方向移动（越界即不可点，按钮变暗） */
  private canMove(id: BuiltinSource, delta: number): boolean {
    const at = this.sourceOrder.indexOf(id);
    const to = at + delta;
    return at >= 0 && to >= 0 && to < this.sourceOrder.length;
  }

  @Builder
  MoveButton(symbol: Resource, label: string, id: BuiltinSource, delta: number, onTap: () => void) {
    Column() {
      SymbolGlyph(symbol)
        .fontSize(DesignTokens.fontHeadline())
        .fontColor([this.canMove(id, delta) ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme)])
        .opacity(this.canMove(id, delta) ? 1 : 0.35)
    }
    .width(DesignTokens.touchTarget())
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .accessibilityText(label)
    .onClick(() => {
      if (this.canMove(id, delta)) {
        onTap();
      }
    })
  }

  @Builder
  SourceRow(id: BuiltinSource) {
    Row() {
      Text(sourceLabel(id))
        .fontSize(DesignTokens.fontSubhead())
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isEnabled(id) ? DesignTokens.labelPrimary(this.theme) : DesignTokens.labelTertiary(this.theme))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      this.MoveButton($r('sys.symbol.chevron_up'), t('source_move_up'), id, -1, (): void => {
        this.move(id, -1);
      })
      this.MoveButton($r('sys.symbol.chevron_down'), t('source_move_down'), id, 1, (): void => {
        this.move(id, 1);
      })

      Toggle({ type: ToggleType.Switch, isOn: this.isEnabled(id) })
        .selectedColor(DesignTokens.accent())
        .onChange((isOn: boolean) => {
          hapticService.light();
          this.setEnabled(id, isOn);
        })
    }
    .width('100%')
    .height(DesignTokens.rowHeight())
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  /** 管理面板：每行 = 源名 + 上移/下移 + 启用开关 */
  @Builder
  ManagePanel() {
    Column() {
      List() {
        ForEach(this.sourceOrder, (id: BuiltinSource, index: number) => {
          ListItem() {
            Column() {
              this.SourceRow(id)

              if (index < this.sourceOrder.length - 1) {
                Divider()
                  .strokeWidth(0.5)
                  .color(DesignTokens.hairlineSeparator(this.theme))
                  .margin({ left: 16, right: 16 })
              }
            }
            .width('100%')
          }
        }, (id: BuiltinSource): string => id)
      }
      .width('100%')
      .constraintSize({ maxHeight: 360 })
      .scrollBar(BarState.Off)

      Text(t('settings_source_order_hint'))
        .fontSize(DesignTokens.fontCaption())
        .fontColor(DesignTokens.labelTertiary(this.theme))
        .width('100%')
        .padding({ top: 10 })
    }
    .width('100%')
  }

  build() {
    Stack() {
      SettingsSection({ title: t('settings_source'), items: this.buildItems() })

      if (this.showManage) {
        BottomSheet({
          visible: $showManage,
          title: t('settings_source_manage'),
          content: (): void => {
            this.ManagePanel();
          },
        })
      }
    }
    .width('100%')
  }
}
