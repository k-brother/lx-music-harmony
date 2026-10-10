/**
 * 听歌识曲页（酷狗指纹单引擎）
 *
 * 移植自 RzdMusic 的 MusicRecognitionPage，按本仓约定重写：
 * - 麦克风按钮 + 环形进度一体（RzdMusic 是独立线性进度条 + 按钮，交互分散）
 * - 结果/历史行复用 ListRow + SonglistMenus 单曲菜单（下一首播放/收藏/下载/分享/不喜欢/源站详情）
 * - 历史走 service/RecognizeHistory（上限 20 + trackId 去重置顶）
 * - 播放链路：hash 直连酷狗取链，失败回退「标题+歌手」搜索补播（识别返回的 ID 不一定可播放）
 */
import { abilityAccessCtrl, common, PermissionRequestResult } from '@kit.AbilityKit';
import { appLog as hilog } from '../core/log/AppLogger';
import { DesignTokens } from '../theme/DesignTokens';
import { Breakpoints } from '../theme/Breakpoints';
import { t, tf, sourceLabel } from '../service/LocalizationService';
import { appActionMenu, appConfirm, appToast } from '../service/DialogService';
import { NavBar } from '../components/ui/NavBar';
import { ListRow } from '../components/ui/ListRow';
import { PlayerBar } from '../components/player/PlayerBar';
import { playerService } from '../service/PlayerService';
import { getMusicUrl, searchMusic, type SearchResultItem } from '../core/music/MusicFeatureEntry';
import { songRowToQueueItem } from '../core/list/SongMappers';
import { MicRecorder } from '../core/music/recognize/MicRecorder';
import { recognizeKugou } from '../core/music/recognize/KugouRecognizer';
import {
  MicCancelledError,
  MicPermissionError,
  RecognitionNetworkError,
  type RecognizedSong,
} from '../core/music/recognize/RecognitionTypes';
import { recognizeHistory } from '../service/RecognizeHistory';
import { emitSearchRequest } from '../service/EventBus';
import { hapticService } from '../service/HapticService';
import { showSongItemMenu } from './SonglistDetail/SonglistMenus';
import {
  addRowToDefaultList,
  addRowToDislike,
  downloadRow,
  openInBrowser,
  shareSongRow,
  sourceDetailUrl,
} from './SonglistDetail/SonglistRowActions';
import type { SongItem } from './SonglistDetail/SonglistTypes';
import {
  isBusy,
  recognizedToMusicInfo,
  recognizedToRow,
  statusColor,
  statusDetail,
  statusText,
  type RecognizeStatus,
} from './Recognize/RecognizeFormat';
import type { ShareResult } from '../service/ShareService';
import type { MusicInfo } from '../types/MusicTypes';

const DOMAIN = 0x0001;
const TAG = 'RecognizePage';
/** 无声门限（RMS），低于该值视为没采到有效声音 */
const RMS_THRESHOLD: number = 32 / 32768;

@Component
export struct RecognizePage {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
  @StorageProp('langVersion') langVersion: number = 0;
  @State status: RecognizeStatus = 'idle';
  @State captureProgress: number = 0;
  @State errorText: string = '';
  @State candidates: RecognizedSong[] = [];
  @State history: RecognizedSong[] = [];
  private recorder: MicRecorder = new MicRecorder();

  aboutToAppear(): void {
    void recognizeHistory.attach(this.hostContext()).then((): void => {
      this.history = recognizeHistory.getAll();
    }).catch((err: Object): void => {
      hilog.warn(DOMAIN, TAG, 'attach history failed: %{public}s', JSON.stringify(err));
    });
  }

  aboutToDisappear(): void {
    this.recorder.stop();
  }

