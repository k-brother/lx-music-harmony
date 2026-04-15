/**
 * 存储服务接口定义
 * core层通过此接口访问存储功能，避免直接依赖service层
 */

/**
 * 存储服务接口
 */
export interface IStorageService {
  getString(key: string, defaultValue?: string): Promise<string>;
  getNumber(key: string, defaultValue?: number): Promise<number>;
  getBoolean(key: string, defaultValue?: boolean): Promise<boolean>;
  setString(key: string, value: string): Promise<void>;
  setNumber(key: string, value: number): Promise<void>;
  setBoolean(key: string, value: boolean): Promise<void>;
  remove(key: string): Promise<void>;
  clear(): Promise<void>;
  has(key: string): Promise<boolean>;
}

/**
 * 默认存储服务实例（由service层在初始化时注入）
 */
let storageServiceInstance: IStorageService | null = null;

/** Preferences 未就绪时（预览器、initStorage 失败）用内存实现，避免播放入口抛错 */
class MemoryStorageService implements IStorageService {
  private readonly store: Map<string, string> = new Map();

  async getString(key: string, defaultValue: string = ''): Promise<string> {
    const v = this.store.get(key);
    return v !== undefined ? v : defaultValue;
  }

  async getNumber(key: string, defaultValue: number = 0): Promise<number> {
    const s = await this.getString(key, '');
    if (s.length === 0) {
      return defaultValue;
    }
    const n = parseFloat(s);
    return isNaN(n) ? defaultValue : n;
  }

  async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    const s = await this.getString(key, '');
    if (s.length === 0) {
      return defaultValue;
    }
    return s === '1' || s === 'true';
  }

  async setString(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }

  async setNumber(key: string, value: number): Promise<void> {
    this.store.set(key, String(value));
  }

  async setBoolean(key: string, value: boolean): Promise<void> {
    this.store.set(key, value ? '1' : '0');
  }

  async remove(key: string): Promise<void> {
    this.store.delete(key);
  }

  async clear(): Promise<void> {
    this.store.clear();
  }

  async has(key: string): Promise<boolean> {
    return this.store.has(key);
  }
}

let memoryStorageFallback: IStorageService | null = null;

/** 供 initStorage 失败时显式注入，与 getStorageService 懒加载实例一致 */
export function createMemoryStorageService(): IStorageService {
  return new MemoryStorageService();
}

/**
 * 设置存储服务实例
 */
export function setStorageService(service: IStorageService): void {
  storageServiceInstance = service;
}

/**
 * 获取存储服务实例（未注入时回退内存实现，不抛错）
 */
export function getStorageService(): IStorageService {
  if (storageServiceInstance) {
    return storageServiceInstance;
  }
  if (!memoryStorageFallback) {
    memoryStorageFallback = new MemoryStorageService();
  }
  return memoryStorageFallback;
}
