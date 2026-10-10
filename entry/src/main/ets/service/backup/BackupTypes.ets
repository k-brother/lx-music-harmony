/**
 * 备份域的公共类型
 *
 * 从 BackupService 抽出：数据类型枚举、文件描述、三份快照与备份内容结构，
 * 由备份服务（文件/配置/调度）与数据映射（收集/恢复）共用。
 */

/** 备份数据类型 */
export enum BackupDataType {
  ALL = 'all',
  PLAYLISTS = 'playlists',
  SETTINGS = 'settings',
  DOWNLOADS = 'downloads',
}

/** 备份文件信息 */
export interface BackupFileInfo {
  fileName: string;
  filePath: string;
  fileSize: number;
  backupTime: number;
  dataType: BackupDataType;
  version: string;
  /** 创建备份时已配置 WebDAV：true=已同步上传 / false=上传失败（仅本地成功） */
  remoteUploaded?: boolean;
}

/** 备份中的歌单快照 */
export interface BackupPlaylistSnapshot {
  id: string;
  name: string;
  musicList: Object[];
  createTime: number;
  updateTime: number;
}

/** 备份中的下载任务快照 */
export interface BackupDownloadSnapshot {
  id: string;
  fileName: string;
  filePath: string;
  status: string;
  createTime: number;
  /** 歌曲信息（恢复后仍可播放/展示） */
  musicInfo?: Object;
  quality?: string;
  progress?: number;
}

/** 备份内容主体 */
export interface BackupData {
  playlists?: BackupPlaylistSnapshot[];
  settings?: Record<string, Object>;
  downloads?: BackupDownloadSnapshot[];
}

/** 备份数据内容（落盘 JSON 的结构） */
export interface BackupDataContent {
  appVersion: string;
  backupTime: string;
  dataType: BackupDataType;
  data: BackupData;
}