  private hostContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  /** 状态下方的小字：采集百分比 / 可恢复错误的具体描述 */
  private async requestMicPermission(): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    try {
      const result: PermissionRequestResult =
        await atManager.requestPermissionsFromUser(this.hostContext(), ['ohos.permission.MICROPHONE']);
      return result.authResults.length > 0 && result.authResults[0] === 0;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'request mic permission failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  private async handleStart(): Promise<void> {
    if (isBusy(this.status)) {
      return;
    }
    this.status = 'requesting';
    const granted: boolean = await this.requestMicPermission();
    if (!granted) {
      this.status = 'permission_denied';
      this.errorText = '';
      return;
    }
    this.status = 'capturing';
    this.captureProgress = 0;
    this.errorText = '';
    this.candidates = [];
    hapticService.medium();
    let samples: Int16Array;
    try {
      samples = await this.recorder.capture((progress: number): void => {
        this.captureProgress = progress;
      });
    } catch (err) {
      this.handleError(err);
      return;
    }
    const rms: number = MicRecorder.computeRms(samples);
    hilog.info(DOMAIN, TAG, 'capture done samples=%{public}d rms=%{public}f', samples.length, rms);
    if (rms < RMS_THRESHOLD) {
      this.status = 'no_audio';
      return;
    }
    this.status = 'recognizing';
    try {
      const results: RecognizedSong[] = await recognizeKugou(samples);
      this.candidates = results;
      if (results.length > 0) {
        this.status = 'matched';
        hilog.info(DOMAIN, TAG, 'matched: %{public}s - %{public}s', results[0].title, results[0].artist);
        void recognizeHistory.add(results[0]);
        this.history = recognizeHistory.getAll();
      } else {
        this.status = 'not_matched';
      }
    } catch (err) {
      this.handleError(err);
    }
  }

  private handleStop(): void {
    this.recorder.stop();
    this.status = 'idle';
    this.errorText = '';
  }

  private handleError(err: Object): void {
    if (err instanceof MicCancelledError) {
      this.status = 'idle';
      this.errorText = '';
      return;
    }
    if (err instanceof MicPermissionError) {
      this.status = 'permission_denied';
      this.errorText = '';
      return;
    }
    if (err instanceof RecognitionNetworkError) {
      this.status = 'network_error';
      this.errorText = '';
      return;
    }
    this.status = 'error';
    this.errorText = err instanceof Error ? err.message : String(err);
    hilog.error(DOMAIN, TAG, 'recognize failed: %{public}s', this.errorText);
  }

  /** 识别结果 → 平台音乐对象（hash 直连酷狗取链用） */
  /**
   * 播放识别结果：hash 可直连时直接走酷狗取链；
   * 直连失败或没有 hash 时，回退按「标题+歌手」搜索酷狗补播
   * （指纹接口返回的 ID 不一定是可播放哈希）。
   */
  private async playRecognized(song: RecognizedSong): Promise<void> {
    try {
      let musicInfo: MusicInfo;
      if (song.hash.length > 0) {
        musicInfo = recognizedToMusicInfo(song);
      } else {
        const results: SearchResultItem[] = await searchMusic({
          name: `${song.title} ${song.artist}`.trim(),
          singer: null,
          source: 'kg',
          page: 1,
          limit: 10,
        });
        if (results.length === 0) {
          appToast(t('toast_no_play_url'));
          return;
        }
        const hit: SearchResultItem = results[0];
        musicInfo = {
          id: hit.id,
          name: hit.name,
          singer: hit.singer,
          source: 'kg',
          songmid: hit.songmid ?? hit.id,
          hash: hit.hash ?? '',
          albumName: hit.album,
          album: hit.album,
          interval: hit.interval,
          img: hit.pic.length > 0 ? hit.pic : null,
          pic: hit.pic.length > 0 ? hit.pic : undefined,
          lrc: null,
          types: [],
          _types: new Map(),
          typeUrl: new Map(),
          otherSource: null,
        };
      }
      const url: string | null = await getMusicUrl({
        musicInfo,
        isRefresh: false,
        onToggleSource: null,
        allowToggleSource: true,
      });
      if (!url || url.length === 0) {
        hilog.warn(DOMAIN, TAG, 'no play url for %{public}s', song.title);
        appToast(t('toast_no_play_url'));
        return;
      }
      const songInfo = songRowToQueueItem({
        id: musicInfo.id ?? '',
        name: musicInfo.name,
        singer: musicInfo.singer,
        album: musicInfo.albumName ?? '',
        duration: 0,
        source: 'kg',
        pic: musicInfo.img ?? '',
        songmid: musicInfo.songmid,
        hash: musicInfo.hash,
      });
      await playerService.playFromSelection(songInfo, url, 0);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'playRecognized failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      appToast(t('toast_operation_failed'));
    }
  }

