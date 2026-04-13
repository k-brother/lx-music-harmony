// Player Store State - 对应 src/store/player/state.ts
// 播放器状态管理

import { MusicInfo, PlayMusicInfo, PlayInfo, Progress, MusicItem } from '../types/MusicTypes';

// 播放器状态
export class PlayerState {
  playInfo: PlayInfo = {
    playIndex: -1,
    playerListId: null,
    playerPlayIndex: -1,
  };

  playMusicInfo: PlayMusicInfo = {
    listId: null,
    musicInfo: null,
    isTempPlay: false,
  };

  musicInfo: MusicInfo = {
    name: '',
    singer: '',
    source: 'kw',
    interval: null,
    img: null,
    lrc: null,
  };

  isPlay: boolean = false;
  volume: number = 1;
  playRate: number = 1;
  statusText: string = '';

  playedList: PlayMusicInfo[] = [];
  tempPlayList: PlayMusicInfo[] = [];

  loadErrorPicUrl: string = '';

  progress: Progress = {
    nowPlayTime: 0,
    maxPlayTime: 0,
    progress: 0,
    nowPlayTimeStr: '00:00',
    maxPlayTimeStr: '00:00',
  };

  lastLyric: string | null = null;
}

// 导出单例
export const playerState = new PlayerState();
