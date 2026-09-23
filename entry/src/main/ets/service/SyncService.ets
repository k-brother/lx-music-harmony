// 同步服务
// 对应安卓版的同步功能

// 日志经由应用日志门面，既输出 hilog 也进入「设置 → 运行日志」
import { appLog as hilog } from '../core/log/AppLogger';
import { common } from '@kit.AbilityKit';

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
} from './sync/SyncTypes';
import { encryptPayload, decryptPayload } from './sync/SyncCrypto';
import { getServerHistory, rememberServer, removeServerHistory } from './sync/SyncHistoryStore';
import { collectLocalData, mergeDataToLocal } from './sync/SyncDataMapper';
import { SyncTransport } from './sync/SyncTransport';

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
  /** 传输层：连接/重连/收发都在里面（见 sync/SyncTransport） */
  private transport: SyncTransport = new SyncTransport({
    onMessage: (message: SyncMessage): void => {
      this.handleSyncMessage(message);
    },
    onConnectionChange: (connected: boolean, message: string): void => {
      this.isWsConnected = connected;
      if (connected) {
        this.updateStatus(SyncStatus.CONNECTED, message);
      } else {
        this.updateStatus(SyncStatus.DISCONNECTED, message);
      }
    },
  });
  /** 是否已连上（由传输层状态同步过来，供 UI 与流程判断） */
  private isWsConnected: boolean = false;

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

  // ==================== 连接（实现在 sync/SyncTransport） ====================

  /** 连接同步服务器：健康检查 + 建 WS + 断线重连都在传输层 */
  async connect(): Promise<boolean> {
    return this.transport.connect(this.config);
  }

  /** 断开连接 */
  async disconnect(): Promise<void> {
    await this.transport.disconnect();
  }

  /** 发送同步消息 */
  private async sendWebSocketMessage(message: SyncMessage): Promise<void> {
    await this.transport.send(message);
  }

  // 同步数据
  async sync(): Promise<boolean> {
    if (!this.transport.isConnected()) {
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
