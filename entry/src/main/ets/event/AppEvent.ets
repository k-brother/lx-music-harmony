// AppEvent - 对应 src/event/appEvent.ts
// 应用相关事件 - ArkTS 兼容版本

import { eventInstance } from './Event';

// 搜索类型
export type SearchType = 'music' | 'songlist';

// 歌单来源
export type SonglistSource = 'kw' | 'tx' | 'mg' | 'wy';

// 歌单标签信息接口
interface SonglistTagInfo {
  source: SonglistSource;
  activeId: string;
}

// 进度数据接口
interface ProgressData {
  progress: number;
  maxPlayTime: number | null;
}

// 标签信息接口
interface TagInfo {
  name: string;
  id: string;
}

// AppEvent类实现
export class AppEventClass {

  focus(): void {
    eventInstance.emit('focus', '');
  }

  mylistUpdated(lists: object[]): void {
    const listArray: object[] = lists;
    eventInstance.emit('mylistUpdated', JSON.stringify(listArray));
  }

  mylistToggled(id: string): void {
    const idString: string = id;
    eventInstance.emit('listToggled', idString);
  }

  musicToggled(): void {
    eventInstance.emit('musicToggled', '');
  }

  setProgress(progress: number, maxPlayTime: number | null = null): void {
    const progressData: ProgressData = { progress: progress, maxPlayTime: maxPlayTime };
    eventInstance.emit('setProgress', JSON.stringify(progressData));
  }

  setVolume(volume: number): void {
    eventInstance.emit('setVolume', volume.toString());
  }

  setVolumeIsMute(isMute: boolean): void {
    eventInstance.emit('setVolumeIsMute', isMute.toString());
  }

  play(): void {
    eventInstance.emit('play', '');
  }

  pause(): void {
    eventInstance.emit('pause', '');
  }

  stop(): void {
    eventInstance.emit('stop', '');
  }

  error(): void {
    eventInstance.emit('error', '');
  }

  playerPlaying(): void {
    eventInstance.emit('playerPlaying', '');
  }

  playerPause(): void {
    eventInstance.emit('playerPause', '');
  }

  playerEnded(): void {
    eventInstance.emit('playerEnded', '');
  }

  playerError(): void {
    eventInstance.emit('playerError', '');
  }

  playerLoadstart(): void {
    eventInstance.emit('playerLoadstart', '');
  }

  playerEmptied(): void {
    eventInstance.emit('playerEmptied', '');
  }

  playerWaiting(): void {
    eventInstance.emit('playerWaiting', '');
  }

  picUpdated(): void {
    eventInstance.emit('picUpdated', '');
  }

  lyricUpdated(): void {
    eventInstance.emit('lyricUpdated', '');
  }

  lyricOffsetUpdate(): void {
    eventInstance.emit('lyricOffsetUpdate', '');
  }

  myListMusicUpdate(ids: string[]): void {
    if (!ids.length) return;
    const idArray: string[] = ids;
    eventInstance.emit('myListMusicUpdate', JSON.stringify(idArray));
  }

  downloadListUpdate(): void {
    eventInstance.emit('downloadListUpdate', '');
  }

  musicInfoUpdate(musicInfo: object): void {
    const musicInfoCopy: object = musicInfo;
    eventInstance.emit('musicInfoUpdate', JSON.stringify(musicInfoCopy));
  }

  changeMenuVisible(visible: boolean): void {
    eventInstance.emit('changeMenuVisible', visible.toString());
  }

  searchTypeChanged(type: SearchType): void {
    eventInstance.emit('searchTypeChanged', type);
  }

  jumpListPosition(): void {
    eventInstance.emit('jumpListPosition', '');
  }

  changeLoveListVisible(visible: boolean): void {
    eventInstance.emit('changeLoveListVisible', visible.toString());
  }

  showSonglistTagList(source: SonglistSource, activeId: string): void {
    const tagInfo: SonglistTagInfo = { source, activeId };
    eventInstance.emit('showSonglistTagList', JSON.stringify(tagInfo));
  }

  hideSonglistTagList(): void {
    eventInstance.emit('hideSonglistTagList', '');
  }

  songlistTagInfoChange(name: string, id: string): void {
    const tagInfo: TagInfo = { name: name, id: id };
    eventInstance.emit('songlistTagInfoChange', JSON.stringify(tagInfo));
  }

  selectSyncMode(mode: string): void {
    eventInstance.emit('selectSyncMode', mode);
  }

  on(eventName: string, listener: (data: string) => void): void {
    eventInstance.on(eventName, listener);
  }

  off(eventName: string, listener: (data: string) => void): void {
    eventInstance.off(eventName, listener);
  }
}

// 创建单例实例
export const appEvent = new AppEventClass();
