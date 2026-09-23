// 同步服务
// 对应安卓版的同步功能

// 日志经由应用日志门面，既输出 hilog 也进入「设置 → 运行日志」
import { appLog as hilog } from '../core/log/AppLogger';
import { common } from '@kit.AbilityKit';

import { httpRequest } from '../core/network/http';
import { createLxWebSocket, decodeWsPayload } from '../core/network/websocket';
import { webSocket } from '@kit.NetworkKit';
import { settingsService } from './SettingsService';
import { t } from './LocalizationService';
import {
  SyncStatus,
  SyncMode,
  type SyncConfig,
  type SyncStatusInfo,
  type SyncHistoryItem,
  type SyncMessage,
  type SyncData,
  type SyncJsonValue,
  type ApiResponse,
} from './sync/SyncTypes';
import { encryptPayload, decryptPayload } from './sync/SyncCrypto';
import { getServerHistory, rememberServer, removeServerHistory } from './sync/SyncHistoryStore';
import { collectLocalData, mergeDataToLocal } from './sync/SyncDataMapper';

// 类型对外仍从本模块导出（设置页等调用方的 import 路径保持不变）
export {
  SyncStatus,
  SyncMode,
} from './sync/SyncTypes';
export type {
  SyncConfig,
  SyncStatusInfo,
  SyncHistoryItem,
  SyncMessage,
  SyncData,
  SyncJsonValue,
} from './sync/SyncTypes';

const DOMAIN: number = 0x0001;
const TAG: string = 'SyncService';

// 同步服务类
export class SyncService {
  private static instance: SyncService;
  private config: SyncConfig = {
    enabled: false,
    serverUrl: '',
    syncKey: '',
    mode: SyncMode.CLIENT,
    autoSync: true,
    syncInterval: 30
  };
  
  private currentStatus: SyncStatusInfo = {
    status: SyncStatus.DISCONNECTED,
    message: t('sync_msg_disconnected'),
    lastSyncTime: 0
  };
  
  private statusListeners: Array<(status: SyncStatusInfo) => void> = [];
  private syncTimer: number | null = null;
  private webSocket: webSocket.WebSocket | null = null;
  private isWsConnected: boolean = false;
  private reconnectAttempts: number = 0;
  private maxReconnectAttempts: number = 5;
  private reconnectDelay: number = 3000; // 3 seconds
  private reconnectTimerId: number | null = null;

  private constructor() {}

  // 单例获取
  static getInstance(): SyncService {
    if (!SyncService.instance) {
      SyncService.instance = new SyncService();
    }
    return SyncService.instance;
  }

  // 初始化
  async initialize(): Promise<void> {
    try {
      await this.loadConfig();
      
      if (this.config.enabled && this.config.autoSync) {
        this.startAutoSync();
      }
      
      hilog.info(DOMAIN, TAG, 'Sync service initialized');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to initialize sync service: %{public}s', JSON.stringify(err));
    }
  }

  // 加载配置
  async loadConfig(): Promise<void> {
    try {
      const settings = settingsService.get();
      this.config.enabled = settings.syncEnabled;
      this.config.serverUrl = settings.syncServer;
      this.config.syncKey = settings.syncKey;
      this.config.mode = settings.syncMode === 'server' ? SyncMode.SERVER : SyncMode.CLIENT;
      this.config.autoSync = settings.syncAutoSync;
      this.config.syncInterval = settings.syncInterval;

      hilog.info(DOMAIN, TAG, 'Sync config loaded (enabled=%{public}s, server=%{public}s)',
        this.config.enabled.toString(), this.config.serverUrl);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to load sync config: %{public}s', JSON.stringify(err));
    }
  }

  // 保存配置
  async saveConfig(): Promise<void> {
    try {
      await settingsService.update({
        syncEnabled: this.config.enabled,
        syncServer: this.config.serverUrl,
        syncKey: this.config.syncKey,
        syncMode: this.config.mode === SyncMode.SERVER ? 'server' : 'client',
        syncAutoSync: this.config.autoSync,
        syncInterval: this.config.syncInterval,
      });
      hilog.info(DOMAIN, TAG, 'Sync config saved');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to save sync config: %{public}s', JSON.stringify(err));
    }
  }

  // ==================== 同步历史（对齐安卓版 Sync/History） ====================

  /** 选中历史里的某个地址作为当前同步服务器 */
  async applyHistoryServer(serverUrl: string): Promise<void> {
    await this.updateConfig({ serverUrl });
  }

