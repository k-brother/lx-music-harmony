/**
 * 系统播控的类型定义
 *
 * 从 BackgroundRunningManager 抽出：`AvMediaMetadata`（播控中心显示的元数据）与
 * `AvSessionCallbacks`（系统下发的操作回调）被播控服务、命令注册器与播放服务共用，
 * 单独成文件避免「注册器要 import 服务、服务又 import 注册器」的循环。
 */
import { avSession } from '@kit.AVSessionKit';

/** 媒体元数据（用于播控中心/锁屏显示） */
export interface AvMediaMetadata {
  assetId: string;
  title: string;
  artist: string;
  album?: string;
  /** 毫秒 */
  duration: number;
  /** 封面（播控中心要求 URL string 或 PixelMap，直接传 string 即可） */
  mediaImage?: string;
  /** 标准 LRC 歌词全文（系统播控中心/锁屏据此显示歌词） */
  lyric?: string;
  /** 当前这一句歌词（不含时间前缀），用于灵动岛/胶囊的单行歌词展示 */
  singleLyricText?: string;
}

/** 系统播控命令回调（由播放服务实现） */
export interface AvSessionCallbacks {
  onPlay: () => void;
  onPause: () => void;
  onStop: () => void;
  onPlayNext: () => void;
  onPlayPrevious: () => void;
  onSeek: (positionMs: number) => void;
  onSetLoopMode: (loopMode: avSession.LoopMode) => void;
  onToggleFavorite: (assetId: string) => void;
}
