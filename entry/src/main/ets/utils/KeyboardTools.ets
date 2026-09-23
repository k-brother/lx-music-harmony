/**
 * 2in1（PC / 平板接键盘）的键盘操作小工具
 *
 * 触屏之外的第二套输入：列表行、卡片这些「自定义可点区域」默认不可聚焦，
 * 接上键盘后完全没法用。统一做法是给元素加 `.focusable(true)` + `.onKeyEvent(...)`，
 * 这里只提供判定逻辑，避免每个组件各写一遍三个键码的比较。
 */
import { KeyCode } from '@kit.InputKit';

/** 是否是「确认」键（回车 / 小键盘回车 / 空格），且是按下事件 */
export function isConfirmKey(event: KeyEvent): boolean {
  if (event.type !== KeyType.Down) {
    return false;
  }
  const code: number = event.keyCode;
  return code === KeyCode.KEYCODE_ENTER
    || code === KeyCode.KEYCODE_NUMPAD_ENTER
    || code === KeyCode.KEYCODE_SPACE;
}
