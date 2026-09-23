/**
 * 原生模块（.so）句柄接口 —— 全工程唯一的原生库签名声明
 *
 * 为什么单独一个文件：
 * 1. ArkTS 不支持结构化类型（arkts-no-structural-typing）：两个形状相同但声明不同的
 *    接口之间不能互相赋值，所以句柄形状必须「只声明一份」，谁用谁引用；
 * 2. ArkTS 不允许类型位置写 typeof（arkts-no-type-query），句柄类型不能从 .so
 *    默认导出推导，只能显式声明；
 * 3. 加载入口见 core/napi/NativeModules.ets（唯一 import *.so 的地方），
 *    模块声明见 native-modules.d.ts（只声明「有这个库」）。
 *
 * 新增原生库时改三处：本文件加接口、native-modules.d.ts 加模块声明、
 * NativeModules.ets 加 import 与 getXxxModule()。
 */

/** libquickjs_loader.so：按路径 dlopen QuickJS 动态库（直连失败时的兜底） */
export interface QuickJSLoaderNativeModule {
  loadQuickJS(path: string): boolean;
  loadScript(script: string): string;
  callJS(action: string, data: string): string;
  unload(): void;
}

/** libquickjs_napi.so：QuickJS 引擎直连 */
export interface QuickJSNativeModule {
  loadScript(script: string): string;
  callJS(action: string, data: string): string;
  destroy(): void;
}

/** libinflate_napi.so：zlib/gzip 内存解压 */
export interface InflateNativeModule {
  /** zlib/gzip 内存解压；失败返回 undefined */
  inflateBytes(data: ArrayBuffer | Uint8Array): ArrayBuffer | undefined;
}
