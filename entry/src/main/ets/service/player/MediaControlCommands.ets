/**
 * 系统播控命令注册（播放/暂停/上一首/下一首/进度/循环/收藏）
 *
 * 从 BackgroundRunningManager 抽出：原来 8 个命令各写一段 13 行的
 * `try { session.on(...) } catch { hilog.warn }`，共 119 行，错误处理文案还各不相同。
 * 这里统一成「注册器 + 调用器」两个小函数：注册失败或回调抛错都只在一处记日志，
 * 新增一个命令只需 3 行。
 */
import { avSession } from '@kit.AVSessionKit';
import { appLog as hilog } from '../../core/log/AppLogger';
import type { AvSessionCallbacks } from './AvSessionTypes';

const TAG = 'MediaCommands';
const DOMAIN: number = 0x0001;

/** 注册一个播控命令：注册失败不影响其它命令 */
function safeRegister(command: string, register: () => void): void {
  try {
    register();
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'register %{public}s command error: %{public}s',
      command, (err as Error)?.message ?? '');
  }
}

/** 调用业务回调：回调抛错不影响播控会话 */
function safeInvoke(command: string, run: () => void): void {
  try {
    run();
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'on%{public}s callback error: %{public}s',
      command, (err as Error)?.message ?? '');
  }
}

/** 把系统播控命令接到播放器回调上 */
export function registerMediaControlCommands(
  session: avSession.AVSession, callbacks: AvSessionCallbacks | null): void {
  const dispatch = (command: string, run: () => void): void => {
    hilog.info(DOMAIN, TAG, 'AVSession command: %{public}s', command);
    safeInvoke(command, run);
  };

  safeRegister('play', (): void => {
    session.on('play', (): void => {
      dispatch('play', (): void => {
        if (callbacks) {
          callbacks.onPlay();
        }
      });
    });
  });
  safeRegister('pause', (): void => {
    session.on('pause', (): void => {
      dispatch('pause', (): void => {
        if (callbacks) {
          callbacks.onPause();
        }
      });
    });
  });
  safeRegister('stop', (): void => {
    session.on('stop', (): void => {
      dispatch('stop', (): void => {
        if (callbacks) {
          callbacks.onStop();
        }
      });
    });
  });
  safeRegister('playNext', (): void => {
    session.on('playNext', (): void => {
      dispatch('playNext', (): void => {
        if (callbacks) {
          callbacks.onPlayNext();
        }
      });
    });
  });
  safeRegister('playPrevious', (): void => {
    session.on('playPrevious', (): void => {
      dispatch('playPrevious', (): void => {
        if (callbacks) {
          callbacks.onPlayPrevious();
        }
      });
    });
  });
  safeRegister('seek', (): void => {
    session.on('seek', (positionMs: number): void => {
      hilog.info(DOMAIN, TAG, 'AVSession command: seek %{public}d', positionMs);
      safeInvoke('Seek', (): void => {
        if (callbacks) {
          callbacks.onSeek(positionMs);
        }
      });
    });
  });
  safeRegister('setLoopMode', (): void => {
    session.on('setLoopMode', (loopMode: avSession.LoopMode): void => {
      hilog.info(DOMAIN, TAG, 'AVSession command: setLoopMode %{public}d', loopMode);
      safeInvoke('SetLoopMode', (): void => {
        if (callbacks) {
          callbacks.onSetLoopMode(loopMode);
        }
      });
    });
  });
  safeRegister('toggleFavorite', (): void => {
    session.on('toggleFavorite', (assetId: string): void => {
      hilog.info(DOMAIN, TAG, 'AVSession command: toggleFavorite assetId=%{public}s', assetId);
      safeInvoke('ToggleFavorite', (): void => {
        if (callbacks) {
          callbacks.onToggleFavorite(assetId);
        }
      });
    });
  });

  hilog.info(DOMAIN, TAG, 'All control commands registered');
}
