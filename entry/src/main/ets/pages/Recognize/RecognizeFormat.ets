/**
 * 听歌识曲的展示与转换（纯函数，从 RecognizePage 抽出）
 *
 * 抽出来的理由：这些逻辑与页面状态无关（只吃 status / 进度 / 识别结果），
 * 却占了页面近三分之一行数，混在 UI 里既难复用也难读。
 * 放在页面层（而不是 core）是因为 `SongItem` 是歌单详情页的行类型。
 */
import { t, tf } from '../../service/LocalizationService';
import { DesignTokens } from '../../theme/DesignTokens';
import type { MusicInfo, MusicSource } from '../../types/MusicTypes';
import type { SongItem } from '../SonglistDetail/SonglistTypes';
import type { RecognizedSong } from '../../core/music/recognize/RecognitionTypes';

/** 指纹识别走酷狗接口，识别结果一律按 kg 源落库/入库 */
const RECOGNIZED_SOURCE: MusicSource = 'kg';

/** 识别流程状态（页面与格式化函数共用；从 RecognizePage 移到这里） */
export type RecognizeStatus =
  | 'idle'
  | 'requesting'
  | 'capturing'
  | 'recognizing'
  | 'matched'
  | 'not_matched'
  | 'no_audio'
  | 'permission_denied'
  | 'network_error'
  | 'error';

export function isBusy(status: RecognizeStatus): boolean {
  return status === 'requesting' || status === 'capturing' || status === 'recognizing';
}

export function statusText(status: RecognizeStatus): string {
  switch (status) {
    case 'idle':
      return t('recognize_ready');
    case 'requesting':
      return t('recognize_requesting');
    case 'capturing':
      return t('recognize_listening');
    case 'recognizing':
      return t('recognize_recognizing');
    case 'matched':
      return t('recognize_matched');
    case 'not_matched':
      return t('recognize_not_matched');
    case 'no_audio':
      return t('recognize_no_audio');
    case 'permission_denied':
      return t('recognize_permission_denied');
    case 'network_error':
      return t('recognize_network_error');
    default:
      return t('recognize_error');
  }
}

export function statusColor(status: RecognizeStatus, theme: string): string {
  if (status === 'matched') {
    return DesignTokens.success();
  }
  if (status === 'no_audio' || status === 'permission_denied'
    || status === 'network_error' || status === 'error') {
    return DesignTokens.danger();
  }
  return DesignTokens.labelSecondary(theme);
}

/** 状态下方的小字：采集百分比 / 可恢复错误的具体描述 */
export function statusDetail(status: RecognizeStatus, captureProgress: number, errorText: string): string {
  if (status === 'capturing') {
    return tf('recognize_capture_progress', [Math.round(captureProgress * 100).toString()]);
  }
  if (status === 'permission_denied') {
    return t('recognize_permission_hint');
  }
  if (status === 'no_audio') {
    return t('recognize_no_audio_hint');
  }
  if (errorText.length > 0) {
    return errorText;
  }
  return '';
}

/** 识别结果 → 平台音乐对象（取链、入库、评论等走这套元数据） */
export function recognizedToMusicInfo(song: RecognizedSong): MusicInfo {
  const cover: string = song.coverUrl;
  return {
    id: song.trackId,
    name: song.title,
    singer: song.artist,
    source: RECOGNIZED_SOURCE,
    songmid: song.hash.length > 0 ? song.hash : song.trackId,
    hash: song.hash,
    albumName: song.album,
    album: song.album,
    interval: null,
    img: cover.length > 0 ? cover : null,
    pic: cover.length > 0 ? cover : undefined,
    lrc: null,
    types: [],
    _types: new Map(),
    typeUrl: new Map(),
    otherSource: null,
  };
}

/** 识别结果 → 歌单行（单曲菜单用） */
export function recognizedToRow(song: RecognizedSong): SongItem {
  return {
    id: song.trackId,
    name: song.title,
    singer: song.artist,
    album: song.album,
    duration: 0,
    source: RECOGNIZED_SOURCE,
    pic: song.coverUrl,
    songmid: song.hash.length > 0 ? song.hash : song.trackId,
    hash: song.hash,
    isPlaying: false,
  };
}
