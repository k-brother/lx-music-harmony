/**
 * 系统播控（AVSession）适配层
 *
 * 从 PlayerService 抽出：这一层只做「播放器 ↔ 系统播控中心」的翻译
 * —— 元数据怎么拼、循环模式怎么映射、系统下发的命令怎么落到播放器动作。
 * 之前混在播放服务里（1500 行），找一个「锁屏点下一首为什么不生效」要翻半天。
 *
 * 与播放器的耦合通过 `PlaybackSessionHost` 反向注入：本模块不认识 PlayerService，
 * 播放服务实现这 8 个动作即可，系统播控的命令全部经由这里转调。
 */
import { avSession } from '@kit.AVSessionKit';
import { appLog as hilog } from '../../core/log/AppLogger';
import { toggleLoveList, type MusicItem } from '../ListService';
import type { AvMediaMetadata, AvSessionCallbacks } from '../BackgroundRunningManager';
import type { PlayMode } from '../SettingsService';
import type { MusicInfo } from '../../types/MusicTypes';
import { t } from '../LocalizationService';
import { asText, asNumber } from '../../utils/ValueCoerce';
import type { SongInfo } from '../PlayerService';

const TAG = 'PlaybackSession';
const DOMAIN: number = 0x0001;

/** 播放器需要提供给播控层的动作 */
export interface PlaybackSessionHost {
  play: () => Promise<void>;
  pause: () => Promise<void>;
  stop: () => Promise<void>;
  playNext: () => Promise<void>;
  playPrev: () => Promise<void>;
  /** 秒 */
  seekTo: (seconds: number) => Promise<void>;
  getPlayMode: () => PlayMode;
  setPlayMode: (mode: PlayMode) => void;
  cyclePlayMode: () => PlayMode;
  getCurrentSong: () => SongInfo | null;
}

/** 应用播放模式 → 系统循环模式 */
export function playModeToAvLoopMode(mode: PlayMode): avSession.LoopMode {
  switch (mode) {
    case 'singleLoop':
      return avSession.LoopMode.LOOP_MODE_SINGLE;
    case 'random':
      return avSession.LoopMode.LOOP_MODE_SHUFFLE;
    case 'sequential':
      return avSession.LoopMode.LOOP_MODE_SEQUENCE;
    default:
      return avSession.LoopMode.LOOP_MODE_LIST;
  }
}

/** 系统循环模式 → 应用播放模式 */
export function avLoopModeToPlayMode(mode: avSession.LoopMode): PlayMode {
  switch (mode) {
    case avSession.LoopMode.LOOP_MODE_SINGLE:
      return 'singleLoop';
    case avSession.LoopMode.LOOP_MODE_SHUFFLE:
      return 'random';
    case avSession.LoopMode.LOOP_MODE_SEQUENCE:
      return 'sequential';
    default:
      return 'listLoop';
  }
}

/** 拼装播控元数据的输入 */
export interface AvMetadataInput {
  musicInfo: MusicInfo;
  /** 当前已知总时长（秒），未知时用 0 */
  durationSeconds: number;
}

/**
 * 拼装系统播控元数据。
 * 注意 assetId 不能为空（官方要求），否则 setAVMetadata 会失败；
 * duration 必须是正数，未知时长兜底 1 秒。
 *
 * assetId/title/artist/album 必须强制成字符串：源 JSON 的 id/songmid 可能是数字
 * （酷狗 Audioid、酷我 id、咪咕 songId），非字符串会被系统播控直接拒收——
 * 日志：`[GetAssetId] test (status == napi_ok) failed` → `Failed to set AVMetadata`，
 * 真机表现就是「这首歌没有接入灵动岛/胶囊，其它歌正常」。
 */
export function buildAvMetadata(input: AvMetadataInput): AvMediaMetadata {
  const info = input.musicInfo;
  const imgUrl: string = asText(info.pic, asText(info.img));
  const assetId: string = asText(info.id, asText(info.songmid, `track_${Date.now()}`));
  const metadata: AvMediaMetadata = {
    assetId: assetId,
    // 锁屏/控制中心会直接展示这两个兜底文案，必须跟随语言
    title: asText(info.name, t('unknown_song')),
    artist: asText(info.singer, t('unknown_artist')),
    album: asText(info.albumName, asText(info.album)),
    duration: Math.max(asNumber(input.durationSeconds, 0), 1) * 1000,
  };
  if (imgUrl.length > 0) {
    metadata.mediaImage = imgUrl;
  }
  return metadata;
}

/** 系统播控命令 → 播放器动作 */
export function createAvSessionCallbacks(host: PlaybackSessionHost): AvSessionCallbacks {
  const handleErr = (action: string, err: Error): void => {
    hilog.error(DOMAIN, TAG, 'AVSession %{public}s failed: %{public}s', action, err.message || 'unknown');
  };
  return {
    onPlay: (): void => {
      host.play().catch((err: Error) => handleErr('play', err));
    },
    onPause: (): void => {
      host.pause().catch((err: Error) => handleErr('pause', err));
    },
    onStop: (): void => {
      host.stop().catch((err: Error) => handleErr('stop', err));
    },
    onPlayNext: (): void => {
      host.playNext().catch((err: Error) => handleErr('playNext', err));
    },
    onPlayPrevious: (): void => {
      host.playPrev().catch((err: Error) => handleErr('playPrev', err));
    },
    onSeek: (positionMs: number): void => {
      host.seekTo(positionMs / 1000).catch((err: Error) => handleErr('seek', err));
    },
    onSetLoopMode: (loopMode: avSession.LoopMode): void => {
      // 播控中心传来的 mode 是「当前」状态：与本地一致时切到下一个模式，否则直接同步
      const currentAvMode = playModeToAvLoopMode(host.getPlayMode());
      if (currentAvMode === loopMode) {
        host.cyclePlayMode();
      } else {
        host.setPlayMode(avLoopModeToPlayMode(loopMode));
      }
    },
    onToggleFavorite: (_assetId: string): void => {
      const currentSong = host.getCurrentSong();
      if (!currentSong) {
        hilog.warn(DOMAIN, TAG, 'Toggle favorite: no current song');
        return;
      }
      const musicItem: MusicItem = {
        id: currentSong.id,
        name: currentSong.title,
        singer: currentSong.artist,
        album: currentSong.album,
        albumId: currentSong.albumId || null,
        duration: currentSong.duration,
        source: currentSong.source || 'kw',
        pic: currentSong.artwork || '',
        lrc: null,
      };
      toggleLoveList(musicItem).then((isLoved: boolean): void => {
        hilog.info(DOMAIN, TAG, 'Toggle favorite: %{public}s is now %{public}s',
          currentSong.title, isLoved ? 'loved' : 'unloved');
      }).catch((err: Error): void => {
        hilog.error(DOMAIN, TAG, 'Toggle favorite failed: %{public}s', err.message);
      });
    },
  };
}
