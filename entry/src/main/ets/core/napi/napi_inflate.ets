/**
 * 原生 zlib 解压封装
 *
 * 酷我等音源的歌词接口返回 zlib 压缩体（魔数 78 9c），ArkTS 只有基于文件、
 * 且仅支持 zip 的 zlib.decompressFile，所以走原生模块做内存解压。
 * 原生模块不可用时返回 null，调用方按「该路径不可用」继续走后续兜底。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import inflateNapiSo from 'libinflate_napi.so';

const TAG = 'NapiInflate';
const DOMAIN = 0x0001;

interface InflateNapiModule {
  inflateBytes(data: ArrayBuffer | Uint8Array): ArrayBuffer | undefined;
}

const inflateModule: InflateNapiModule = inflateNapiSo;

/**
 * 内存解压（自动识别 zlib / gzip 头）
 * @returns 解压后的字节；失败返回 null
 */
export function zlibInflate(data: ArrayBuffer): ArrayBuffer | null {
  if (data.byteLength === 0) {
    return null;
  }
  try {
    const result: ArrayBuffer | undefined = inflateModule.inflateBytes(data);
    if (result && result.byteLength > 0) {
      return result;
    }
    return null;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'zlibInflate failed: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    return null;
  }
}
