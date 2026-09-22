/**
 * 全局面板宿主（挂在页面根节点之上）
 *
 * 与 service/SheetService 配对：任何页面/分组都可以命令式调用
 * `sheetService.select(...)` / `sheetService.input(...)`，
 * 真正的浮层由这里渲染，避免被 Scroll 等容器裁剪。
 */
import { sheetService, type SheetRequest } from '../../service/SheetService';
import { SelectSheet } from './SelectSheet';
import { InputSheet } from './InputSheet';
import type { SettingOption } from './SettingsTypes';

@Component
export struct SheetHost {
  @State visible: boolean = false;
  @State kind: string = 'select';
  @State title: string = '';
  @State options: SettingOption[] = [];
  @State value: string = '';
  @State placeholder: string = '';
  @State numberOnly: boolean = false;
  private pending: SheetRequest | null = null;

  aboutToAppear() {
    sheetService.register((request: SheetRequest): void => {
      this.pending = request;
      this.kind = request.kind;
      this.title = request.title;
      this.options = request.options.map((item): SettingOption => {
        const option: SettingOption = { label: item.label, value: item.value };
        return option;
      });
      this.value = request.value;
      this.placeholder = request.placeholder;
      this.numberOnly = request.numberOnly;
      this.visible = true;
    });
  }

  /** 结束当前面板：取消传空字符串 */
  private finish(result: string): void {
    const request = this.pending;
    this.pending = null;
    this.visible = false;
    if (request) {
      request.resolve(result);
    }
  }

  build() {
    if (this.kind === 'input') {
      InputSheet({
        visible: $visible,
        title: this.title,
        placeholder: this.placeholder,
        value: this.value,
        numberOnly: this.numberOnly,
        onSubmit: (text: string): void => {
          this.finish(text);
        },
        onCancel: (): void => {
          this.finish('');
        },
      })
    } else {
      SelectSheet({
        visible: $visible,
        title: this.title,
        options: this.options,
        value: this.value,
        onPick: (picked: string): void => {
          this.finish(picked);
        },
        onCancel: (): void => {
          this.finish('');
        },
      })
    }
  }
}
