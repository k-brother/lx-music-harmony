/**
 * 运行日志服务
 *
 * 职责：
 * - 把 LogStore 的日志持久化到 `filesDir/logs/app.log`，应用重启后仍可回溯
 * - 提供读取 / 清理 / 导出（复制文本）能力，供「设置 → 运行日志」使用
 * - 文件超过上限自动滚动一份备份，避免无限增长
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  logStore,
  LogRecord,
  LOG_LEVEL_DEBUG,
  LOG_LEVEL_INFO,
  LOG_LEVEL_WARN,
  LOG_LEVEL_ERROR
} from '../core/log/LogStore';
import { settingsService } from './SettingsService';
import { on, EventTypes, type SettingChangedData } from './EventBus';

const TAG = 'LogService';
/** hilog 域号：本服务自身的落盘失败只能用系统日志兜底（此时应用日志正在失败） */
const DOMAIN = 0x0005;
/** 单个日志文件上限 512KB，超出后滚动到 app.log.1 */
const MAX_FILE_BYTES = 512 * 1024;
/** 落盘节流：3 秒内的日志合并写一次 */
const FLUSH_INTERVAL_MS = 3000;
/** 单次待写入缓冲上限 */
const MAX_PENDING_LINES = 500;
/** 启动时从文件恢复的最大条数 */
const RESTORE_LIMIT = 300;

class LogServiceImpl {
  private logDir: string = '';
  private logFile: string = '';
  private backupFile: string = '';
  private pending: string[] = [];
  private timerId: number = -1;
  private initialized: boolean = false;

