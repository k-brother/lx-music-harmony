// 全局类型定义 - 对应 src/types/app.d.ts
// 应用的全局数据类型声明

// 播放器状态
export interface PlayerStatus {
  isInitialized: boolean;
  isRegisteredService: boolean;
  isIniting: boolean;
}

// 播放信息
export interface PlayInfo {
  isPlaying: boolean;
  status: string;
  currentTrack: object | null;
}

// 全局LX状态
export interface LX {
  fontSize: number;
  playerStatus: PlayerStatus;
  isPlayedStop: boolean;
  playerTrackId: string | null;
  gettingUrlId: string | null;
  playInfo: PlayInfo;
  homePagerIdle: boolean;
}

// App事件接口
export interface AppEventInterface {
  error: () => void;
  playerError: () => void;
  playerPlaying: () => void;
  playerPause: () => void;
  playerWaiting: () => void;
  playerLoadstart: () => void;
  playerEnded: () => void;
  playerEmptied: () => void;
  play: () => void;
  pause: () => void;
  setProgress: (position: number) => void;
  jumpListPosition: () => void;
  changeMenuVisible: (visible: boolean) => void;
  searchTypeChanged: (type: string) => void;
  showSonglistTagList: () => void;
  hideSonglistTagList: () => void;
}

// 状态事件接口
export interface StateEventInterface {
  on: (event: string, callback: Function) => void;
  off: (event: string, callback: Function) => void;
  navActiveIdUpdated: (id: string) => void;
  playInfoChanged: (info: object) => void;
  playMusicInfoChanged: (info: object) => void;
  playerMusicInfoChanged: (info: object) => void;
  playStateChanged: (isPlay: boolean) => void;
  playStateTextChanged: (text: string) => void;
  playProgressChanged: (progress: object) => void;
  playPlayedListChanged: (list: object[]) => void;
  playTempPlayListChanged: (list: object[]) => void;
  themeUpdated: () => void;
  languageChanged: () => void;
  configUpdated: (keys: string[], setting: object) => void;
  componentIdsUpdated: (ids: object) => void;
}

// 全局App对象
export interface GlobalApp {
  app_event: AppEventInterface;
  state_event: StateEventInterface;
}

// 创建播放器状态实例
function createPlayerStatus(): PlayerStatus {
  const playerStatus: PlayerStatus = {
    isInitialized: false,
    isRegisteredService: false,
    isIniting: false,
  };
  return playerStatus;
}

// 创建播放信息实例
function createPlayInfo(): PlayInfo {
  const playInfo: PlayInfo = {
    isPlaying: false,
    status: 'idle',
    currentTrack: null,
  };
  return playInfo;
}

// 创建LX状态实例
function createLX(): LX {
  const lxInstance: LX = {
    fontSize: 1,
    playerStatus: createPlayerStatus(),
    isPlayedStop: false,
    playerTrackId: null,
    gettingUrlId: null,
    playInfo: createPlayInfo(),
    homePagerIdle: true,
  };
  return lxInstance;
}

// 创建全局App实例
function createGlobalApp(): GlobalApp {
  const globalAppInstance: GlobalApp = {
    app_event: {
      error: () => {},
      playerError: () => {},
      playerPlaying: () => {},
      playerPause: () => {},
      playerWaiting: () => {},
      playerLoadstart: () => {},
      playerEnded: () => {},
      playerEmptied: () => {},
      play: () => {},
      pause: () => {},
      setProgress: (position: number) => {},
      jumpListPosition: () => {},
      changeMenuVisible: (visible: boolean) => {},
      searchTypeChanged: (type: string) => {},
      showSonglistTagList: () => {},
      hideSonglistTagList: () => {},
    },
    state_event: {
      on: (event: string, callback: Function) => {},
      off: (event: string, callback: Function) => {},
      navActiveIdUpdated: (id: string) => {},
      playInfoChanged: (info: object) => {},
      playMusicInfoChanged: (info: object) => {},
      playerMusicInfoChanged: (info: object) => {},
      playStateChanged: (isPlay: boolean) => {},
      playStateTextChanged: (text: string) => {},
      playProgressChanged: (progress: object) => {},
      playPlayedListChanged: (list: object[]) => {},
      playTempPlayListChanged: (list: object[]) => {},
      themeUpdated: () => {},
      languageChanged: () => {},
      configUpdated: (keys: string[], setting: object) => {},
      componentIdsUpdated: (ids: object) => {},
    },
  };
  return globalAppInstance;
}

// 全局变量实例
export let lx: LX = createLX();
export let globalApp: GlobalApp = createGlobalApp();
