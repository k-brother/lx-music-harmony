/**
 * 原生模块（.so）统一加载入口
 *
 * 约定（由 scripts/check_native_modules.py 钉住）：
 * 1. 全工程只有这一个文件 `import ... from 'lib*.so'`，其它模块一律通过本文件的
 *    getXxxModule() 取句柄 —— 想知道应用里用了哪些原生库，看这一个文件就够；
 * 2. 加载方式统一：同一个 loadNative() 负责探测 + 缓存 + 失败只记一次日志，
 *    原生库缺失或加载抛异常都统一返回 null，调用方按「该能力不可用」降级；
 * 3. 类型单一来源：句柄接口统一声明在 ./NativeModuleTypes.ets，这里用 `as` 收敛；
 *    ArkTS 不支持结构化类型（arkts-no-structural-typing），也不允许类型位置写
 *    typeof（arkts-no-type-query），所以句柄类型只能引用那一份声明。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import inflateNapiSo from 'libinflate_napi.so';
import quickjsLoaderSo from 'libquickjs_loader.so';
import quickjsNapiSo from 'libquickjs_napi.so';
import type {
  InflateNativeModule,
  QuickJSLoaderNativeModule,
  QuickJSNativeModule,
} from './NativeModuleTypes';

const TAG = 'NativeModules';
const DOMAIN = 0x0001;

const NAME_INFLATE: string = 'libinflate_napi.so';
const NAME_QUICKJS: string = 'libquickjs_napi.so';
const NAME_QUICKJS_LOADER: string = 'libquickjs_loader.so';

/**
 * 统一的加载探测
 *
 * 句柄用 thunk 传进来（`() => inflateNapiSo`），这样「读取 .so 绑定」这一步也在
 * try 里：原生库缺失时读绑定可能抛异常，统一在这里兜住，不让它炸到业务层。
 * 探测结果只算一次，成功返回句柄，失败返回 null。
 */
function loadNative<T>(name: string, resolve: () => T): T | null {
  try {
    const handle: T = resolve();
    if (handle) {
      hilog.info(DOMAIN, TAG, 'native module ready: %{public}s', name);
      return handle;
    }
    hilog.warn(DOMAIN, TAG, 'native module unavailable: %{public}s', name);
    return null;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'native module failed: %{public}s %{public}s', name,
      err instanceof Error ? err.message : String(err));
    return null;
  }
}

let inflateHandle: InflateNativeModule | null = null;
let inflateProbed: boolean = false;

/** libinflate_napi.so 句柄；原生库不可用时返回 null */
export function getInflateModule(): InflateNativeModule | null {
  if (!inflateProbed) {
    inflateProbed = true;
    inflateHandle = loadNative(NAME_INFLATE, (): InflateNativeModule => inflateNapiSo as InflateNativeModule);
  }
  return inflateHandle;
}

let quickjsHandle: QuickJSNativeModule | null = null;
let quickjsProbed: boolean = false;

/** libquickjs_napi.so 句柄；原生库不可用时返回 null */
export function getQuickJSModule(): QuickJSNativeModule | null {
  if (!quickjsProbed) {
    quickjsProbed = true;
    quickjsHandle = loadNative(NAME_QUICKJS, (): QuickJSNativeModule => quickjsNapiSo as QuickJSNativeModule);
  }
  return quickjsHandle;
}

let quickjsLoaderHandle: QuickJSLoaderNativeModule | null = null;
let quickjsLoaderProbed: boolean = false;

/** libquickjs_loader.so 句柄；原生库不可用时返回 null */
export function getQuickJSLoaderModule(): QuickJSLoaderNativeModule | null {
  if (!quickjsLoaderProbed) {
    quickjsLoaderProbed = true;
    quickjsLoaderHandle = loadNative(NAME_QUICKJS_LOADER,
      (): QuickJSLoaderNativeModule => quickjsLoaderSo as QuickJSLoaderNativeModule);
  }
  return quickjsLoaderHandle;
}
