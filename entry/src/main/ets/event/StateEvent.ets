// StateEvent - 对应 src/event/stateEvent.ts
// 状态相关事件 - ArkTS 兼容版本

import { eventInstance } from './Event';
import { MusicInfo, PlayMusicInfo, PlayInfo, Progress } from '../types/MusicTypes';

// 同步状态
export type SyncStatus = 'idle' | 'syncing' | 'error' | 'success';

// 版本信息
export interface VersionInfo {
  version: string;
  desc: string;
  publishTime: string;
}

// 配置更新接口
interface ConfigUpdateData {
  keys: string[];
  setting: object;
}

// StateEvent类实现
export class StateEventClass {

  configUpdated(keys: string[], setting: object): void {
    const configData: ConfigUpdateData = { keys: keys, setting: setting };
    const configDataCopy: ConfigUpdateData = configData;
    eventInstance.emit('configUpdated', JSON.stringify(configDataCopy));
  }

  languageChanged(locale: string): void {
    eventInstance.emit('languageChanged', locale);
  }

  fontSizeUpdated(size: number): void {
    eventInstance.emit('fontSizeUpdated', size.toString());
  }

  statusbarHeightUpdated(size: number): void {
    eventInstance.emit('statusbarHeightUpdated', size.toString());
  }

  apiSourceUpdated(source: string): void {
    eventInstance.emit('apiSourceUpdated', source);
  }

  themeUpdated(theme: string): void {
    eventInstance.emit('themeUpdated', theme);
  }

  bgPicUpdated(bgPic: string | null): void {
    eventInstance.emit('bgPicUpdated', bgPic || '');
  }

  playerMusicInfoChanged(musicInfo: MusicInfo): void {
    const musicInfoCopy: MusicInfo = musicInfo;
    eventInstance.emit('playerMusicInfoChanged', JSON.stringify(musicInfoCopy));
  }

  playMusicInfoChanged(playMusicInfo: PlayMusicInfo): void {
    const playMusicInfoCopy: PlayMusicInfo = playMusicInfo;
    eventInstance.emit('playMusicInfoChanged', JSON.stringify(playMusicInfoCopy));
  }

  playInfoChanged(playInfo: PlayInfo): void {
    const playInfoCopy: PlayInfo = playInfo;
    eventInstance.emit('playInfoChanged', JSON.stringify(playInfoCopy));
  }

  playStateTextChanged(text: string): void {
    eventInstance.emit('playStateTextChanged', text);
  }

  playStateChanged(state: boolean): void {
    eventInstance.emit('playStateChanged', state.toString());
  }

  playProgressChanged(progress: Progress): void {
    const progressCopy: Progress = progress;
    eventInstance.emit('playProgressChanged', JSON.stringify(progressCopy));
  }

  playPlayedListChanged(playedList: PlayMusicInfo[]): void {
    const playedListCopy: PlayMusicInfo[] = playedList;
    eventInstance.emit('playPlayedListChanged', JSON.stringify(playedListCopy));
  }

  playTempPlayListChanged(tempPlayList: PlayMusicInfo[]): void {
    const tempPlayListCopy: PlayMusicInfo[] = tempPlayList;
    eventInstance.emit('playTempPlayListChanged', JSON.stringify(tempPlayListCopy));
  }

  mylistUpdated(lists: object[]): void {
    const listsCopy: object[] = lists;
    eventInstance.emit('mylistUpdated', JSON.stringify(listsCopy));
  }

  mylistToggled(id: string): void {
    eventInstance.emit('mylistToggled', id);
  }

  fetchingListStatusUpdated(fetchingListStatus: boolean): void {
    eventInstance.emit('fetchingListStatusUpdated', fetchingListStatus.toString());
  }

  syncStatusUpdated(status: SyncStatus): void {
    eventInstance.emit('syncStatusUpdated', status);
  }

  versionInfoUpdated(info: VersionInfo | null): void {
    const infoCopy: VersionInfo | null = info;
    eventInstance.emit('versionInfoUpdated', JSON.stringify(infoCopy));
  }

  versionInfoIgnoreVersionUpdated(version: string): void {
    eventInstance.emit('versionInfoIgnoreVersionUpdated', version);
  }

  versionDownloadProgressUpdated(progress: number): void {
    eventInstance.emit('versionDownloadProgressUpdated', progress.toString());
  }

  componentIdsUpdated(ids: object): void {
    const idsCopy: object = ids;
    eventInstance.emit('componentIdsUpdated', JSON.stringify(idsCopy));
  }

  navActiveIdUpdated(id: string): void {
    eventInstance.emit('navActiveIdUpdated', id);
  }

  sourceNamesUpdated(names: object): void {
    const namesCopy: object = names;
    eventInstance.emit('sourceNamesUpdated', JSON.stringify(namesCopy));
  }

  on(eventName: string, listener: (data: string) => void): void {
    eventInstance.on(eventName, listener);
  }

  off(eventName: string, listener: (data: string) => void): void {
    eventInstance.off(eventName, listener);
  }
}

// 创建单例实例
export const stateEvent = new StateEventClass();

export { Progress };
