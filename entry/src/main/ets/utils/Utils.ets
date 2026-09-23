/**
 * 通用小工具
 *
 * 这里只保留真正被多处复用的实现；数组/判空/深拷贝等已收敛到
 * utils/CommonUtils，时长格式化统一在 utils/FormatTools。
 */

// 生成随机 ID
export function generateId(): string {
  return Date.now().toString(36) + Math.random().toString(36).substring(2);
}

/** 等待若干毫秒（轮询/退避等场景共用一份实现） */
export function delayMs(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, ms);
  });
}
