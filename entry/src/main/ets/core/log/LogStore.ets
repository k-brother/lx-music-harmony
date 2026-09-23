/**
 * 运行日志内存仓库
 *
 * 只负责"记录 + 快照"，不关心持久化（由 service/LogService 安装 sink 落盘），
 * 这样 core 层任何模块都能低成本地把日志留给「设置 → 运行日志」查看。
 *
 * 记录策略：
 * - WARN / ERROR 始终记录（用户排查问题的关键信息）
 * - DEBUG / INFO 仅在开启「记录详细日志」时记录，避免高频日志占满环形缓冲
 */

/** 单条日志 */
export interface LogRecord {
  /** 毫秒时间戳 */
  time: number;
  /** DEBUG / INFO / WARN / ERROR */
  level: string;
  /** 模块标签 */
  tag: string;
  /** 已格式化文本 */
  message: string;
}

/** 落盘回调（由 LogService 注入） */
export type LogSink = (record: LogRecord) => void;

/** 环形缓冲容量：约等于最近一次完整会话的关键日志 */
const DEFAULT_CAPACITY = 1200;

export const LOG_LEVEL_DEBUG = 'DEBUG';
export const LOG_LEVEL_INFO = 'INFO';
export const LOG_LEVEL_WARN = 'WARN';
export const LOG_LEVEL_ERROR = 'ERROR';

class LogStoreImpl {
  private records: LogRecord[] = [];
  private capacity: number = DEFAULT_CAPACITY;
  private sink: LogSink | null = null;
  private verbose: boolean = false;
  /** 版本号：页面据此判断是否需要刷新 */
  private revision: number = 0;

  /** 是否记录 DEBUG / INFO 级日志 */
  setVerbose(enable: boolean): void {
    this.verbose = enable;
  }

  /** 安装落盘回调 */
  setSink(sink: LogSink | null): void {
    this.sink = sink;
  }

  /** 记录一条日志（同步、低成本） */
  record(level: string, tag: string, message: string): void {
    if (!this.verbose && (level === LOG_LEVEL_DEBUG || level === LOG_LEVEL_INFO)) {
      return;
    }
    this.append(level, tag, message);
  }

  /**
   * 忽略"详细日志"开关，强制记录
   * 供日志服务自身的关键动作（清空、开关切换）使用，保证用户总能看到这些操作痕迹
   */
  recordAlways(level: string, tag: string, message: string): void {
    this.append(level, tag, message);
  }

  private append(level: string, tag: string, message: string): void {
    const item: LogRecord = { time: Date.now(), level, tag, message };
    this.records.push(item);
    if (this.records.length > this.capacity) {
      this.records.splice(0, this.records.length - this.capacity);
    }
    this.revision++;
    const currentSink = this.sink;
    if (currentSink) {
      try {
        currentSink(item);
      } catch (err) {
        // 落盘失败不能影响业务
      }
    }
  }

  /** 快照（时间正序） */
  snapshot(): LogRecord[] {
    return this.records.slice();
  }

  /** 按级别过滤后的快照（时间正序），level 为空表示全部 */
  query(level: string): LogRecord[] {
    if (!level || level === 'ALL') {
      return this.snapshot();
    }
    const result: LogRecord[] = [];
    for (let i = 0; i < this.records.length; i++) {
      if (this.records[i].level === level) {
        result.push(this.records[i]);
      }
    }
    return result;
  }

  count(): number {
    return this.records.length;
  }

  revisionNo(): number {
    return this.revision;
  }

  clear(): void {
    this.records = [];
    this.revision++;
  }

  /** 批量导入（启动时把上次会话的尾部日志读回来） */
  restore(records: LogRecord[]): void {
    if (records.length === 0) {
      return;
    }
    const merged = records.concat(this.records);
    this.records = merged.length > this.capacity
      ? merged.slice(merged.length - this.capacity)
      : merged;
    this.revision++;
  }
}

export const logStore = new LogStoreImpl();
export default logStore;
