/**
 * 「内容正在滚动」信号（底部玻璃底舱据此做材质反应）
 *
 * 为什么要一个独立工具：滚动发生在各个 Tab 视图内部，而"随滑动变化"要作用在
 * HomePage 的玻璃底舱上，两者之间没有组件引用关系。用 AppStorage 键解耦最省事：
 * 视图只管在自己的 onDidScroll 里 `markContentScrolling()`，
 * 底舱用 `@StorageProp('contentScrolling')` 读，不需要层层透传回调。
 *
 * 去抖：连续滚动期间保持 true，停手 IDLE_MS 之后复位 —— 否则停下的那一帧就要回弹，
 * 手感会一直抖。定时器是模块级的（不挂在组件上），无需随组件生命周期清理。
 */

/** AppStorage 键：内容是否正在滚动 */
export const CONTENT_SCROLLING_KEY: string = 'contentScrolling';

/** 停手多久算"滚动结束" */
const IDLE_MS: number = 320;

let idleTimer: number = -1;

/** 标记一次滚动活动（各 Tab 视图的 onDidScroll 里调用） */
export function markContentScrolling(): void {
  if (AppStorage.get<boolean>(CONTENT_SCROLLING_KEY) !== true) {
    AppStorage.setOrCreate(CONTENT_SCROLLING_KEY, true);
  }
  if (idleTimer !== -1) {
    clearTimeout(idleTimer);
  }
  idleTimer = setTimeout((): void => {
    idleTimer = -1;
    AppStorage.setOrCreate(CONTENT_SCROLLING_KEY, false);
  }, IDLE_MS);
}
