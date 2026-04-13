// Player Store Action - 对应 src/store/player/action.ts
// 播放器状态操作 - 使用 ArkTS 兼容语法

import { formatPlayTime } from '../utils/CommonUtils';
import { playerState } from './PlayerStoreState';
import { stateEvent } from '../event/StateEvent';
import { MusicInfo, PlayMusicInfo, PlayInfo, Progress, MusicSource } from '../types/MusicTypes';

// 创建进度对象副本
function createProgressCopy(progress: Progress): Progress {
  const progressCopy: Progress = {
    nowPlayTime: progress.nowPlayTime,
    maxPlayTime: progress.maxPlayTime,
    progress: progress.progress,
    nowPlayTimeStr: progress.nowPlayTimeStr,
    maxPlayTimeStr: progress.maxPlayTimeStr
  } as Progress;
  return progressCopy;
}

// 创建播放信息对象副本
function createPlayInfoCopy(playInfo: PlayInfo): PlayInfo {
  const playInfoCopy: PlayInfo = {
    playIndex: playInfo.playIndex,
    playerListId: playInfo.playerListId,
    playerPlayIndex: playInfo.playerPlayIndex
  } as PlayInfo;
  return playInfoCopy;
}

// 创建播放音乐信息对象副本
function createPlayMusicInfoCopy(playMusicInfo: PlayMusicInfo): PlayMusicInfo {
  const playMusicInfoCopy: PlayMusicInfo = {
    listId: playMusicInfo.listId,
    musicInfo: playMusicInfo.musicInfo,
    isTempPlay: playMusicInfo.isTempPlay
  } as PlayMusicInfo;
  return playMusicInfoCopy;
}

// 创建音乐信息对象副本
function createMusicInfoCopy(musicInfo: MusicInfo): MusicInfo {
  const musicInfoCopy: MusicInfo = {
    id: musicInfo.id,
    name: musicInfo.name,
    singer: musicInfo.singer,
    source: musicInfo.source,
    interval: musicInfo.interval,
    img: musicInfo.img,
    lrc: musicInfo.lrc,
    types: musicInfo.types,
    _types: musicInfo._types,
    typeUrl: musicInfo.typeUrl,
    otherSource: musicInfo.otherSource,
    songmid: musicInfo.songmid,
    albumId: musicInfo.albumId,
    albumName: musicInfo.albumName,
    hash: musicInfo.hash,
    strMediaMid: musicInfo.strMediaMid,
    songId: musicInfo.songId,
    albumMid: musicInfo.albumMid,
    copyrightId: musicInfo.copyrightId,
  } as MusicInfo;
  return musicInfoCopy;
}

// 更新播放索引
export function updatePlayIndex(playIndex: number, playerPlayIndex: number): void {
  playerState.playInfo.playIndex = playIndex;
  playerState.playInfo.playerPlayIndex = playerPlayIndex;
  const playInfoCopy = createPlayInfoCopy(playerState.playInfo);
  stateEvent.playInfoChanged(playInfoCopy);
}

// 设置播放列表ID
export function setPlayListId(playerListId: string | null): void {
  playerState.playInfo.playerListId = playerListId;
  const playInfoCopy = createPlayInfoCopy(playerState.playInfo);
  stateEvent.playInfoChanged(playInfoCopy);
}

// 设置播放音乐信息
export function setPlayMusicInfo(listId: string | null, musicInfo: MusicInfo | null, isTempPlay: boolean = false): void {
  playerState.playMusicInfo.listId = listId;
  playerState.playMusicInfo.musicInfo = musicInfo;
  playerState.playMusicInfo.isTempPlay = isTempPlay;
  const playMusicInfoCopy = createPlayMusicInfoCopy(playerState.playMusicInfo);
  stateEvent.playMusicInfoChanged(playMusicInfoCopy);
}

// 设置音乐信息
export function setMusicInfo(name: string = '', singer: string = '', img: string | null = null, lrc: string | null = null, source: MusicSource = 'kw'): void {
  if (name !== '') playerState.musicInfo.name = name;
  if (singer !== '') playerState.musicInfo.singer = singer;
  if (img !== null) playerState.musicInfo.img = img;
  if (lrc !== null) playerState.musicInfo.lrc = lrc;
  if (source !== 'kw') playerState.musicInfo.source = source;

  const musicInfoCopy = createMusicInfoCopy(playerState.musicInfo);
  stateEvent.playerMusicInfoChanged(musicInfoCopy);
}

