/**
 * 通用格式化工具（字节大小 / 时长）
 *
 * 之前同一件事有 4 份实现且输出格式各不相同：
 *   - `core/music/local/LocalPlayback.formatFileSize`（B/KB/MB/GB，2 位小数）
 *   - `utils/CommonUtils.sizeFormate`（1.5MB 这种紧凑写法，无空格）
 *   - `service/CacheService.formatCacheSize`（只到 MB）
 *   - `pages/DownloadPage.formatFileSize`（数组 + Math.pow 版本）
 * 现在统一到这里，调用方只选「可读（带空格）」或「紧凑（无空格）」两种形态。
 */

const UNIT_STEP = 1024;

/**
 * 可读字节数：`0 B` / `512 B` / `48.00 KB` / `2.60 MB` / `1.20 GB`
 * decimals 只作用于 KB 及以上，B 永远是整数。
 */
export function formatBytes(bytes: number, decimals: number = 2): string {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '0 B';
  }
  if (bytes < UNIT_STEP) {
    return `${Math.floor(bytes)} B`;
  }
  if (bytes < UNIT_STEP * UNIT_STEP) {
    return `${(bytes / UNIT_STEP).toFixed(decimals)} KB`;
  }
  if (bytes < UNIT_STEP * UNIT_STEP * UNIT_STEP) {
    return `${(bytes / (UNIT_STEP * UNIT_STEP)).toFixed(decimals)} MB`;
  }
  return `${(bytes / (UNIT_STEP * UNIT_STEP * UNIT_STEP)).toFixed(decimals)} GB`;
}

/** 紧凑字节数（无空格）：`512B` / `1.5KB` / `3.2MB`，音源接口里的文件大小多用这种 */
export function formatBytesCompact(bytes: number, decimals: number = 1): string {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '0B';
  }
  if (bytes < UNIT_STEP) {
    return `${Math.floor(bytes)}B`;
  }
  if (bytes < UNIT_STEP * UNIT_STEP) {
    return `${(bytes / UNIT_STEP).toFixed(decimals)}KB`;
  }
  if (bytes < UNIT_STEP * UNIT_STEP * UNIT_STEP) {
    return `${(bytes / (UNIT_STEP * UNIT_STEP)).toFixed(decimals)}MB`;
  }
  return `${(bytes / (UNIT_STEP * UNIT_STEP * UNIT_STEP)).toFixed(2)}GB`;
}

/** 秒 → `mm:ss`，非法值返回 `--:--`（列表时长列统一用这个） */
export function formatDuration(seconds: number): string {
  if (!seconds || seconds <= 0) {
    return '--:--';
  }
  const total = Math.floor(seconds);
  const minute = Math.floor(total / 60);
  const second = total % 60;
  const pad = (value: number): string => (value < 10 ? `0${value}` : `${value}`);
  return `${pad(minute)}:${pad(second)}`;
}
