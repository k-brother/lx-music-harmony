// 同步服务
// 对应安卓版的同步功能

import hilog from '@ohos.hilog';
import { common } from '@kit.AbilityKit';
import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';
import {
  getUserList,
  getDefaultList,
  getLoveList,
  LIST_IDS,
  createUserList,
  addMusicToList,
  MusicItem
} from './ListService';
import { musicItemFromPlainObject } from '../core/list/PlaylistRecordMapper';
import { utf8Encode, utf8Decode } from '../utils/TextCodec';
import { httpRequest } from '../core/network/http';
import { createLxWebSocket, decodeWsPayload } from '../core/network/websocket';
import { webSocket } from '@kit.NetworkKit';
import { settingsService, type SettingsPatch } from './SettingsService';
import { t } from './LocalizationService';

const DOMAIN: number = 0x0001;
const TAG: string = 'SyncService';

// 同步状态
export enum SyncStatus {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  SYNCING = 'syncing',
  ERROR = 'error'
}

// 同步模式
export enum SyncMode {
  SERVER = 'server',
  CLIENT = 'client'
}

// 同步配置
export interface SyncConfig {
  enabled: boolean;
  serverUrl: string;
  syncKey: string;
  mode: SyncMode;
  autoSync: boolean;
  syncInterval: number; // 分钟
}

// 同步状态信息
export interface SyncStatusInfo {
  status: SyncStatus;
  message: string;
  lastSyncTime: number;
  error?: string;
}

// API响应类型
interface ApiResponse {
  success: boolean;
  message: string;
  data?: object;
}

// WebSocket消息类型
interface SyncMessage {
  type: string;
  data: object;
  timestamp: number;
}

// 同步歌单项（导出/合并共用）
interface SyncListExport {
  id: string;
  name: string;
  type: string;
  musicCount?: number;
  musicList?: MusicItem[];
  source?: string;
  desc?: string;
  pic?: string;
  count?: number;
  createTime?: number;
  updateTime?: number;
}

// 同步 JSON 可序列化标量（ArkTS 中不可把 boolean/number 赋给 Record<string, Object>）
type SyncJsonValue = string | number | boolean | Object;

// 同步数据类型
interface SyncData {
  lists: SyncListExport[];
  settings: Record<string, SyncJsonValue>;
  lastSyncTime: number;
}

