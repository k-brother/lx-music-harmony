/**
 * 设置行工厂
 *
 * 设置分组里「一行 = 标题 + 值 + 选项 + 回调」的样板重复了几十遍，
 * 每个 push 要写 12~20 行对象字面量（DesktopLyricSection 的 buildItems 一度 272 行）。
 * 这里用工厂函数把样板收成一行，分组只剩「有哪些设置项」这件事本身：
 *
 *   items.push(selectRow(t('lyric_pos_title'), this.lyricPosition, positionOptions, (value) => {...}));
 *
 * 只做数据装配，不涉及渲染（渲染仍在 SettingsSection，弹层仍在 SheetService）。
 */
import type { SettingOption, SettingSectionItem } from './SettingsTypes';

/** 按钮行的可选项 */
export interface ButtonRowOptions {
  description?: string;
  /** 危险操作（删除/清空）用危险色 */
  danger?: boolean;
}

/** 单选项行 */
export function selectRow(
  title: string, value: string, options: SettingOption[],
  onChange: (value: string) => void, description?: string
): SettingSectionItem {
  return {
    type: 'select',
    title: title,
    description: description,
    value: value,
    options: options,
    onChange: onChange,
  };
}

/** 开关行 */
export function toggleRow(
  title: string, value: boolean,
  onChangeToggle: (value: boolean) => void, description?: string
): SettingSectionItem {
  return {
    type: 'toggle',
    title: title,
    description: description,
    value: value,
    onChangeToggle: onChangeToggle,
  };
}

/** 可点击的动作行（右侧箭头） */
export function buttonRow(title: string, onClick: () => void, options?: ButtonRowOptions): SettingSectionItem {
  return {
    type: 'button',
    title: title,
    description: options?.description,
    danger: options?.danger === true,
    onClick: onClick,
  };
}

/** 输入行（点开后弹出输入面板） */
export function inputRow(
  title: string, value: string, onChange: (value: string) => void, description?: string
): SettingSectionItem {
  return {
    type: 'input',
    title: title,
    description: description,
    value: value,
    onChange: onChange,
  };
}

/** 只读信息行（同步状态、当前模式说明等） */
export function infoRow(title: string, value: string, description?: string): SettingSectionItem {
  return {
    type: 'info',
    title: title,
    description: description,
    value: value,
  };
}
