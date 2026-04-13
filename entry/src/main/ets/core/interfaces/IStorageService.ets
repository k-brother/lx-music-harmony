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

/**
 * 设置存储服务实例
 */
export function setStorageService(service: IStorageService): void {
  storageServiceInstance = service;
}

/**
 * 获取存储服务实例
 */
export function getStorageService(): IStorageService {
  if (!storageServiceInstance) {
    throw new Error('StorageService not initialized');
  }
  return storageServiceInstance;
}
