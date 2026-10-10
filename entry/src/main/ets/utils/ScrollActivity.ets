/**
 * 首页滚动信号（底部玻璃底舱据此做材质反应与"收拢"联动）
 *
 * 为什么要一个独立工具：滚动发生在各个 Tab 视图内部，而"随滑动变化"要作用在
 * HomePage 的玻璃底舱上，两者之间没有组件引用关系。用 AppStorage 键解耦最省事：
 * 视图只管在自己的 onDidScroll 里上报，底舱用 @StorageProp 读，不需要层层透传回调。
 *
 * 两组信号：
 * 1. `contentScrolling`：**正在滚动**（去抖）。连续滚动期间保持 true，停手 IDLE_MS 后复位 ——
 *    底舱据此轻微收放（材质跟着滑动"呼吸"）；
 * 2. `contentScrolledAway`：**已滚离顶部**（带迟滞）。滚过阈值就保持 true，滚回顶部附近才复位 ——
 *    底舱据此收成一条迷你条（左侧"回到顶部" + 播放控件），对齐华为音乐滚动后的形态。
 *    迟滞是为了避免停在阈值上反复抖动。
 *
 * 定时器是模块级的（不挂在组件上），无需随组件生命周期清理。
 */

/** AppStorage 键：内容是否正在滚动（去抖） */
export const CONTENT_SCROLLING_KEY: string = 'contentScrolling';
/** AppStorage 键：内容是否已滚离顶部（底舱据此收拢） */
export const CONTENT_SCROLLED_AWAY_KEY: string = 'contentScrolledAway';
/** AppStorage 键：请求把当前列表滚回顶部（底舱左键触发） */
export const SCROLL_TOP_REQUEST_KEY: string = 'scrollTopRequest';

/** 停手多久算"滚动结束" */
const IDLE_MS: number = 320;
/** 滚过这么多就算"滚离顶部" */
const AWAY_ON_VP: number = 28;
/** 滚回到这个范围内算"回到顶部"（迟滞下沿） */
const AWAY_OFF_VP: number = 12;

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

/**
 * 上报当前绝对滚动位移（vp）：各 Tab 视图在 onDidScroll 里带自己的 scroller 偏移调用。
 * 只有跨过阈值时才写 AppStorage，避免每帧都触发底舱重绘。
 */
export function reportScrollOffset(offset: number): void {
  const away: boolean = AppStorage.get<boolean>(CONTENT_SCROLLED_AWAY_KEY) === true;
  if (!away && offset > AWAY_ON_VP) {
    AppStorage.setOrCreate(CONTENT_SCROLLED_AWAY_KEY, true);
  } else if (away && offset < AWAY_OFF_VP) {
    AppStorage.setOrCreate(CONTENT_SCROLLED_AWAY_KEY, false);
  }
}

/** 复位"滚离顶部"（切 Tab 时调：新列表默认在顶部，底舱应展开） */
export function resetScrollAway(): void {
  if (AppStorage.get<boolean>(CONTENT_SCROLLED_AWAY_KEY) === true) {
    AppStorage.setOrCreate(CONTENT_SCROLLED_AWAY_KEY, false);
  }
}

/**
 * 请求把当前列表滚回顶部（底舱左键用）。
 * 用"递增的请求号"广播：当前挂载的那个 Tab 视图监听到变化就去滚自己的 scroller，
 * 不需要 HomePage 持有各视图的 scroller 引用。
 */
export function requestScrollToTop(): void {
  const current: number = AppStorage.get<number>(SCROLL_TOP_REQUEST_KEY) ?? 0;
  AppStorage.setOrCreate(SCROLL_TOP_REQUEST_KEY, current + 1);
}