  /** 应用启动时调用一次 */
  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    try {
      this.logDir = `${context.filesDir}/logs`;
      this.logFile = `${this.logDir}/app.log`;
      this.backupFile = `${this.logDir}/app.log.1`;
      await this.ensureDir(this.logDir);
      this.rotateIfNeeded();
      this.restoreFromFile();
      logStore.setVerbose(settingsService.get().enableVerboseLog);
      logStore.setSink((record: LogRecord): void => {
        this.enqueue(record);
      });
      // 设置变化时同步「记录详细日志」开关：恢复备份 / 同步下发改了它也能立即生效
      // （只靠启动时读一次 + 设置页手动调用，会漏掉这两条入口）
      on(EventTypes.SETTING_CHANGED, (data?: Object): void => {
        const key: string = data ? ((data as SettingChangedData).key ?? '') : '';
        if (key === 'enableVerboseLog' || key === 'all' || key.length === 0) {
          this.setVerbose(settingsService.get().enableVerboseLog);
        }
      });
      this.startTimer();
      this.appendSystemLine('INFO', TAG, 'LogService initialized');
    } catch (err) {
      // 日志服务本身失败时不能影响启动流程
    }
  }

  /** 详细日志开关变化时同步到 LogStore */
  setVerbose(enable: boolean): void {
    logStore.setVerbose(enable);
    this.appendSystemLine('INFO', TAG, enable ? 'Verbose logging enabled' : 'Verbose logging disabled');
  }

  /** 读取日志（时间正序），level 传空或 ALL 表示全部 */
  getRecords(level: string): LogRecord[] {
    return logStore.query(level);
  }

  /** 汇总为可复制的纯文本（时间倒序，最新在前） */
  getLogText(level: string): string {
    const records = logStore.query(level);
    const lines: string[] = [];
    for (let i = records.length - 1; i >= 0; i--) {
      lines.push(this.formatLine(records[i]));
    }
    return lines.join('\n');
  }

  count(): number {
    return logStore.count();
  }

  revision(): number {
    return logStore.revisionNo();
  }

  /** 把内存中待写入的内容立即落盘 */
  flush(): void {
    if (this.pending.length === 0 || this.logFile.length === 0) {
      return;
    }
    const text = `${this.pending.join('\n')}\n`;
    this.pending = [];
    try {
      const file = fs.openSync(this.logFile, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND);
      fs.writeSync(file.fd, text);
      fs.closeSync(file.fd);
    } catch (err) {
      // 磁盘写入失败忽略，内存日志仍可用
    }
    this.rotateIfNeeded();
  }

  /** 清空内存与磁盘日志 */
  clear(): void {
    logStore.clear();
    this.pending = [];
    try {
      if (this.logFile.length > 0) {
        this.writeTextSync(this.logFile, '');
      }
      if (this.backupFile.length > 0 && this.fileExists(this.backupFile)) {
        fs.unlinkSync(this.backupFile);
      }
    } catch (err) {
      // 忽略
    }
    this.appendSystemLine('INFO', TAG, 'Logs cleared');
  }

  /** 导出为文件，返回绝对路径；失败返回空串 */
  exportToFile(): string {
    this.flush();
    if (this.logDir.length === 0) {
      return '';
    }
    const stamp = this.timestampForFileName();
    const target = `${this.logDir}/lxmusic-log-${stamp}.txt`;
    try {
      const header = `# LX Music HarmonyOS 运行日志\n# 导出时间: ${this.formatTime(Date.now())}\n# 条目数: ${logStore.count()}\n\n`;
      this.writeTextSync(target, header + this.getLogText('ALL'));
      return target;
    } catch (err) {
      return '';
    }
  }

  /** 同步写文本（fs 无 writeFileSync，用 open/write/close 组合） */
  private writeTextSync(path: string, text: string): void {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, text);
    } catch (err) {
      // 日志落盘失败不能反过来影响业务：只记一条 hilog（此时 hilog 里还能看到）
      hilog.warn(DOMAIN, TAG, 'writeTextSync failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file.fd);
        } catch (closeErr) {
          hilog.warn(DOMAIN, TAG, 'close failed: %{public}s',
            closeErr instanceof Error ? closeErr.message : JSON.stringify(closeErr));
        }
      }
    }
  }

  /** @internal 供一次性系统提示：既进内存也走 hilog */
  private appendSystemLine(level: string, tag: string, message: string): void {
    logStore.recordAlways(level, tag, message);
  }

  private enqueue(record: LogRecord): void {
    this.pending.push(this.formatLine(record));
    if (this.pending.length > MAX_PENDING_LINES) {
      this.pending.splice(0, this.pending.length - MAX_PENDING_LINES);
    }
  }

  private startTimer(): void {
    if (this.timerId >= 0) {
      return;
    }
    this.timerId = setInterval((): void => {
      this.flush();
    }, FLUSH_INTERVAL_MS);
  }

  private formatLine(record: LogRecord): string {
    return `${this.formatTime(record.time)} ${record.level} [${record.tag}] ${record.message}`;
  }

  private formatTime(ms: number): string {
    const date = new Date(ms);
    const pad2 = (value: number): string => (value < 10 ? `0${value}` : `${value}`);
    const pad3 = (value: number): string => {
      if (value < 10) {
        return `00${value}`;
      }
      if (value < 100) {
        return `0${value}`;
      }
      return `${value}`;
    };
    return `${date.getFullYear()}-${pad2(date.getMonth() + 1)}-${pad2(date.getDate())} ` +
      `${pad2(date.getHours())}:${pad2(date.getMinutes())}:${pad2(date.getSeconds())}.${pad3(date.getMilliseconds())}`;
  }

  private timestampForFileName(): string {
    const date = new Date();
    const pad2 = (value: number): string => (value < 10 ? `0${value}` : `${value}`);
    return `${date.getFullYear()}${pad2(date.getMonth() + 1)}${pad2(date.getDate())}` +
      `-${pad2(date.getHours())}${pad2(date.getMinutes())}${pad2(date.getSeconds())}`;
  }

  private rotateIfNeeded(): void {
    try {
      if (this.logFile.length === 0 || !this.fileExists(this.logFile)) {
        return;
      }
      const stat = fs.statSync(this.logFile);
      if (stat.size < MAX_FILE_BYTES) {
        return;
      }
      if (this.fileExists(this.backupFile)) {
        fs.unlinkSync(this.backupFile);
      }
      fs.renameSync(this.logFile, this.backupFile);
    } catch (err) {
      // 忽略滚动失败
    }
  }

  /** 启动时把上次会话的尾部日志读回内存，便于查看崩溃前的上下文 */
  private restoreFromFile(): void {
    try {
      if (!this.fileExists(this.logFile)) {
        return;
      }
      const text = fs.readTextSync(this.logFile);
      if (text.length === 0) {
        return;
      }
      const lines = text.split('\n');
      const records: LogRecord[] = [];
      const start = Math.max(0, lines.length - RESTORE_LIMIT);
      for (let i = start; i < lines.length; i++) {
        const parsed = this.parseLine(lines[i]);
        if (parsed) {
          records.push(parsed);
        }
      }
      logStore.restore(records);
    } catch (err) {
      // 历史日志解析失败不影响启动
    }
  }

  /** 解析 `2026-09-22 10:00:00.123 WARN [Tag] message` 形式的历史行 */
  private parseLine(line: string): LogRecord | null {
    if (line.length < 30) {
      return null;
    }
    const level = this.detectLevel(line);
    if (level.length === 0) {
      return null;
    }
    const levelIndex = line.indexOf(` ${level} [`);
    if (levelIndex < 0) {
      return null;
    }
    const timeText = line.substring(0, levelIndex);
    const tagStart = levelIndex + level.length + 3;
    const tagEnd = line.indexOf('] ', tagStart);
    if (tagEnd < 0) {
      return null;
    }
    const time = Date.parse(timeText.replace(' ', 'T'));
    return {
      time: isNaN(time) ? Date.now() : time,
      level,
      tag: line.substring(tagStart, tagEnd),
      message: line.substring(tagEnd + 2),
    };
  }

  private detectLevel(line: string): string {
    if (line.indexOf(` ${LOG_LEVEL_ERROR} [`) > 0) {
      return LOG_LEVEL_ERROR;
    }
    if (line.indexOf(` ${LOG_LEVEL_WARN} [`) > 0) {
      return LOG_LEVEL_WARN;
    }
    if (line.indexOf(` ${LOG_LEVEL_INFO} [`) > 0) {
      return LOG_LEVEL_INFO;
    }
    if (line.indexOf(` ${LOG_LEVEL_DEBUG} [`) > 0) {
      return LOG_LEVEL_DEBUG;
    }
    return '';
  }

  private fileExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (err) {
      return false;
    }
  }

  private async ensureDir(dirPath: string): Promise<void> {
    if (this.fileExists(dirPath)) {
      return;
    }
    const parent = dirPath.substring(0, dirPath.lastIndexOf('/'));
    if (parent.length > 0 && !this.fileExists(parent)) {
      await this.ensureDir(parent);
    }
    try {
      fs.mkdirSync(dirPath);
    } catch (err) {
      // 并发创建时忽略
    }
  }

  /** 供页面调用：把日志文本写入剪贴板（返回是否成功） */
  copyText(text: string): boolean {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setDataSync(data);
      return true;
    } catch (err) {
      return false;
    }
  }
}

export const logService = new LogServiceImpl();
export default logService;
