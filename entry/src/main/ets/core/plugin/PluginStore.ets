/**
 * 自定义源（用户 JS 源）持久化仓库
 *
 * 对齐安卓版的「userApi 列表」：可以导入多个源、逐个启用/停用、更新、删除。
 * 脚本正文一并存下来（安卓版同样保存脚本），这样重启后离线也能直接激活，
 * 不需要每次启动都去下载。
 */
import { getStorageService } from '../interfaces/IStorageService';

const STORAGE_KEY = 'plugin.customSources';
/** 旧版本只存了单个源的 URL，迁移用 */
const LEGACY_URL_KEY = 'plugin.customSourceUrl';
const LEGACY_CURRENT_KEY = 'plugin.currentSource';

/** 已保存的自定义源 */
export interface StoredCustomSource {
  /** 插件 id（custom_<时间戳>） */
  id: string;
  /** 来源（在线链接或本地文件 URI） */
  url: string;
  name: string;
  version: string;
  author: string;
  description: string;
  homepage: string;
  /** 脚本正文，离线可用 */
  script: string;
  /** 是否启用（同一时间只允许一个自定义源处于启用状态） */
  enabled: boolean;
  addedAt: number;
  updatedAt: number;
}

/** 读取全部自定义源 */
export async function loadStoredSources(): Promise<StoredCustomSource[]> {
  const storage = getStorageService();
  const raw = await storage.getString(STORAGE_KEY, '');
  let list: StoredCustomSource[] = [];
  if (raw.length > 0) {
    try {
      const parsed = JSON.parse(raw) as StoredCustomSource[];
      if (Array.isArray(parsed)) {
        list = parsed.filter((item: StoredCustomSource) => !!item && typeof item.id === 'string');
      }
    } catch (err) {
      list = [];
    }
  }
  return await migrateLegacySingleSource(list);
}

/** 保存全部自定义源 */
export async function saveStoredSources(list: StoredCustomSource[]): Promise<void> {
  await getStorageService().setString(STORAGE_KEY, JSON.stringify(list));
}

/**
 * 旧数据迁移：老版本只在 `plugin.customSourceUrl` 里存了一个地址，
 * 若新列表为空且存在旧地址，就转成一条记录（脚本留空，首次启动会按需重新下载）
 */
async function migrateLegacySingleSource(list: StoredCustomSource[]): Promise<StoredCustomSource[]> {
  if (list.length > 0) {
    return list;
  }
  const storage = getStorageService();
  const legacyUrl = await storage.getString(LEGACY_URL_KEY, '');
  if (legacyUrl.length === 0) {
    return list;
  }
  const currentSource = await storage.getString(LEGACY_CURRENT_KEY, '');
  const migrated: StoredCustomSource = {
    id: `custom_legacy_${Date.now()}`,
    url: legacyUrl,
    name: legacyUrl,
    version: '',
    author: '',
    description: '',
    homepage: '',
    script: '',
    enabled: currentSource === 'custom',
    addedAt: Date.now(),
    updatedAt: Date.now(),
  };
  await saveStoredSources([migrated]);
  return [migrated];
}

/** 新增或覆盖一条记录（按 id 匹配） */
export async function upsertStoredSource(record: StoredCustomSource): Promise<StoredCustomSource[]> {
  const list = await loadStoredSources();
  const index = list.findIndex((item: StoredCustomSource) => item.id === record.id);
  if (index >= 0) {
    list[index] = record;
  } else {
    list.push(record);
  }
  await saveStoredSources(list);
  return list;
}

/** 删除一条记录 */
export async function removeStoredSource(id: string): Promise<StoredCustomSource[]> {
  const list = await loadStoredSources();
  const next = list.filter((item: StoredCustomSource) => item.id !== id);
  await saveStoredSources(next);
  return next;
}

/** 只允许一个源处于启用状态；传入 id 为 null 表示全部停用 */
export async function setEnabledSource(id: string | null): Promise<StoredCustomSource[]> {
  const list = await loadStoredSources();
  for (let i = 0; i < list.length; i++) {
    list[i].enabled = id !== null && list[i].id === id;
  }
  await saveStoredSources(list);
  return list;
}

/** 取当前启用的源（没有则返回 null） */
export function findEnabledSource(list: StoredCustomSource[]): StoredCustomSource | null {
  for (let i = 0; i < list.length; i++) {
    if (list[i].enabled) {
      return list[i];
    }
  }
  return null;
}
