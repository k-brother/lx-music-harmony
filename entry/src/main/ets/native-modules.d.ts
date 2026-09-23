/**
 * 原生模块（.so）模块声明 —— 只声明「有这个原生库」，不重复声明句柄形状。
 *
 * 句柄接口统一在 core/napi/NativeModuleTypes.ets 声明一份，加载统一走
 * core/napi/NativeModules.ets：
 * - 这里若再写一遍形状，就等于两份声明，ArkTS 不支持结构化类型
 *   （arkts-no-structural-typing），很容易踩「形状相同但不同名」的报红；
 * - ArkTS 也不允许类型位置写 typeof（arkts-no-type-query），
 *   所以原生库句柄类型只能来自显式声明的接口。
 */

/** libquickjs_loader.so：按路径 dlopen QuickJS 动态库（直连失败时的兜底） */
declare module 'libquickjs_loader.so' {
  const module: Object;
  export default module;
}

/** libquickjs_napi.so：QuickJS 引擎直连 */
declare module 'libquickjs_napi.so' {
  const module: Object;
  export default module;
}

/** libinflate_napi.so：zlib/gzip 内存解压（酷我歌词是压缩体） */
declare module 'libinflate_napi.so' {
  const module: Object;
  export default module;
}
