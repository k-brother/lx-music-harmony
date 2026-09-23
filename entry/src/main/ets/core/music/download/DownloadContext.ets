/**
 * 下载域的 UIAbilityContext 持有者
 *
 * 文件层（写公共目录）与队列层都要用上下文；单独一个小模块避免两层互相依赖。
 */
import type { common } from '@kit.AbilityKit';

let downloadContext: common.UIAbilityContext | null = null;

export function setDownloadContext(context: common.UIAbilityContext): void {
  downloadContext = context;
}

export function getDownloadContext(): common.UIAbilityContext | null {
  return downloadContext;
}

/** 取上下文，未初始化直接抛错（下载必须先由页面 setDownloadContext） */
export function requireDownloadContext(): common.UIAbilityContext {
  if (!downloadContext) {
    throw new Error('Download context not initialized. Call setDownloadContext first.');
  }
  return downloadContext;
}
