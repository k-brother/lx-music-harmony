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

/**
 * 秒 → `mm:ss`，非法/非正值返回 `00:00`。
 * 与 formatDuration 的区别：列表列用「--:--」表示未知，而接口/播放场景需要 `00:00`。
 */
export function formatClock(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return '00:00';
  }
  const total = Math.floor(seconds);
  const minute = Math.floor(total / 60);
  const second = total % 60;
  const pad = (value: number): string => (value < 10 ? `0${value}` : `${value}`);
  return `${pad(minute)}:${pad(second)}`;
}

/** 秒 → 超过 1 小时给 `hh:mm:ss`，否则 `mm:ss`（播放页/播控显示用） */
export function formatClockWithHours(seconds: number): string {
  if (!Number.isFinite(seconds) || seconds < 0) {
    return '00:00';
  }
  const total = Math.floor(seconds);
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const secs = total % 60;
  const pad = (value: number): string => (value < 10 ? `0${value}` : `${value}`);
  if (hours > 0) {
    return `${pad(hours)}:${pad(minutes)}:${pad(secs)}`;
  }
  return `${pad(minutes)}:${pad(secs)}`;
}

/**
 * `mm:ss` / `hh:mm:ss` → 秒（从后往前按 60 进位，容忍多余空格与空段）。
 * 之前 utils/CommonUtils、core/music/MusicParsingUtils、core/list/SongMappers 各有一份等价实现。
 */
export function parsePlayTimeText(text: string | null | undefined): number {
  if (!text || text.length === 0) {
    return 0;
  }
  const parts = text.split(':');
  let seconds = 0;
  let unit = 1;
  for (let i = parts.length - 1; i >= 0; i--) {
    const value = parseInt(parts[i].trim(), 10);
    if (!isNaN(value)) {
      seconds += value * unit;
    }
    unit *= 60;
  }
  return seconds;
}

/**
 * 播放量/播放次数：`8550` / `5.5 万` / `1.2 亿`
 *
 * 之前这段逻辑在排行榜卡片、歌单卡片、歌单详情、搜索结果里各写了一遍，
 * 阈值、空格、小数位都不同（真机截图里出现过 `8550.7` 这种带小数的播放量）。
 * 单位文案由调用方传入，保持本模块是纯函数、不依赖 i18n。
 */
export function formatPlayCount(
  count: number, tenThousandUnit: string, billionUnit: string): string {
  if (!Number.isFinite(count) || count <= 0) {
    return '0';
  }
  if (count >= 100000000) {
    return `${(count / 100000000).toFixed(1)} ${billionUnit}`;
  }
  if (count >= 10000) {
    return `${(count / 10000).toFixed(1)} ${tenThousandUnit}`;
  }
  // 一万以下直接取整：接口偶尔给出小数（如 8550.7），展示成整数才自然
  return `${Math.round(count)}`;
}
