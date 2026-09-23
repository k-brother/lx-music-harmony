/**
 * 播放事件订阅中心
 *
 * PlayerService 里原先有 6 组「listener 数组 + 订阅方法 + 广播方法」，
 * 每组写法一致却各写一遍（约 150 行）。通用订阅器已收敛到 service/EventChannel：
 * 新增一种事件只需一行声明，广播也自动做了「单个订阅者异常不影响其他人」。
 */
import { EventChannel } from '../EventChannel';
import type { MusicInfo } from '../../types/MusicTypes';
import type { PlayStatus, ProgressInfo } from './PlaybackTypes';

const DOMAIN = 0x0002;
const TAG = 'PlaybackEvents';

/** 当前状态（idle/playing/...） */
export type StateChangeListener = (status: PlayStatus) => void;
/** 播放/暂停 */
export type PlayStateListener = (isPlay: boolean) => void;
/** 播放进度（秒） */
export type ProgressListener = (position: number, duration: number) => void;
/** 当前歌曲信息变化 */
export type MusicInfoListener = (info: MusicInfo) => void;
/** 整首播完 */
export type TrackCompletedListener = () => void;
/** 进度信息变化（节流后的完整快照） */
export type ProgressInfoListener = (progress: ProgressInfo) => void;

/**
 * 播放事件中心
 *
 * 用法：`playerEvents.state.emit((l) => l(status))`
 */
class PlaybackEventHub {
  readonly state: EventChannel<StateChangeListener> = new EventChannel('state');
  readonly playState: EventChannel<PlayStateListener> = new EventChannel('playState');
  readonly progress: EventChannel<ProgressListener> = new EventChannel('progress');
  readonly musicInfo: EventChannel<MusicInfoListener> = new EventChannel('musicInfo');
  readonly trackCompleted: EventChannel<TrackCompletedListener> = new EventChannel('trackCompleted');
  readonly progressInfo: EventChannel<ProgressInfoListener> = new EventChannel('progressInfo');

  /** 页面销毁/服务重建时清空所有订阅，避免悬挂回调 */
  clearAll(): void {
    this.state.clear();
    this.playState.clear();
    this.progress.clear();
    this.musicInfo.clear();
    this.trackCompleted.clear();
    this.progressInfo.clear();
  }
}

export const playbackEvents = new PlaybackEventHub();