// 设置播放状态
export function setIsPlay(isPlay: boolean): void {
  playerState.isPlay = isPlay;
  stateEvent.playStateChanged(isPlay);
}

// 设置状态文本
export function setStatusText(statusText: string): void {
  playerState.statusText = statusText;
  stateEvent.playStateTextChanged(statusText);
}

// 设置当前播放时间
export function setNowPlayTime(time: number): void {
  playerState.progress.nowPlayTime = time;
  playerState.progress.nowPlayTimeStr = formatPlayTime(time);
  playerState.progress.progress = playerState.progress.maxPlayTime ? time / playerState.progress.maxPlayTime : 0;
  const progressCopy = createProgressCopy(playerState.progress);
  stateEvent.playProgressChanged(progressCopy);
}

// 设置最大播放时间
export function setMaxplayTime(time: number): void {
  playerState.progress.maxPlayTime = time;
  playerState.progress.maxPlayTimeStr = formatPlayTime(time);
  playerState.progress.progress = time ? playerState.progress.nowPlayTime / time : 0;
  const progressCopy = createProgressCopy(playerState.progress);
  stateEvent.playProgressChanged(progressCopy);
}

// 设置进度
export function setProgress(currentTime: number, totalTime: number): void {
  playerState.progress.nowPlayTime = currentTime;
  playerState.progress.nowPlayTimeStr = formatPlayTime(currentTime);
  playerState.progress.maxPlayTime = totalTime;
  playerState.progress.maxPlayTimeStr = formatPlayTime(totalTime);
  playerState.progress.progress = totalTime ? currentTime / totalTime : 0;
  const progressCopy = createProgressCopy(playerState.progress);
  stateEvent.playProgressChanged(progressCopy);
}

// 添加已播放列表
export function addPlayedList(info: PlayMusicInfo): void {
  let exists = false;
  for (const m of playerState.playedList) {
    if (m.musicInfo && info.musicInfo && m.musicInfo.id === info.musicInfo.id) {
      exists = true;
      break;
    }
  }
  if (!exists) {
    playerState.playedList.push(info);
    const playedListCopy: PlayMusicInfo[] = [...playerState.playedList];
    stateEvent.playPlayedListChanged(playedListCopy);
  }
}

// 移除已播放列表项
export function removePlayedList(index: number): void {
  playerState.playedList.splice(index, 1);
  const playedListCopy: PlayMusicInfo[] = [...playerState.playedList];
  stateEvent.playPlayedListChanged(playedListCopy);
}

// 清空已播放列表
export function clearPlayedList(): void {
  playerState.playedList = [];
  const playedListCopy: PlayMusicInfo[] = [];
  stateEvent.playPlayedListChanged(playedListCopy);
}

// 添加临时播放列表
export function addTempPlayList(list: PlayMusicInfo[]): void {
  for (const item of list) {
    playerState.tempPlayList.push(item);
  }
  const tempPlayListCopy: PlayMusicInfo[] = [...playerState.tempPlayList];
  stateEvent.playTempPlayListChanged(tempPlayListCopy);
}

// 移除临时播放列表项
export function removeTempPlayList(index: number): void {
  playerState.tempPlayList.splice(index, 1);
  const tempPlayListCopy: PlayMusicInfo[] = [...playerState.tempPlayList];
  stateEvent.playTempPlayListChanged(tempPlayListCopy);
}

// 清空临时播放列表
export function clearTempPlayList(): void {
  playerState.tempPlayList = [];
  const tempPlayListCopy: PlayMusicInfo[] = [];
  stateEvent.playTempPlayListChanged(tempPlayListCopy);
}

// 设置加载错误图片URL
export function setLoadErrorPicUrl(url: string): void {
  playerState.loadErrorPicUrl = url;
}

// 设置最后歌词
export function setLastLyric(lrc: string | null = null): void {
  playerState.lastLyric = lrc;
}