  /** 识别结果 → 歌单行（单曲菜单用） */
  /** 长按结果/历史行：与搜索、歌单详情同一套单曲菜单 */
  private async openRowMenu(song: RecognizedSong): Promise<void> {
    await showSongItemMenu(recognizedToRow(song), {
      onPlayLater: (target: SongItem): void => {
        playerService.insertNext(songRowToQueueItem(target));
        appToast(tf('toast_play_later_added', [target.name]));
      },
      onAddToList: (target: SongItem): void => {
        void this.addToDefaultList(target);
      },
      onDownload: (target: SongItem): void => {
        void this.downloadSong(target);
      },
      onShare: (target: SongItem): void => {
        void this.shareSong(target);
      },
      onDislike: (target: SongItem): void => {
        void this.dislikeSong(target);
      },
      onSourceDetail: (target: SongItem): void => {
        if (!openInBrowser(this.hostContext(), sourceDetailUrl(target))) {
          appToast(t('toast_operation_failed'));
        }
      },
      onViewArtist: (target: SongItem): void => {
        emitSearchRequest(target.singer);
      },
      onViewAlbum: (target: SongItem): void => {
        emitSearchRequest(target.album);
      },
    }, {
      canEditPosition: false,
      canMoveToList: false,
    });
  }

  private async addToDefaultList(row: SongItem): Promise<void> {
    const error: string = await addRowToDefaultList(row);
    appToast(error.length === 0 ? tf('toast_added_to_default', [row.name]) : t('toast_operation_failed'));
  }

  private async downloadSong(row: SongItem): Promise<void> {
    const error: string = await downloadRow(row);
    appToast(error.length === 0 ? tf('toast_download_start_song', [row.name]) : t('toast_operation_failed'));
  }

  private async shareSong(row: SongItem): Promise<void> {
    const result: ShareResult = await shareSongRow(this.hostContext(), row, sourceLabel(row.source));
    if (result === 'clipboard') {
      appToast(t('toast_share_copy'));
    } else if (result === 'failed') {
      appToast(t('toast_operation_failed'));
    }
  }

