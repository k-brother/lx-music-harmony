/**
 * 缓存管理服务
 *
 * 把缓存分成两类管理（对齐安卓版的「元数据缓存 / 资源缓存」）：
 * - 元数据缓存：歌曲链接、歌词等以字符串形式存在 Preferences 里的缓存
 * - 资源缓存：封面等下载到磁盘的图片文件（ImageCache 管理）
 *
 * 元数据缓存通过"键登记表"维护：写入缓存时登记键名与大小，
 * 这样统计大小是 O(1)，清理时也能精确删掉这些键而不影响用户数据。
 */
import hilog from '@ohos.hilog';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { getStorageService } from '../core/interfaces/IStorageService';
import { imageCacheService } from '../utils/ImageCache';
import { formatBytes } from '../utils/FormatTools';
import { clearHistoryList } from '../core/search/search';
import { clearPlayHistory } from './PlayHistoryService';

const TAG = 'CacheService';
const DOMAIN = 0x0005;
const KEYS_STORAGE_KEY = 'cache.metadata.keys';
/** 登记表上限，防止极端情况下无限增长（超出后按最久未更新淘汰） */
const MAX_TRACKED_KEYS = 1500;

/** 缓存统计信息 */
export interface CacheInfo {
  count: number;
  /** 估算字节数 */
  bytes: number;
}

/** 元数据缓存登记项：key + 估算字节数 */
interface TrackedCacheEntry {
  key: string;
  bytes: number;
}

/** 字节数格式化为可读文本（规则统一在 utils/FormatTools：B / KB / MB / GB） */
export function formatCacheSize(bytes: number): string {
  return formatBytes(bytes);
}

class CacheServiceImpl {
  /** key -> 估算字节数，Map 保证 O(1) 更新且能精确扣除被覆盖写入的旧值 */
  private entries: Map<string, number> = new Map();
  private trackedSize: number = 0;
  private loaded: boolean = false;

