/**
 * 滚动位置工具
 *
 * 歌单详情、榜单详情等页面都要「读当前滚动偏移」做顶栏收缩/位置记忆，
 * 实现（含 currentOffset 抛异常的兜底）此前在两个页面各写了一份。
 */

/**
 * 读取列表当前纵向偏移；Scroller 尚未绑定或取不到值时返回 0。
 */
export function scrollerOffsetY(scroller: Scroller): number {
  try {
    const y = scroller.currentOffset().yOffset;
    if (typeof y === 'number' && isFinite(y)) {
      return y;
    }
    return 0;
  } catch (_e) {
    return 0;
  }
}

/**
 * 让列表平滑回到顶部；列表尚未绑定 Scroller 时静默忽略。
 */
export function scrollToTop(scroller: Scroller, animated: boolean = true): void {
  try {
    scroller.scrollTo({ xOffset: 0, yOffset: 0, animation: animated });
  } catch (_e) {
    // 列表还没挂载，忽略
  }
}

/**
 * 「稍后回到顶部」的延迟器。
 *
 * 切换音乐源/筛选条件时列表内容会整批重建，立刻 scrollTo 会被这一帧的
 * 布局覆盖掉，所以要等一帧；同时要保证页面已销毁时不再触发。
 * 歌单页与排行榜页此前各写了一份完全相同的实现（含 alive 标志与定时器清理）。
 */
export class DeferredScrollToTop {
  private timer: number = -1;
  private alive: boolean = false;

  /** 页面 aboutToAppear 调用 */
  start(): void {
    this.alive = true;
  }

  /** 页面 aboutToDisappear 调用：取消待执行的滚动 */
  stop(): void {
    this.alive = false;
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }

  /** 安排一次滚动（重复调用只保留最后一次） */
  schedule(scroller: Scroller): void {
    if (!this.alive) {
      return;
    }
    if (this.timer >= 0) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
    this.timer = setTimeout((): void => {
      if (!this.alive) {
        return;
      }
      scrollToTop(scroller, false);
      this.timer = -1;
    }, 0);
  }
}