// 加密配置
interface EncryptionConfig {
  algorithm: string;
  key: string;
  iv: string;
}

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
          return data.success;
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

  // 准备本地数据
  private async prepareLocalData(): Promise<SyncData> {
    try {
      // 获取本地歌单数据
      const lists: SyncListExport[] = await this.getLocalLists();
      
      // 获取本地设置
      const settings: Record<string, SyncJsonValue> = await this.getLocalSettings();
      
      const result: SyncData = {
        lists,
        settings,
        lastSyncTime: this.currentStatus.lastSyncTime
      };
      return result;
    } catch (err) {
      const errorMsg: string = err instanceof Error ? err.message : '准备本地数据失败';
      hilog.error(DOMAIN, TAG, '准备本地数据失败: %{public}s', errorMsg);
      const error = new Error(errorMsg);
      throw error;
    }
  }

  // 获取本地歌单数据
  private async getLocalLists(): Promise<SyncListExport[]> {
    try {
      hilog.info(DOMAIN, TAG, '获取本地歌单数据');
      
      const result: SyncListExport[] = [];
      
      const defaultList: SyncListExport = {
        id: LIST_IDS.DEFAULT,
        name: '默认列表',
        type: 'default',
        musicCount: getDefaultList().length,
        musicList: getDefaultList(),
        createTime: Date.now(),
        updateTime: Date.now()
      };
      result.push(defaultList);
      
      const loveList: SyncListExport = {
        id: LIST_IDS.LOVE,
        name: '我喜欢',
        type: 'love',
        musicCount: getLoveList().length,
        musicList: getLoveList(),
        createTime: Date.now(),
        updateTime: Date.now()
      };
      result.push(loveList);
      
      const userLists = getUserList();
      for (let i = 0; i < userLists.length; i++) {
        const list = userLists[i];
        const userListData: SyncListExport = {
          id: list.id,
          name: list.name,
          type: 'user',
          source: list.source,
          desc: list.desc,
          pic: list.pic,
          count: list.count,
          createTime: list.createTime,
          updateTime: list.updateTime
        };
        result.push(userListData);
      }
      
      hilog.info(DOMAIN, TAG, '获取到 %{public}d 个本地歌单', result.length);
      return result;
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, '获取本地歌单数据失败: %{public}s', errorMsg);
      return [];
    }
  }

  // 获取本地设置
  private async getLocalSettings(): Promise<Record<string, SyncJsonValue>> {
    try {
      hilog.info(DOMAIN, TAG, '获取本地设置');

      const result: Record<string, SyncJsonValue> = {};

      // 应用设置：整体序列化为一个字段，避免逐键同步时键名漂移
      result['app_settings'] = JSON.stringify(settingsService.get());

      // 添加同步相关设置
      result['sync_enabled'] = this.config.enabled;
      result['sync_server'] = this.config.serverUrl;
      result['sync_mode'] = this.config.mode;
      result['sync_auto'] = this.config.autoSync;
      result['sync_interval'] = this.config.syncInterval;
      result['last_sync_time'] = this.currentStatus.lastSyncTime;

      hilog.info(DOMAIN, TAG, '获取到 %{public}d 个本地设置', Object.keys(result).length);
      return result;

    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, '获取本地设置失败: %{public}s', errorMsg);
      return {};
    }
  }

  // 加密数据
  private async encryptData(data: string): Promise<string> {
    try {
      // 使用AES加密
      const key: string = this.config.syncKey || 'default-sync-key';
      const iv: string = '1234567890123456'; // 固定IV，实际应用中应该随机生成
      
      // 创建AES加密器
      const cipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
      
      // 准备Key和IV
      const keyUint8Array: Uint8Array = new Uint8Array(key.length);
      for (let i: number = 0; i < key.length; i++) {
        keyUint8Array[i] = key.charCodeAt(i) & 0xFF;
      }
      
      const ivUint8Array: Uint8Array = new Uint8Array(iv.length);
      for (let i: number = 0; i < iv.length; i++) {
        ivUint8Array[i] = iv.charCodeAt(i) & 0xFF;
      }
      
      // 准备对称密钥
      const keyBlob: cryptoFramework.DataBlob = { data: keyUint8Array };
      const ivBlob: cryptoFramework.DataBlob = { data: ivUint8Array };
      const dataBlob: cryptoFramework.DataBlob = { data: utf8Encode(data) };
      
      // 创建对称密钥
      const symKeyGen: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
      const symKey: cryptoFramework.SymKey = await symKeyGen.convertKey(keyBlob);
      
      const ivParamsSpec: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: ivBlob
      };
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, ivParamsSpec);
      
      // 加密数据
      const encryptedBlob: cryptoFramework.DataBlob = await cipher.doFinal(dataBlob);
      
      // 转换为Base64字符串
      const encryptedUint8Array: Uint8Array = encryptedBlob.data;
      let base64Str: string = '';
      const base64Chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      const padding: string = '=';
      
      const len: number = encryptedUint8Array.length;
      const mod3: number = len % 3;
      
      for (let i: number = 0; i < len - mod3; i += 3) {
        const a: number = encryptedUint8Array[i];
        const b: number = encryptedUint8Array[i + 1];
        const c: number = encryptedUint8Array[i + 2];
        base64Str += base64Chars[a >> 2];
        base64Str += base64Chars[((a & 0x03) << 4) | (b >> 4)];
        base64Str += base64Chars[((b & 0x0F) << 2) | (c >> 6)];
        base64Str += base64Chars[c & 0x3F];
      }
      
      if (mod3 === 1) {
        const a: number = encryptedUint8Array[len - 1];
        base64Str += base64Chars[a >> 2];
        base64Str += base64Chars[(a & 0x03) << 4];
        base64Str += padding;
        base64Str += padding;
      } else if (mod3 === 2) {
        const a: number = encryptedUint8Array[len - 2];
        const b: number = encryptedUint8Array[len - 1];
        base64Str += base64Chars[a >> 2];
        base64Str += base64Chars[((a & 0x03) << 4) | (b >> 4)];
        base64Str += base64Chars[(b & 0x0F) << 2];
        base64Str += padding;
      }
      
      return base64Str;
    } catch (err) {
      const errorMsg: string = err instanceof Error ? err.message : '加密数据失败';
      hilog.error(DOMAIN, TAG, '加密数据失败: %{public}s', errorMsg);
      return data;
    }
  }

  // 解密数据
  private async decryptData(encryptedData: string): Promise<string> {
    try {
      // 使用AES解密
      const key: string = this.config.syncKey || 'default-sync-key';
      const iv: string = '1234567890123456'; // 固定IV，需要与加密时一致
      
      // Base64解码
      const base64Chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      const padding: string = '=';
      
      const cleanData: string = encryptedData.replace(/[\r\n]/g, '');
      const dataLen: number = cleanData.length;
      const paddingCount: number = cleanData.endsWith(padding + padding) ? 2 : (cleanData.endsWith(padding) ? 1 : 0);
      const binaryLen: number = Math.floor(dataLen * 3 / 4) - paddingCount;
      
      const decodedArray: Uint8Array = new Uint8Array(binaryLen);
      let bufIndex: number = 0;
      
      for (let i: number = 0; i < dataLen; i += 4) {
        const a: number = base64Chars.indexOf(cleanData[i]);
        const b: number = base64Chars.indexOf(cleanData[i + 1]);
        const c: number = (i + 2 < dataLen) ? base64Chars.indexOf(cleanData[i + 2]) : 0;
        const d: number = (i + 3 < dataLen) ? base64Chars.indexOf(cleanData[i + 3]) : 0;
        
        if (bufIndex < binaryLen) decodedArray[bufIndex++] = ((a << 2) | (b >> 4)) & 0xFF;
        if (bufIndex < binaryLen) decodedArray[bufIndex++] = ((b << 4) | (c >> 2)) & 0xFF;
        if (bufIndex < binaryLen) decodedArray[bufIndex++] = ((c << 6) | d) & 0xFF;
      }
      
      // 创建解密器
      const decipher: cryptoFramework.Cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
      
      // 准备Key和IV
      const keyUint8Array: Uint8Array = new Uint8Array(key.length);
      for (let i: number = 0; i < key.length; i++) {
        keyUint8Array[i] = key.charCodeAt(i) & 0xFF;
      }
      
      const ivUint8Array: Uint8Array = new Uint8Array(iv.length);
      for (let i: number = 0; i < iv.length; i++) {
        ivUint8Array[i] = iv.charCodeAt(i) & 0xFF;
      }
      
      const keyBlob: cryptoFramework.DataBlob = { data: keyUint8Array };
      const ivBlob: cryptoFramework.DataBlob = { data: ivUint8Array };
      const encryptedBlob: cryptoFramework.DataBlob = { data: decodedArray };
      
      // 创建对称密钥
      const symKeyGen: cryptoFramework.SymKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
      const symKey: cryptoFramework.SymKey = await symKeyGen.convertKey(keyBlob);
      
      const decipherIvParams: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: ivBlob
      };
      await decipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, decipherIvParams);
      
      // 解密数据
      const decryptedBlob: cryptoFramework.DataBlob = await decipher.doFinal(encryptedBlob);
      
      // 转换为字符串
      return utf8Decode(decryptedBlob.data);
    } catch (err) {
      const errorMsg: string = err instanceof Error ? err.message : '解密数据失败';
      hilog.error(DOMAIN, TAG, '解密数据失败: %{public}s', errorMsg);
      const error: Error = new Error(errorMsg);
      throw error;
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

  // 合并数据到本地
  private async mergeDataToLocal(syncData: SyncData): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, '开始合并数据到本地');
      
      // 合并歌单数据
      if (syncData.lists && syncData.lists.length > 0) {
        await this.mergeLists(syncData.lists);
      }
      
      // 合并设置数据
      if (syncData.settings) {
        await this.mergeSettings(syncData.settings);
      }
      
      hilog.info(DOMAIN, TAG, '数据合并完成');
    } catch (err) {
      const errMsg: string = err instanceof Error ? err.message : 'Unknown error';
      hilog.error(DOMAIN, TAG, '合并数据到本地失败: %{public}s', errMsg);
      const error: Error = new Error(errMsg);
      throw error;
    }
  }

  // 合并歌单数据
  private async mergeLists(remoteLists: SyncListExport[]): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, '合并歌单数据，数量: %{public}d', remoteLists.length);
      
      const localUserLists = getUserList();
      
      for (let r = 0; r < remoteLists.length; r++) {
        const remoteList = remoteLists[r];
        const listId = remoteList.id;
        const listName = remoteList.name;
        const listType = remoteList.type;
        const musicList = remoteList.musicList ?? [];
        
        if (listType === 'user') {
          const localList = localUserLists.find(list => list.id === listId);
          
          if (!localList) {
            try {
              const newList = await createUserList(listName);
              hilog.info(DOMAIN, TAG, '创建新歌单: %{public}s', listName);
              
              for (let m = 0; m < musicList.length; m++) {
                try {
                  await addMusicToList(newList.id, musicItemFromPlainObject(musicList[m] as Object));
                } catch (musicErr) {
                  hilog.warn(DOMAIN, TAG, '添加歌曲失败: %{public}s', JSON.stringify(musicErr));
                }
              }
            } catch (createErr) {
              hilog.error(DOMAIN, TAG, '创建歌单失败: %{public}s', JSON.stringify(createErr));
            }
          } else {
            hilog.info(DOMAIN, TAG, '合并现有歌单: %{public}s', listName);
            hilog.info(DOMAIN, TAG, '歌单 %{public}s 已有 %{public}d 首歌曲，远程有 %{public}d 首',
              listName, localList.count || 0, musicList.length);
          }
        } else if (listType === 'default' || listType === 'love') {
          hilog.info(DOMAIN, TAG, '合并系统歌单: %{public}s', listName);
          
          for (let m = 0; m < musicList.length; m++) {
            try {
              await addMusicToList(listId, musicItemFromPlainObject(musicList[m] as Object));
            } catch (musicErr) {
              hilog.warn(DOMAIN, TAG, '添加歌曲到系统歌单失败: %{public}s', JSON.stringify(musicErr));
            }
          }
        }
      }
      
      hilog.info(DOMAIN, TAG, '歌单数据合并完成');
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, '合并歌单数据失败: %{public}s', errorMsg);
      throw new Error(errorMsg);
    }
  }

  // 合并设置数据
  private async mergeSettings(remoteSettings: Record<string, SyncJsonValue>): Promise<void> {
    try {
      hilog.info(DOMAIN, TAG, '合并设置数据');

      const payload = remoteSettings['app_settings'];
      if (typeof payload !== 'string' || payload.length === 0) {
        hilog.warn(DOMAIN, TAG, '远端未提供 app_settings，跳过后端设置合并');
        return;
      }

      const remote = JSON.parse(payload) as SettingsPatch;
      // ArkTS 不支持 delete，这里显式只挑"用户偏好"字段，
      // 同步开关/服务器/密钥等本机连接配置不参与覆盖。
      const patch: SettingsPatch = {
        language: remote.language,
        startupPage: remote.startupPage,
        showExitDialog: remote.showExitDialog,
        themeMode: remote.themeMode,
        themeId: remote.themeId,
        autoPlay: remote.autoPlay,
        highQuality: remote.highQuality,
        playMode: remote.playMode,
        volume: remote.volume,
        sleepTimerEnabled: remote.sleepTimerEnabled,
        sleepTimerMinutes: remote.sleepTimerMinutes,
        showDesktopLyric: remote.showDesktopLyric,
        desktopLyricPosition: remote.desktopLyricPosition,
        desktopLyricColor: remote.desktopLyricColor,
        searchSource: remote.searchSource,
        showHotSearch: remote.showHotSearch,
        searchHistoryCount: remote.searchHistoryCount,
        addMusicLocation: remote.addMusicLocation,
        autoCleanPlayedList: remote.autoCleanPlayedList,
        fontSize: remote.fontSize,
        showAnimation: remote.showAnimation,
      };

      await settingsService.update(patch);
      hilog.info(DOMAIN, TAG, '设置数据合并完成');
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(DOMAIN, TAG, '合并设置数据失败: %{public}s', errorMsg);
      throw new Error(errorMsg);
    }
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

  // 获取上下文
  private getUIContext(): common.UIAbilityContext {
    if (!this.uiContext) {
      throw new Error('UIContext not set. Call setUIContext first.');
    }
    return this.uiContext;
  }

  // 设置上下文
  setUIContext(context: common.UIAbilityContext): void {
    this.uiContext = context;
  }

  private uiContext: common.UIAbilityContext | null = null;
}

// 导出单例
export const syncService = SyncService.getInstance();
