/**
 * 应用级存储文件名（中立常量，UI 进程与卡片进程共用）
 *
 * 为什么放 utils 而不是 service：卡片扩展（FormExtensionAbility）跑在独立进程，
 * 不该也不能 import `service/StorageService` 那套单例 + context 依赖；
 * 两边只共享"文件名"这一个常量即可。
 *
 * 定义权归基础设施：`service/StorageService` 从这里取值对外导出，
 * 功能模块（卡片 / 实况窗）只引用，不再自己声明应用级常量。
 */
export const APP_PREFERENCES_NAME: string = 'lx_music_preferences';
