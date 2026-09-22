/**
 * 日志门面：与 hilog 完全同签名，额外把日志交给内存仓库（供「运行日志」页查看）。
 *
 * 用法（与原来的 hilog 完全一致，替换 import 即可）：
 *   import { appLog as hilog } from '../log/AppLogger';
 *   hilog.warn(DOMAIN, TAG, 'failed: %{public}s', err.message);
 *
 * 这样业务代码无需关心日志去向：既输出到系统 hilog，也进入应用内日志页。
 */
import hilog from '@ohos.hilog';
import {
  logStore,
  LOG_LEVEL_DEBUG,
  LOG_LEVEL_INFO,
  LOG_LEVEL_WARN,
  LOG_LEVEL_ERROR
} from './LogStore';

/** hilog 支持的格式化参数（业务侧只会传标量） */
type LogArg = string | number | boolean;

const FATAL_LEVEL = 'FATAL';

/**
 * 把 hilog 的 `%{public}s` 风格占位符替换成实际参数，
 * 让日志页里看到的是可读文本而不是模板。
 */
export function formatLogMessage(format: string, args: LogArg[]): string {
  if (args.length === 0 || format.indexOf('%{') < 0) {
    return format;
  }
  let result = '';
  let cursor = 0;
  let argIndex = 0;
  const length = format.length;
  while (cursor < length) {
    const start = format.indexOf('%{', cursor);
    if (start < 0) {
      result += format.substring(cursor);
      break;
    }
    const end = format.indexOf('}', start);
    if (end < 0 || end + 1 >= length) {
      result += format.substring(cursor);
      break;
    }
    result += format.substring(cursor, start);
    if (argIndex >= args.length) {
      // 参数不足：保留原始占位符，避免信息丢失
      result += format.substring(start, end + 2);
    } else {
      result += String(args[argIndex]);
      argIndex++;
    }
    cursor = end + 2;
  }
  return result;
}

class AppLoggerImpl {
  debug(domain: number, tag: string, format: string, ...args: LogArg[]): void {
    hilog.debug(domain, tag, format, ...args);
    logStore.record(LOG_LEVEL_DEBUG, tag, formatLogMessage(format, args));
  }

  info(domain: number, tag: string, format: string, ...args: LogArg[]): void {
    hilog.info(domain, tag, format, ...args);
    logStore.record(LOG_LEVEL_INFO, tag, formatLogMessage(format, args));
  }

  warn(domain: number, tag: string, format: string, ...args: LogArg[]): void {
    hilog.warn(domain, tag, format, ...args);
    logStore.record(LOG_LEVEL_WARN, tag, formatLogMessage(format, args));
  }

  error(domain: number, tag: string, format: string, ...args: LogArg[]): void {
    hilog.error(domain, tag, format, ...args);
    logStore.record(LOG_LEVEL_ERROR, tag, formatLogMessage(format, args));
  }

  fatal(domain: number, tag: string, format: string, ...args: LogArg[]): void {
    hilog.fatal(domain, tag, format, ...args);
    logStore.record(FATAL_LEVEL, tag, formatLogMessage(format, args));
  }
}

export const appLog = new AppLoggerImpl();
export default appLog;
