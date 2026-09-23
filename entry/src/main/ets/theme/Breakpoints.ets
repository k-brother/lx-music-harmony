/**
 * 一多（响应式）布局取值
 *
 * 断点由 service/WindowService 根据窗口宽度广播到 AppStorage
 * （'breakpoint' / 'windowWidthVp'），组件用 @StorageProp 绑定即可自动适配；
 * 这里是「断点 → 具体尺寸」的纯计算出口，避免各页面各写一套数值。
 *
 * 参考 HarmonyOS 一多规范：sm < 600vp ≤ md < 840vp ≤ lg。
 */

/** 内容列最大宽度（vp）：超过后两侧留白居中，避免 PC 上单行文字横跨整屏 */
const CONTENT_MAX_WIDTH_VP = 1200;

export class Breakpoints {
  /** 宽屏（平板横屏 / PC）：播放页双栏、更多列表列数都用它判断 */
  static isWide(bp: string): boolean {
    return bp === 'md' || bp === 'lg';
  }

  /** 只看最大档（>=840vp）：设置页分两列、内容列居中用它 */
  static isLarge(bp: string): boolean {
    return bp === 'lg';
  }

  /**
   * 内容两侧留白：窗口比内容列宽时均分多余空间。
   * 直接给列表容器加这个 padding，就能在大屏上得到居中的内容列，
   * 而顶部/底部栏保持通栏（与 iPad / PC 版音乐 App 一致）。
   */
  static contentInset(windowWidthVp: number): number {
    const extra = windowWidthVp - CONTENT_MAX_WIDTH_VP;
    return extra > 0 ? Math.round(extra / 2) : 0;
  }

  /** 列表/网格的列数：按断点在「紧凑 / 中等 / 宽屏」三档里取一档 */
  static gridColumns(bp: string, compact: number, medium: number, large: number): number {
    if (bp === 'lg') {
      return large;
    }
    if (bp === 'md') {
      return medium;
    }
    return compact;
  }

  /** Grid 的 columnsTemplate（等宽列） */
  static columnsTemplate(bp: string, compact: number, medium: number, large: number): string {
    const n = Breakpoints.gridColumns(bp, compact, medium, large);
    const parts: string[] = [];
    for (let i = 0; i < n; i++) {
      parts.push('1fr');
    }
    return parts.join(' ');
  }
}
