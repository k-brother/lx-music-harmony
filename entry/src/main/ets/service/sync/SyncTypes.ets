/**
 * 同步域的公共类型
 *
 * 从 SyncService 抽出：配置、状态、历史、同步消息与数据体这些类型
 * 被服务、设置页（同步分组）与数据映射模块共用。
 */

/** 同步连接状态 */
export enum SyncStatus {
  DISCONNECTED = 'disconnected',
  CONNECTING = 'connecting',
  CONNECTED = 'connected',
  SYNCING = 'syncing',
  ERROR = 'error'
}

/** 同步模式：server=本机作为服务端，client=连服务器 */
export enum SyncMode {
  SERVER = 'server',
  CLIENT = 'client'
}

/** 同步配置 */
export interface SyncConfig {
  enabled: boolean;
  serverUrl: string;
  syncKey: string;
  mode: SyncMode;
  autoSync: boolean;
  syncInterval: number;
}

/** 对外暴露的同步状态 */
export interface SyncStatusInfo {
  status: SyncStatus;
  message: string;
  lastSyncTime: number;
  error?: string;
}

/** 一条同步服务器历史 */
export interface SyncHistoryItem {
  serverUrl: string;
  lastUsed: number;
}

/** 服务器接口响应 */
export interface ApiResponse {
  /** 健康检查接口回的是 success，老接口回 code，两者都保 */
  success?: boolean;
  code?: number;
  message: string;
  data?: object;
}

/** WebSocket 同步消息 */
export interface SyncMessage {
  type: string;
  data: object;
  timestamp: number;
}

/** 同步时导出的本地歌单 */
export interface SyncListExport {
  id: string;
  name: string;
  type: string;
  musicCount?: number;
  musicList?: object[];
  source?: string;
  desc?: string;
  pic?: string;
  count?: number;
  createTime?: number;
  updateTime?: number;
}

/** 同步数据体 */
export interface SyncData {
  lists: SyncListExport[];
  settings: Record<string, SyncJsonValue>;
  lastSyncTime: number;
}

/** 同步消息里可出现的 JSON 值 */
export type SyncJsonValue = string | number | boolean | null | object;
