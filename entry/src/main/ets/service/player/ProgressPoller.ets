/**
 * 播放进度轮询器
 *
 * 从 PlayerService 抽出：每秒读一次播放位置并回调，连续失败 5 次自动停表。
 * 之前这段写死在播放服务里（含在飞行中的 async 块、失败计数、定时器句柄），
 * 抽成小类之后「什么时候轮询、失败怎么办」一目了然，也便于单独核对。
 *
 * 与播放器的耦合通过 host 回调注入：轮询器不认识 AvPlayer，只负责节奏与容错。
 */
import { appLog as hilog } from '../../core/log/AppLogger';

const TAG = 'ProgressPoller';
const DOMAIN: number = 0x0002;
/** 默认轮询间隔与失败上限 */
const DEFAULT_INTERVAL_MS = 1000;
const MAX_FAILURES = 5;

export interface ProgressPollerHost {
  /** 当前是否在播放（不在播放则不轮询） */
  isPlaying: () => boolean;
  /** 读当前位置（秒） */
  readPosition: () => Promise<number>;
  /** 读总时长（秒） */
  readDuration: () => Promise<number>;
  /** 每次成功读到进度 */
  onTick: (position: number, duration: number) => void;
}

export class ProgressPoller {
  private timerId: number = -1;
  private failCount: number = 0;
  private host: ProgressPollerHost;

  constructor(host: ProgressPollerHost) {
    this.host = host;
  }

  isRunning(): boolean {
    return this.timerId !== -1;
  }

  /** 启动（重复调用会先停旧的，避免多表并存） */
  start(intervalMs: number = DEFAULT_INTERVAL_MS): void {
    this.stop();
    this.failCount = 0;
    this.timerId = setInterval((): void => {
      if (this.timerId === -1 || !this.host.isPlaying()) {
        return;
      }
      // 上一拍还在读就让过去；catch 全部在内部处理，避免未捕获的 promise 告警
      (async (): Promise<void> => {
        try {
          const position = await this.host.readPosition();
          const duration = await this.host.readDuration();
          this.failCount = 0;
          this.host.onTick(position, duration);
        } catch (err) {
          this.failCount++;
          if (this.failCount >= MAX_FAILURES) {
            this.stop();
            hilog.warn(DOMAIN, TAG, 'Progress timer stopped after %{public}d consecutive failures: %{public}s',
              MAX_FAILURES, (err as Error)?.message ?? '');
            return;
          }
          hilog.warn(DOMAIN, TAG, 'Progress poll failed (%{public}d/%{public}d): %{public}s',
            this.failCount, MAX_FAILURES, (err as Error)?.message ?? '');
        }
      })().catch((_err: Error): void => {
        // 已在内部处理
      });
    }, intervalMs);
  }

  stop(): void {
    if (this.timerId !== -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    this.failCount = 0;
  }
}