  private async dislikeSong(row: SongItem): Promise<void> {
    const picked: number = await appActionMenu(t('dislike_title'), [
      t('dislike_song'),
      t('dislike_singer'),
      t('dislike_name'),
    ]);
    if (picked < 0) {
      return;
    }
    try {
      const count: number = await addRowToDislike(row, picked);
      appToast(tf('dislike_added', [count.toString()]));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'dislike failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_operation_failed'));
    }
  }

  private async clearHistory(): Promise<void> {
    // 清空是不可逆的，确认行要用危险色（与清空日志/清空历史同一套）
    const ok: boolean = await appConfirm(t('recognize_history_clear_title'), t('recognize_history_clear_msg'),
      { danger: true, confirmText: t('confirm') });
    if (!ok) {
      return;
    }
    await recognizeHistory.clear();
    this.history = [];
    appToast(t('toast_history_cleared'));
  }

  /** 麦克风主按钮：采集时外圈是进度环，按钮本体即开始/停止 */
  @Builder
  private MicButton() {
    Stack() {
      if (this.status === 'capturing') {
        Progress({ value: Math.round(this.captureProgress * 100), total: 100, type: ProgressType.Ring })
          .width(196)
          .height(196)
          .color(DesignTokens.accent())
          .backgroundColor(Color.Transparent)
      }
      Circle({ width: 148, height: 148 })
        .fill(isBusy(this.status)
          ? DesignTokens.accentSoft(this.theme)
          : (this.status === 'matched' ? DesignTokens.success() : DesignTokens.accent()))
      if (isBusy(this.status)) {
        SymbolGlyph($r('sys.symbol.mic_fill'))
          .fontSize(DesignTokens.fontDisplayXl())
          .fontColor([DesignTokens.accent()])
      } else {
        SymbolGlyph($r('sys.symbol.mic'))
          .fontSize(DesignTokens.fontDisplayXl())
          .fontColor([DesignTokens.onAccent()])
      }
    }
    .width(200)
    .height(200)
    .accessibilityText(t('a11y_recognize'))
    .onClick(() => {
      if (this.status === 'capturing') {
        this.handleStop();
      } else if (!isBusy(this.status)) {
        void this.handleStart();
      }
    })
  }

  /** 结果/历史共用的一行 */
  @Builder
  private SongRow(song: RecognizedSong, active: boolean, divider: boolean) {
    ListRow({
      title: song.title,
      singer: song.artist,
      album: song.album,
      sourceId: 'kg',
      cover: song.coverUrl,
      showIndex: false,
      active,
      divider,
      onTap: (): void => {
        void this.playRecognized(song);
      },
      onLongPress: (): void => {
        void this.openRowMenu(song);
      },
    })
  }

  build() {
    Column() {
      NavBar({ title: t('recognize_title') })

      Scroll() {
        Column({ space: DesignTokens.spaceGutter() }) {
          Column({ space: 10 }) {
            this.MicButton()

            Text(statusText(this.status))
              .fontSize(DesignTokens.fontTitle())
              .fontWeight(FontWeight.Medium)
              .fontColor(statusColor(this.status, this.theme))

            if (statusDetail(this.status, this.captureProgress, this.errorText).length > 0) {
              Text(statusDetail(this.status, this.captureProgress, this.errorText))
                .fontSize(DesignTokens.fontCaption())
                .fontColor(this.status === 'capturing'
                  ? DesignTokens.labelSecondary(this.theme)
                  : DesignTokens.danger())
                .padding({ left: 32, right: 32 })
                .textAlign(TextAlign.Center)
            }
          }
          .width('100%')
          .padding({ top: 28, bottom: 10 })

          if (this.candidates.length > 0 && this.status === 'matched') {
            Column({ space: 2 }) {
              ForEach(this.candidates, (song: RecognizedSong, index: number) => {
                this.SongRow(song, index === 0, index < this.candidates.length - 1)
              }, (song: RecognizedSong) => song.id)
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
            .borderRadius(DesignTokens.radiusCard())
            .backgroundColor(DesignTokens.card(this.theme))
          }

          // 识别历史
          Column({ space: 2 }) {
            Row() {
              Text(t('recognize_history'))
                .fontSize(DesignTokens.fontTitle())
                .fontWeight(FontWeight.Medium)
                .fontColor(DesignTokens.labelPrimary(this.theme))
                .layoutWeight(1)
              if (this.history.length > 0) {
                Text(t('history_clear'))
                  .fontSize(DesignTokens.fontCaption())
                  .fontColor(DesignTokens.danger())
                  .padding({ top: 12, bottom: 12, left: 16, right: 16 })
                  .onClick(() => {
                    void this.clearHistory();
                  })
              }
            }
            .width('100%')
            .height(DesignTokens.rowHeight())
            .alignItems(VerticalAlign.Center)

            if (this.history.length === 0) {
              Text(t('recognize_history_empty'))
                .fontSize(DesignTokens.fontCaption())
                .fontColor(DesignTokens.labelTertiary(this.theme))
                .width('100%')
                .padding({ top: 14, bottom: 18 })
            } else {
              ForEach(this.history, (song: RecognizedSong, index: number) => {
                this.SongRow(song, false, index < this.history.length - 1)
              }, (song: RecognizedSong) => song.id)
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .borderRadius(DesignTokens.radiusCard())
          .backgroundColor(DesignTokens.card(this.theme))
          .margin({ bottom: 20 })
        }
        .width('100%')
        .padding({
          left: Breakpoints.contentInset(this.windowWidthVp),
          right: Breakpoints.contentInset(this.windowWidthVp),
          top: DesignTokens.spaceGutter(),
        })
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      PlayerBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
