/**
 * 播放相关的公共类型
 *
 * 单独成文件是为了打破循环依赖：PlaybackEvents（订阅中心）需要 PlayStatus/ProgressInfo，
 * 而 PlayerService 又要用订阅中心；类型独立后两边都能安全引用。
 * PlayerService 继续 re-export 这些类型，调用方 import 路径不变。
 */

/** 播放状态 */
export type PlayStatus = 'idle' | 'loading' | 'playing' | 'paused' | 'stopped' | 'buffering' | 'error';

/** 进度信息（播放页进度条、播控中心都用它） */
export interface ProgressInfo {
  nowPlayTime: number;
  maxPlayTime: number;
  progress: number;
  nowPlayTimeStr: string;
  maxPlayTimeStr: string;
}