  // 获取配置
  getConfig(): SyncConfig {
    const result: SyncConfig = {
      enabled: this.config.enabled,
      serverUrl: this.config.serverUrl,
      syncKey: this.config.syncKey,
      mode: this.config.mode,
      autoSync: this.config.autoSync,
      syncInterval: this.config.syncInterval
    };
    return result;
  }

  // 更新配置
  async updateConfig(newConfig: Partial<SyncConfig>): Promise<void> {
    const updated: SyncConfig = {
      enabled: newConfig.enabled !== undefined ? newConfig.enabled : this.config.enabled,
      serverUrl: newConfig.serverUrl !== undefined ? newConfig.serverUrl : this.config.serverUrl,
      syncKey: newConfig.syncKey !== undefined ? newConfig.syncKey : this.config.syncKey,
      mode: newConfig.mode !== undefined ? newConfig.mode : this.config.mode,
      autoSync: newConfig.autoSync !== undefined ? newConfig.autoSync : this.config.autoSync,
      syncInterval: newConfig.syncInterval !== undefined ? newConfig.syncInterval : this.config.syncInterval
    };
    this.config = updated;
    await this.saveConfig();
    // 记录使用过的服务器地址（同步历史，对齐安卓版 getSyncHostHistory）
    if (newConfig.serverUrl !== undefined) {
      await this.rememberServer(this.config.serverUrl);
    }
    
    // 重新启动自动同步
    if (this.syncTimer) {
      clearInterval(this.syncTimer);
      this.syncTimer = null;
    }
    
    if (this.config.enabled && this.config.autoSync) {
      this.startAutoSync();
    }
  }

  // 获取状态
  getStatus(): SyncStatusInfo {
    const result: SyncStatusInfo = {
      status: this.currentStatus.status,
      message: this.currentStatus.message,
      lastSyncTime: this.currentStatus.lastSyncTime,
      error: this.currentStatus.error
    };
    return result;
  }

  // 更新状态
  private updateStatus(status: SyncStatus, message: string, error?: string): void {
    this.currentStatus = {
      status,
      message,
      lastSyncTime: status === SyncStatus.CONNECTED ? Date.now() : this.currentStatus.lastSyncTime,
      error
    };
    
    this.notifyStatusChange();
  }

  // 连接服务器
  async connect(): Promise<boolean> {
    if (!this.config.enabled || !this.config.serverUrl) {
      this.updateStatus(SyncStatus.ERROR, t('sync_msg_not_enabled'));
      return false;
    }

    // 如果已经连接，先断开
    if (this.webSocket && this.isWsConnected) {
      await this.disconnect();
    }

    this.updateStatus(SyncStatus.CONNECTING, t('sync_msg_connecting'));
    
    try {
      // 首先检查服务器状态
      const serverAvailable = await this.checkServerStatus();
      if (!serverAvailable) {
        this.updateStatus(SyncStatus.ERROR, t('sync_msg_server_unavailable'));
        return false;
      }

      // 建立WebSocket连接
      await this.connectWebSocket();
      
      this.updateStatus(SyncStatus.CONNECTED, t('sync_msg_connected'));
      this.reconnectAttempts = 0; // 重置重连尝试次数
      return true;
    } catch (err) {
      const errorMsg: string = JSON.stringify(err);
      this.updateStatus(SyncStatus.ERROR, t('sync_msg_connect_failed'), errorMsg);
      
      // 尝试重连
      if (this.reconnectAttempts < this.maxReconnectAttempts) {
        this.reconnectAttempts++;
        hilog.info(DOMAIN, TAG, '尝试重连 (%{public}d/%{public}d)', 
          this.reconnectAttempts, this.maxReconnectAttempts);
        
        this.reconnectTimerId = setTimeout(() => {
          this.connect().catch((reconnectErr: Error) => {
            hilog.error(DOMAIN, TAG, '重连失败: %{public}s', JSON.stringify(reconnectErr));
          });
        }, this.reconnectDelay);
      }
      
      return false;
    }
  }

