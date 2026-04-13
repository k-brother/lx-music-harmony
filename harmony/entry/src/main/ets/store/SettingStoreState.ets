// Setting Store - 对应 src/store/setting/state.ts
// 应用设置状态 - 使用 ArkTS 兼容语法

// 播放来源别名
export interface SourceName {
  kw: string;  // 酷我
  tx: string;   // 腾讯
  mg: string;   // 咪咕
  wy: string;   // 网易
}

// 音质列表
export interface QualityList {
  low: string;
  medium: string;
  high: string;
  super: string;
}

// 播放设置
interface PlaySettings {
  autoPlay: boolean;
  continuePlay: boolean;
  playIndex: number;
  volume: number;
  playerTimer: number;
  timeoutExit: number;
}

// 通用设置
interface CommonSettings {
  apiSource: string;
  sourceNames: SourceName;
  qualityList: QualityList;
  play: PlaySettings;
}

// 播放列表设置
interface ListSettings {
  defaultPlay: boolean;
  autoDownload: boolean;
  downloadPath: string;
}

// 下载设置
interface DownloadSettings {
  threadNum: number;
  savePath: string;
  maxDownloading: number;
  flatOfflineData: boolean;
}

// 桌面歌词设置
interface DesktopLyricSettings {
  enable: boolean;
  defaultOpen: boolean;
  align: string;
  style: number;
}

// 歌词设置
interface LyricSettings {
  syncLyric: boolean;
  showLyricTranslation: boolean;
  lxlrc: boolean;
  playLxlrc: boolean;
  desktopLyric: DesktopLyricSettings;
}

// 搜索设置
interface SearchSettings {
  searchHistory: boolean;
  maxSearchHistory: number;
}

// 同步设置
interface SyncSettings {
  enable: boolean;
  syncMode: string;
  syncKey: string;
}

// 设置状态
export class SettingState {
  // 通用设置
  common: CommonSettings = {
    apiSource: 'kw',
    sourceNames: {
      kw: '酷我',
      tx: 'QQ音乐',
      mg: '咪咕',
      wy: '网易',
    },
    qualityList: {
      low: '128k',
      medium: '320k',
      high: 'flac',
      super: 'flac',
    },
    play: {
      autoPlay: false,
      continuePlay: false,
      playIndex: -1,
      volume: 1,
      playerTimer: 0,
      timeoutExit: 0,
    },
  };

  // 播放列表设置
  list: ListSettings = {
    defaultPlay: false,
    autoDownload: false,
    downloadPath: '',
  };

  // 下载设置
  download: DownloadSettings = {
    threadNum: 3,
    savePath: '',
    maxDownloading: 3,
    flatOfflineData: false,
  };

  // 歌词设置
  lyric: LyricSettings = {
    syncLyric: true,
    showLyricTranslation: true,
    lxlrc: false,
    playLxlrc: false,
    desktopLyric: {
      enable: false,
      defaultOpen: false,
      align: 'left',
      style: 0,
    },
  };

  // 搜索设置
  search: SearchSettings = {
    searchHistory: true,
    maxSearchHistory: 50,
  };

  // 同步设置
  sync: SyncSettings = {
    enable: false,
    syncMode: 'push',
    syncKey: '',
  };

  // 歌词翻译类型
  lyricTranslationType: string = 'original';
}

// 导出单例
export const settingState = new SettingState();
