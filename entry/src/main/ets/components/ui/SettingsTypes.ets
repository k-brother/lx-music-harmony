/**
 * 设置项数据结构（所有设置分组共用）
 *
 * 之所以独立成文件：设置页由「渲染器 + 若干分组组件」组成，
 * 类型必须被多方共享，放在页面里会造成循环依赖。
 */

/** 单选/多选项 */
export interface SettingOption {
  label: string;
  value: string;
}

/**
 * 选项值 → 展示文案。
 *
 * 设置分组里「已选中值要显示成哪个 label」原先在三个分组各写了一遍；
 * 找不到时回退成原值，避免出现空白行。
 */
export function labelOfOption(options: SettingOption[], value: string): string {
  for (let i = 0; i < options.length; i++) {
    if (options[i].value === value) {
      return options[i].label;
    }
  }
  return value;
}

/** 设置行类型 */
export type SettingItemType = 'toggle' | 'select' | 'button' | 'input' | 'info';

/** 设置行 */
export interface SettingSectionItem {
  type: SettingItemType;
  title: string;
  description?: string;
  value?: string | boolean;
  options?: SettingOption[];
  /** select / input 的值变更回调 */
  onChange?: (value: string) => void;
  onChangeToggle?: (value: boolean) => void;
  /** button 行点击 */
  onClick?: () => void;
  /** 危险行（删除/清空），文字与图标用危险色 */
  danger?: boolean;
}