  // 检查服务器状态
  private async checkServerStatus(): Promise<boolean> {
    try {
      const serverUrl = this.config.serverUrl.replace('ws://', 'http://').replace('wss://', 'https://');
      const task = httpRequest(`${serverUrl}/api/status`, {
        method: 'GET',
        connectTimeout: 10000,
        readTimeout: 10000,
      });
      const response = await task.promise;
      // Check if we received a valid response
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

  // 连接WebSocket
  private async connectWebSocket(): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (error: Error) => void) => {
      try {
        // 创建WebSocket连接（统一工厂）
        this.webSocket = createLxWebSocket();
        
        // 设置事件监听器
        this.setupWebSocketListeners(resolve, reject);
        
        // 构建WebSocket URL
        let wsUrl = this.config.serverUrl;
        if (!wsUrl.startsWith('ws://') && !wsUrl.startsWith('wss://')) {
          wsUrl = `ws://${wsUrl}`;
        }
        
        // 添加同步密钥到URL
        const fullUrl = `${wsUrl}?key=${encodeURIComponent(this.config.syncKey)}&mode=${this.config.mode}`;
        
        // 连接服务器
        this.webSocket.connect(fullUrl, (err: Error) => {
          if (err) {
            reject(err);
          }
        });
      } catch (err) {
        reject(err instanceof Error ? err : new Error(JSON.stringify(err)));
      }
    });
  }

  // 设置WebSocket监听器
  private setupWebSocketListeners(resolve: () => void, reject: (error: Error) => void): void {
    if (!this.webSocket) return;

    // 连接打开
    this.webSocket.on('open', () => {
      hilog.info(DOMAIN, TAG, 'WebSocket连接已打开');
      this.isWsConnected = true;
      resolve();
    });

    // 收到消息
    this.webSocket.on('message', (err: Error, data: string | ArrayBuffer) => {
      if (err) {
        hilog.error(DOMAIN, TAG, 'WebSocket消息错误: %{public}s', err.message);
        return;
      }
      try {
        const messageStr: string = decodeWsPayload(data);
        const message: SyncMessage = JSON.parse(messageStr) as SyncMessage;
        this.handleSyncMessage(message);
      } catch (err) {
        const errMsg: string = err instanceof Error ? err.message : 'Unknown error';
        hilog.error(DOMAIN, TAG, '处理WebSocket消息失败: %{public}s', errMsg);
      }
    });

    // 连接关闭
    this.webSocket.on('close', () => {
      hilog.info(DOMAIN, TAG, 'WebSocket连接关闭');
      this.isWsConnected = false;
      if (this.webSocket) {
        this.webSocket.off('open');
        this.webSocket.off('message');
        this.webSocket.off('close');
        this.webSocket.off('error');
        this.webSocket = null;
      }
      
      // 尝试重连
      if (this.config.enabled && this.reconnectAttempts < this.maxReconnectAttempts) {
        this.reconnectAttempts++;
        this.reconnectTimerId = setTimeout(() => {
          this.connect().then(() => {
            hilog.info(DOMAIN, TAG, '重连成功');
          }).catch((reconnectErr: Error) => {
            hilog.error(DOMAIN, TAG, '重连失败: %{public}s', reconnectErr.message);
          });
        }, this.reconnectDelay);
      }
    });

    // 发生错误
    this.webSocket.on('error', (err: Error) => {
      hilog.error(DOMAIN, TAG, 'WebSocket错误: %{public}s', err.message);
      this.isWsConnected = false;
      reject(err);
    });
  }

  // 断开连接
  async disconnect(): Promise<void> {
    if (this.reconnectTimerId !== null) {
      clearTimeout(this.reconnectTimerId);
      this.reconnectTimerId = null;
    }
    if (this.webSocket && this.isWsConnected) {
      try {
        const closeOptions: webSocket.WebSocketCloseOptions = {
          code: 1000,
          reason: t('sync_msg_normal_close')
        };
        await this.webSocket.close(closeOptions);
      } catch (err) {
        hilog.error(DOMAIN, TAG, '断开连接失败: %{public}s', JSON.stringify(err));
      } finally {
        this.webSocket.off('open');
        this.webSocket.off('message');
        this.webSocket.off('close');
        this.webSocket.off('error');
        this.webSocket = null;
        this.isWsConnected = false;
      }
    }
  }

  // ==================== 委派（实现在 service/sync/*） ====================

  /** 读取连接过的同步服务器历史（最近使用在前） */
  async getServerHistory(): Promise<SyncHistoryItem[]> {
    return getServerHistory();
  }

  /** 记录一次使用过的服务器地址 */
  async rememberServer(serverUrl: string): Promise<void> {
    await rememberServer(serverUrl);
  }

  /** 删除一条历史 */
  async removeServerHistory(serverUrl: string): Promise<void> {
    await removeServerHistory(serverUrl);
  }

  /** 打包本地数据（歌单 + 设置） */
  private async prepareLocalData(): Promise<SyncData> {
    return collectLocalData(this.config, this.currentStatus.lastSyncTime);
  }

  /** 加密 / 解密（密钥取当前配置） */
  private async encryptData(data: string): Promise<string> {
    return encryptPayload(data, this.config.syncKey);
  }

  private async decryptData(encryptedData: string): Promise<string> {
    return decryptPayload(encryptedData, this.config.syncKey);
  }

  /** 把远端同步数据合并到本地 */
  private async mergeDataToLocal(syncData: SyncData): Promise<void> {
    await mergeDataToLocal(syncData);
  }

  // 同步数据
  async sync(): Promise<boolean> {
    if (!this.isWsConnected || !this.webSocket) {
      const connected = await this.connect();
      if (!connected) {
        return false;
      }
    }

    this.updateStatus(SyncStatus.SYNCING, t('sync_msg_syncing'));
    
    try {
      // 1. 准备本地数据
      const localData = await this.prepareLocalData();
      
      // 2. 加密数据
      const encryptedData = await this.encryptData(JSON.stringify(localData));
      
      // 3. 发送同步请求
      const syncMode: string = this.config.mode;
      const syncTimestamp: number = Date.now();
      const syncDataObj: Record<string, SyncJsonValue> = {};
      syncDataObj['mode'] = syncMode;
      syncDataObj['data'] = encryptedData;
      syncDataObj['timestamp'] = syncTimestamp;
      const syncMessage: SyncMessage = {
        type: 'sync_request',
        data: syncDataObj,
        timestamp: syncTimestamp
      };
      
      await this.sendWebSocketMessage(syncMessage);
      
      // 4. 等待同步完成（通过WebSocket消息处理）
      // 同步结果会在handleSyncMessage中处理
      
      this.updateStatus(SyncStatus.CONNECTED, t('sync_msg_request_sent'));
      return true;
    } catch (err) {
      const errorMsg: string = JSON.stringify(err);
      this.updateStatus(SyncStatus.ERROR, t('sync_msg_failed'), errorMsg);
      return false;
    }
  }

  // 发送WebSocket消息
  private async sendWebSocketMessage(message: SyncMessage): Promise<void> {
    if (!this.webSocket || !this.isWsConnected) {
      throw new Error('WebSocket未连接');
    }
    
    try {
      const messageStr = JSON.stringify(message);
      await this.webSocket.send(messageStr);
    } catch (err) {
      hilog.error(DOMAIN, TAG, '发送WebSocket消息失败: %{public}s', JSON.stringify(err));
      const error: Error = err instanceof Error ? err : new Error(JSON.stringify(err));
      throw error;
    }
  }

  // 处理同步消息
  private handleSyncMessage(message: SyncMessage): void {
    try {
      switch (message.type) {
        case 'sync_response':
          this.handleSyncResponse(message.data);
          break;
        case 'sync_data':
          this.handleSyncData(message.data);
          break;
        case 'sync_complete':
          this.handleSyncComplete(message.data);
          break;
        case 'sync_error':
          this.handleSyncError(message.data);
          break;
        default:
          hilog.warn(DOMAIN, TAG, '未知的同步消息类型: %{public}s', message.type);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, '处理同步消息失败: %{public}s', JSON.stringify(err));
    }
  }

  // 处理同步响应
  private async handleSyncResponse(data: object): Promise<void> {
    hilog.info(DOMAIN, TAG, '收到同步响应: %{public}s', JSON.stringify(data));
    
    const dataObj: Record<string, Object> = data as Record<string, Object>;
    if (dataObj['requireData']) {
      // 服务器需要数据，发送本地数据
      const localData = await this.prepareLocalData();
      const encryptedData = await this.encryptData(JSON.stringify(localData));
      
      const responseType: string = 'sync_data';
      const responseTimestamp: number = Date.now();
      const responseDataObj: Record<string, SyncJsonValue> = {};
      responseDataObj['data'] = encryptedData;
      responseDataObj['timestamp'] = responseTimestamp;
      const responseMessage: SyncMessage = {
        type: responseType,
        data: responseDataObj,
        timestamp: responseTimestamp
      };
      
      await this.sendWebSocketMessage(responseMessage);
    }
  }

  // 处理同步数据
  private async handleSyncData(data: object): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, '收到同步数据');
      
      const dataObj: Record<string, Object> = data as Record<string, Object>;
      const dataStr: string = dataObj['data'] as string;
      
      // 解密数据
      const decryptedData = await this.decryptData(dataStr);
      const syncData: SyncData = JSON.parse(decryptedData) as SyncData;
      
      // 合并数据到本地
      await this.mergeDataToLocal(syncData);
      
      // 发送同步完成消息
      const completeType: string = 'sync_complete';
      const completeTimestamp: number = Date.now();
      const completeSuccess: boolean = true;
      const completeDataObj: Record<string, SyncJsonValue> = {};
      completeDataObj['success'] = completeSuccess;
      completeDataObj['timestamp'] = completeTimestamp;
      const completeMessage: SyncMessage = {
        type: completeType,
        data: completeDataObj,
        timestamp: completeTimestamp
      };
      
      await this.sendWebSocketMessage(completeMessage);
      
      // 更新最后同步时间
      this.currentStatus.lastSyncTime = Date.now();
      this.updateStatus(SyncStatus.CONNECTED, t('sync_msg_data_done'));
      
    } catch (err) {
      const errMsg: string = err instanceof Error ? err.message : 'Unknown error';
      hilog.error(DOMAIN, TAG, '处理同步数据失败: %{public}s', errMsg);
      
      // 发送错误消息
      const errorType: string = 'sync_error';
      const errorTimestamp: number = Date.now();
      const errorDataObj: Record<string, SyncJsonValue> = {};
      errorDataObj['error'] = errMsg;
      errorDataObj['timestamp'] = errorTimestamp;
      const errorMessage: SyncMessage = {
        type: errorType,
        data: errorDataObj,
        timestamp: errorTimestamp
      };
      
      await this.sendWebSocketMessage(errorMessage);
    }
  }

  // 处理同步完成
  private handleSyncComplete(data: object): void {
    hilog.info(DOMAIN, TAG, '同步完成: %{public}s', JSON.stringify(data));
    
    const dataObj: Record<string, Object> = data as Record<string, Object>;
    if (dataObj['success']) {
      this.currentStatus.lastSyncTime = Date.now();
      this.updateStatus(SyncStatus.CONNECTED, t('sync_msg_done'));
    } else {
      const errorMsg: string = dataObj['error'] as string || '未知错误';
      this.updateStatus(SyncStatus.ERROR, t('sync_msg_failed'), errorMsg);
    }
  }

  // 处理同步错误
  private handleSyncError(data: object): void {
    const dataObj: Record<string, Object> = data as Record<string, Object>;
    const errorMsg: string = dataObj['error'] as string || '未知错误';
    hilog.error(DOMAIN, TAG, '同步错误: %{public}s', errorMsg);
    this.updateStatus(SyncStatus.ERROR, t('sync_msg_error'), errorMsg);
  }

  // 开始自动同步
  startAutoSync(): void {
    if (this.syncTimer) {
      clearInterval(this.syncTimer);
    }
    
    if (this.config.enabled && this.config.autoSync && this.config.syncInterval > 0) {
      this.syncTimer = setInterval(() => {
        this.sync().catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'Auto sync failed: %{public}s', JSON.stringify(err));
        });
      }, this.config.syncInterval * 60 * 1000);
      
      hilog.info(DOMAIN, TAG, 'Auto sync started, interval: %{public}d minutes', this.config.syncInterval);
    }
  }

  // 停止自动同步
  stopAutoSync(): void {
    if (this.syncTimer) {
      clearInterval(this.syncTimer);
      this.syncTimer = null;
      hilog.info(DOMAIN, TAG, 'Auto sync stopped');
    }
  }

  // 添加状态监听器
  addStatusListener(listener: (status: SyncStatusInfo) => void): void {
    this.statusListeners.push(listener);
  }

  // 移除状态监听器
  removeStatusListener(listener: (status: SyncStatusInfo) => void): void {
    const index = this.statusListeners.indexOf(listener);
    if (index !== -1) {
      this.statusListeners.splice(index, 1);
    }
  }

  // 通知状态变化
  private notifyStatusChange(): void {
    const status: SyncStatusInfo = this.getStatus();
    const listeners: Array<(status: SyncStatusInfo) => void> = this.statusListeners;
    for (let i: number = 0; i < listeners.length; i++) {
      try {
        listeners[i](status);
      } catch (err) {
        const errorMsg: string = JSON.stringify(err);
        hilog.error(DOMAIN, TAG, 'Status listener error: %{public}s', errorMsg);
      }
    }
  }

  // 设置上下文
  setUIContext(context: common.UIAbilityContext): void {
    this.uiContext = context;
  }

  private uiContext: common.UIAbilityContext | null = null;
}

// 导出单例
export const syncService = SyncService.getInstance();