  private async ensureLoaded(): Promise<void> {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      const storage = getStorageService();
      const raw = await storage.getString(KEYS_STORAGE_KEY, '');
      if (raw.length > 0) {
        const list = JSON.parse(raw) as TrackedCacheEntry[];
        for (let i = 0; i < list.length; i++) {
          const item = list[i];
          if (item && typeof item.key === 'string' && item.key.length > 0) {
            this.entries.set(item.key, typeof item.bytes === 'number' ? item.bytes : 0);
          }
        }
      }
      this.recalcSize();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'load cache registry failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      this.entries.clear();
      this.trackedSize = 0;
    }
  }

  /** 登记一个元数据缓存键（由缓存写入方调用） */
  async trackMetadataKey(key: string, valueLength: number): Promise<void> {
    await this.ensureLoaded();
    if (key.length === 0) {
      return;
    }
    // 用 UTF-16 估算：每个字符约 2 字节
    const bytes = Math.max(0, valueLength) * 2;
    const previous = this.entries.get(key);
    if (previous !== undefined) {
      this.trackedSize = Math.max(0, this.trackedSize - previous);
    }
    // 覆盖写入：先删后插，保持 Map 的插入顺序即"最近更新顺序"
    this.entries.delete(key);
    this.entries.set(key, bytes);
    this.trackedSize += bytes;
    // 超出上限时淘汰最久未更新的记录（只影响统计，不影响实际缓存读写）
    while (this.entries.size > MAX_TRACKED_KEYS) {
      const oldest = this.entries.keys().next().value as string | undefined;
      if (oldest === undefined) {
        break;
      }
      const oldestBytes = this.entries.get(oldest) ?? 0;
      this.entries.delete(oldest);
      this.trackedSize = Math.max(0, this.trackedSize - oldestBytes);
    }
    await this.persistRegistry();
  }

  /** 元数据缓存统计 */
  async getMetadataCacheInfo(): Promise<CacheInfo> {
    await this.ensureLoaded();
    return { count: this.entries.size, bytes: this.trackedSize };
  }

  /** 取消登记（缓存条目被主动删除时调用，避免统计虚高） */
  async untrackMetadataKey(key: string): Promise<void> {
    await this.ensureLoaded();
    const previous = this.entries.get(key);
    if (previous === undefined) {
      return;
    }
    this.entries.delete(key);
    this.trackedSize = Math.max(0, this.trackedSize - previous);
    await this.persistRegistry();
  }

  /** 资源缓存统计（图片文件） */
  getResourceCacheInfo(): CacheInfo {
    return { count: imageCacheService.getEntryCount(), bytes: imageCacheService.getSizeBytes() };
  }

  /** 全部缓存统计 */
  async getAllCacheInfo(): Promise<CacheInfo> {
    const meta = await this.getMetadataCacheInfo();
    const resource = this.getResourceCacheInfo();
    return { count: meta.count + resource.count, bytes: meta.bytes + resource.bytes };
  }

  /** 清理元数据缓存 */
  async clearMetadataCache(): Promise<void> {
    await this.ensureLoaded();
    const storage = getStorageService();
    const keys: string[] = [];
    this.entries.forEach((_value: number, key: string) => {
      keys.push(key);
    });
    for (let i = 0; i < keys.length; i++) {
      try {
        await storage.remove(keys[i]);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'remove cache key failed: %{public}s', keys[i]);
      }
    }
    this.entries.clear();
    this.trackedSize = 0;
    await this.persistRegistry();
    hilog.info(DOMAIN, TAG, 'Metadata cache cleared: %{public}d keys', keys.length);
  }

  /** 清理资源缓存（封面等图片） */
  async clearResourceCache(): Promise<void> {
    await imageCacheService.clear();
    hilog.info(DOMAIN, TAG, 'Resource cache cleared');
  }

  /**
   * 一键清理（设置页「清除缓存」）：
   * 元数据缓存 + 资源缓存 + 历史遗留的图片/临时目录 + 搜索历史 + 播放历史
   *
   * 这类"清理哪些东西"的规则属于服务层职责，页面只负责确认与提示，
   * 避免每个入口各写一遍容易漏项。
   * @returns 清理的条目数（用于提示语）
   */
  async clearEverything(context: common.UIAbilityContext): Promise<number> {
    let clearedItems = 0;
    const before = await this.getAllCacheInfo();
    await this.clearAll();
    clearedItems += before.count;

    clearedItems += await this.clearDirectory(`${context.cacheDir}/images`);
    clearedItems += await this.clearDirectory(`${context.tempDir}`);

    try {
      await clearHistoryList();
      clearedItems++;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clear search history failed: %{public}s', JSON.stringify(err));
    }
    try {
      await clearPlayHistory();
      clearedItems++;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clear play history failed: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, TAG, 'Everything cleared: %{public}d items', clearedItems);
    return clearedItems;
  }

  /** 递归清空目录内容，返回删除的文件数（目录不存在时返回 0） */
  async clearDirectory(dirPath: string): Promise<number> {
    let clearedCount = 0;
    try {
      fs.accessSync(dirPath);
      const entries: string[] = fs.listFileSync(dirPath);
      for (let i = 0; i < entries.length; i++) {
        const name = entries[i];
        const fullPath = `${dirPath}/${name}`;
        const stat = fs.statSync(fullPath);
        if (stat.isFile()) {
          fs.unlinkSync(fullPath);
          clearedCount++;
        } else if (stat.isDirectory()) {
          clearedCount += await this.clearDirectory(fullPath);
          fs.rmdirSync(fullPath);
        }
      }
    } catch (err) {
      // 目录不存在或不可访问：忽略
    }
    return clearedCount;
  }

  /** 清理全部缓存 */
  async clearAll(): Promise<void> {
    await this.clearMetadataCache();
    await this.clearResourceCache();
  }

  private async persistRegistry(): Promise<void> {
    try {
      const storage = getStorageService();
      const list: TrackedCacheEntry[] = [];
      this.entries.forEach((bytes: number, key: string) => {
        list.push({ key, bytes });
      });
      await storage.setString(KEYS_STORAGE_KEY, JSON.stringify(list));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'persist cache registry failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
    }
  }

  private recalcSize(): void {
    let total = 0;
    this.entries.forEach((bytes: number) => {
      total += bytes;
    });
    this.trackedSize = total;
  }
}

export const cacheService = new CacheServiceImpl();
export default cacheService;
