/**
 * 同步传输层（WebSocket 连接、健康检查、断线重连）
 *
 * 从 SyncService 抽出：连接生命周期（建连、监听、重连退避、断开）与同步业务
 * （打包数据、合并数据、状态机）是两件事，混在一个类里时「重连为什么会打三次」这类
 * 问题要跨十几个方法找。这里只负责「把消息送出去 / 把消息交回来」。
 *
 * 与服务的契约：通过 handlers 回调把「收到消息」和「连接状态变化」交回服务，
 * 传输层不含任何业务判断。
 */
import { webSocket } from '@kit.NetworkKit';
import { appLog as hilog } from '../../core/log/AppLogger';
import { createLxWebSocket, decodeWsPayload } from '../../core/network/websocket';
import { httpRequest } from '../../core/network/http';
import { t } from '../LocalizationService';
import type { ApiResponse, SyncConfig, SyncMessage } from './SyncTypes';

const TAG = 'SyncTransport';
const DOMAIN: number = 0x0001;
/** 重连退避与上限 */
const MAX_RECONNECT_ATTEMPTS = 5;
const RECONNECT_DELAY_MS = 3000;

/** 传输层回调（由同步服务实现） */
export interface SyncTransportHandlers {
  /** 收到一条同步消息 */
  onMessage: (message: SyncMessage) => void;
  /** 连接状态变化：connected=false 时 msg 表示原因 */
  onConnectionChange: (connected: boolean, msg: string) => void;
}

export class SyncTransport {
  private socket: webSocket.WebSocket | null = null;
  private connected: boolean = false;
  private reconnectAttempts: number = 0;
  private reconnectTimerId: number | null = null;
  private handlers: SyncTransportHandlers;

  constructor(handlers: SyncTransportHandlers) {
    this.handlers = handlers;
  }

  isConnected(): boolean {
    return this.connected;
  }

  /** 健康检查：确认服务器在（避免直接建 WS 卡住） */
  async checkServerStatus(config: SyncConfig): Promise<boolean> {
    try {
      const task = httpRequest(`${config.serverUrl}/api/health`, { method: 'GET' });
      const response = await task.promise;
      if (response && response.result) {
        const resultStr: string = typeof response.result === 'string' ? response.result : '';
        if (resultStr.length > 0) {
          const data: ApiResponse = JSON.parse(resultStr) as ApiResponse;
          // 健康检查接口回 success，老接口只回 code（200 视为可用）
          return data.success === true || data.code === 200;
        }
      }
      return false;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '检查服务器状态失败: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /** 建连（含健康检查与一次重连计数复位） */
  async connect(config: SyncConfig): Promise<boolean> {
    if (this.connected && this.socket) {
      return true;
    }
    try {
      this.handlers.onConnectionChange(false, t('sync_msg_connecting'));
      const alive = await this.checkServerStatus(config);
      if (!alive) {
        hilog.warn(DOMAIN, TAG, 'Server health check failed: %{public}s', config.serverUrl);
        this.handlers.onConnectionChange(false, t('sync_msg_server_unavailable'));
        return false;
      }
      await this.connectWebSocket(config);
      this.reconnectAttempts = 0;
      this.connected = true;
      this.handlers.onConnectionChange(true, t('sync_msg_connected'));
      return true;
    } catch (err) {
      const msg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, '连接失败: %{public}s', msg);
      this.handlers.onConnectionChange(false, t('sync_msg_connect_failed'));
      return false;
    }
  }

  private async connectWebSocket(config: SyncConfig): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
      try {
        // 创建 WebSocket 连接（统一工厂），URL 规则与原实现一致：ws(s) + key + mode
        this.socket = createLxWebSocket();
        this.setupListeners(config, resolve, reject);

        let wsUrl = config.serverUrl;
        if (!wsUrl.startsWith('ws://') && !wsUrl.startsWith('wss://')) {
          wsUrl = `ws://${wsUrl}`;
        }
        const fullUrl = `${wsUrl}?key=${encodeURIComponent(config.syncKey)}&mode=${config.mode}`;
        this.socket.connect(fullUrl, (err: Error) => {
          if (err) {
            reject(err);
          }
        });
      } catch (err) {
        reject(err instanceof Error ? err : new Error(JSON.stringify(err)));
      }
    });
  }

  private setupListeners(config: SyncConfig, resolve: () => void, reject: (e: Error) => void): void {
    const socket = this.socket;
    if (!socket) {
      reject(new Error('WebSocket not created'));
      return;
    }
    socket.on('open', () => {
      hilog.info(DOMAIN, TAG, 'WebSocket连接已建立');
      this.connected = true;
      resolve();
    });

    socket.on('message', (err: Error, data: string | ArrayBuffer) => {
      if (err) {
        hilog.error(DOMAIN, TAG, 'WebSocket消息错误: %{public}s', err.message);
        return;
      }
      try {
        const messageStr: string = decodeWsPayload(data);
        const message: SyncMessage = JSON.parse(messageStr) as SyncMessage;
        this.handlers.onMessage(message);
      } catch (err) {
        hilog.error(DOMAIN, TAG, '处理WebSocket消息失败: %{public}s',
          err instanceof Error ? err.message : JSON.stringify(err));
      }
    });

    socket.on('close', () => {
      hilog.info(DOMAIN, TAG, 'WebSocket连接关闭');
      this.connected = false;
      this.releaseSocket();
      this.scheduleReconnect(config);
    });

    socket.on('error', (err: Error) => {
      hilog.error(DOMAIN, TAG, 'WebSocket错误: %{public}s', err.message);
      this.connected = false;
      reject(err);
    });
  }

  private releaseSocket(): void {
    if (this.socket) {
      this.socket.off('open');
      this.socket.off('message');
      this.socket.off('close');
      this.socket.off('error');
      this.socket = null;
    }
  }

  /** 断线重连：指数按次数封顶，超过上限不再重试 */
  private scheduleReconnect(config: SyncConfig): void {
    if (!config.enabled || this.reconnectAttempts >= MAX_RECONNECT_ATTEMPTS) {
      return;
    }
    this.reconnectAttempts++;
    this.reconnectTimerId = setTimeout(() => {
      this.connect(config).then((): void => {
        hilog.info(DOMAIN, TAG, '重连成功');
      }).catch((err: Error): void => {
        hilog.error(DOMAIN, TAG, '重连失败: %{public}s', err.message);
      });
    }, RECONNECT_DELAY_MS);
  }

  async disconnect(): Promise<void> {
    if (this.reconnectTimerId !== null) {
      clearTimeout(this.reconnectTimerId);
      this.reconnectTimerId = null;
    }
    const socket = this.socket;
    if (socket && this.connected) {
      try {
        await socket.close({ code: 1000, reason: t('sync_msg_normal_close') });
      } catch (err) {
        hilog.error(DOMAIN, TAG, '断开连接失败: %{public}s', JSON.stringify(err));
      } finally {
        this.releaseSocket();
        this.connected = false;
      }
    }
  }

  /** 发送一条同步消息 */
  async send(message: SyncMessage): Promise<void> {
    if (!this.connected || !this.socket) {
      throw new Error('WebSocket not connected');
    }
    // send 的异常按原语义上抛给调用方（它决定重连/丢弃），这里只补一条日志
    try {
      await this.socket.send(JSON.stringify(message));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'send failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      throw err as Error;
    }
  }

}
