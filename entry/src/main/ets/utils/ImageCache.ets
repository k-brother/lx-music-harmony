import hilog from '@ohos.hilog';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import type { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN: number = 0x0002;
const TAG: string = 'ImageCache';

// 缓存配置
const MAX_CACHE_SIZE = 100 * 1024 * 1024; // 100MB
const CACHE_EXPIRY_MS = 7 * 24 * 60 * 60 * 1000; // 7天

interface CacheEntry {
  url: string;
  path: string;
  size: number;
  timestamp: number;
}

class ImageCacheService {
  private cacheDir: string = '';
  private indexFile: string = '';
  private cacheIndex: Map<string, CacheEntry> = new Map();
  private totalSize: number = 0;
  private context: common.UIAbilityContext | null = null;

  async init(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    const cachePath = context.cacheDir;
    this.cacheDir = `${cachePath}/image_cache`;
    this.indexFile = `${this.cacheDir}/index.json`;

    try {
      // 确保缓存目录存在（HarmonyOS fs.mkdir 不支持 recursive 参数）
      await this.ensureDirExists(this.cacheDir);
      await this.loadIndex();
      await this.cleanup();
      hilog.info(DOMAIN, TAG, 'ImageCache initialized at %{public}s', this.cacheDir);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to init ImageCache: %{public}s, path: %{public}s',
        JSON.stringify(err), this.cacheDir);
    }
  }

  private async loadIndex(): Promise<void> {
    try {
      if (await this.fileExists(this.indexFile)) {
        const file = await fs.open(this.indexFile, fs.OpenMode.READ_ONLY);
        const stat = await fs.stat(file.fd);
        const buffer = new ArrayBuffer(stat.size);
        await fs.read(file.fd, buffer);
        const textDecoder = util.TextDecoder.create('utf-8');
        const data: string = textDecoder.decodeToString(new Uint8Array(buffer));
        const entries = JSON.parse(data) as CacheEntry[];
        
        this.cacheIndex.clear();
        this.totalSize = 0;
        for (const entry of entries) {
          this.cacheIndex.set(entry.url, entry);
          this.totalSize += entry.size;
        }
        await fs.close(file.fd);
      }
    } catch (err) {
      const code: number = (err as BusinessError)?.code ?? 0;
      // 13900002 = 文件不存在：首次启动或缓存被清理，属于正常情况
      if (code === 13900002) {
        hilog.info(DOMAIN, TAG, 'No cache index yet (first launch), starting empty');
      } else {
        hilog.warn(DOMAIN, TAG, 'Failed to load cache index: %{public}s', JSON.stringify(err));
      }
    }
  }

  private async saveIndex(): Promise<void> {
    try {
      const entries = Array.from(this.cacheIndex.values());
      const textEncoder = new util.TextEncoder();
      const data: Uint8Array = textEncoder.encodeInto(JSON.stringify(entries));
      const file = await fs.open(this.indexFile, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, data.buffer);
      await fs.fsync(file.fd);
      await fs.close(file.fd);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save cache index: %{public}s', JSON.stringify(err));
    }
  }

  async get(url: string): Promise<string | null> {
    const entry = this.cacheIndex.get(url);
    if (!entry) return null;

    // 检查文件是否存在
    if (!(await this.fileExists(entry.path))) {
      this.cacheIndex.delete(url);
      this.totalSize -= entry.size;
      void this.saveIndex();
      return null;
    }

    // 检查是否过期
    if (Date.now() - entry.timestamp > CACHE_EXPIRY_MS) {
      await this.removeEntry(url);
      return null;
    }

    return entry.path;
  }

  async put(url: string, data: Uint8Array): Promise<string> {
    const fileName = this.hashUrl(url);
    const filePath = `${this.cacheDir}/${fileName}`;

    // 写入文件
    let file: fs.File;
    let size: number;
    try {
      file = await fs.open(filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, data.buffer);
      await fs.fsync(file.fd);
      await fs.close(file.fd);

      const stat = await fs.stat(filePath);
      size = stat.size;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, 'Failed to write cache file: %{public}s', msg);
      throw new Error(msg);
    }

    // 更新索引
    if (this.cacheIndex.has(url)) {
      this.totalSize -= this.cacheIndex.get(url)!.size;
    }

    const entry: CacheEntry = {
      url,
      path: filePath,
      size,
      timestamp: Date.now()
    };

    this.cacheIndex.set(url, entry);
    this.totalSize += size;

    await this.saveIndex();
    await this.cleanup();

    return filePath;
  }

  private async removeEntry(url: string): Promise<void> {
    const entry = this.cacheIndex.get(url);
    if (entry) {
      try {
        if (await this.fileExists(entry.path)) {
          await fs.unlink(entry.path);
        }
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'Failed to delete cache file: %{public}s', JSON.stringify(err));
      }
      this.totalSize -= entry.size;
      this.cacheIndex.delete(url);
      await this.saveIndex();
    }
  }

  private async cleanup(): Promise<void> {
    // 如果超过最大容量，删除最旧的缓存
    if (this.totalSize > MAX_CACHE_SIZE) {
      const sortedEntries = Array.from(this.cacheIndex.values()).sort((a, b) => a.timestamp - b.timestamp);
      let currentSize = this.totalSize;
      
      for (const entry of sortedEntries) {
        if (currentSize <= MAX_CACHE_SIZE * 0.8) break; // 清理到 80%
        await this.removeEntry(entry.url);
        currentSize -= entry.size;
      }
    }
  }

  private hashUrl(url: string): string {
    // 简单的哈希实现，实际项目中可以使用 crypto 模块
    let hash = 0;
    for (let i = 0; i < url.length; i++) {
      const char = url.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32bit integer
    }
    return Math.abs(hash).toString(16) + '.jpg';
  }

  private async fileExists(path: string): Promise<boolean> {
    try {
      await fs.access(path);
      return true;
    } catch (err) {
      return false;
    }
  }

  /** 当前索引中的缓存条目数量（供缓存管理页展示） */
  getEntryCount(): number {
    return this.cacheIndex.size;
  }

  /** 当前缓存占用字节数（供缓存管理页展示） */
  getSizeBytes(): number {
    return this.totalSize;
  }

  // 逐层创建目录（HarmonyOS fs.mkdir 无 recursive 参数）
  private async ensureDirExists(dirPath: string): Promise<void> {
    if (await this.fileExists(dirPath)) {
      return;
    }
    // 先确保父目录存在
    const parentPath = dirPath.substring(0, dirPath.lastIndexOf('/'));
    if (parentPath && !(await this.fileExists(parentPath))) {
      await this.ensureDirExists(parentPath);
    }
    try {
      await fs.mkdir(dirPath);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to create directory: %{public}s', JSON.stringify(err));
    }
  }

  async clear(): Promise<void> {
    try {
      const files = fs.listFileSync(this.cacheDir);
      for (const file of files) {
        if (file !== 'index.json') {
          await fs.unlink(`${this.cacheDir}/${file}`);
        }
      }
      this.cacheIndex.clear();
      this.totalSize = 0;
      await this.saveIndex();
      hilog.info(DOMAIN, TAG, 'ImageCache cleared');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to clear cache: %{public}s', JSON.stringify(err));
    }
  }
}

export const imageCacheService = new ImageCacheService();
