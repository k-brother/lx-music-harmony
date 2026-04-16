import hilog from '@ohos.hilog';
import { navigationService } from '../service/NavigationService';
import { playerService, SongInfo } from '../service/PlayerService';
import { getMusicUrl } from '../core/music/MusicFeatureEntry';
import { getPlayHistory, clearPlayHistory, PlayHistoryItem } from '../service/PlayHistoryService';
import type { MusicInfo as AppMusicInfo, MusicSource } from '../types/MusicTypes';
import { formatPlayTime } from '../utils/CommonUtils';
import { DesignTokens } from '../theme/DesignTokens';

interface PromptActionResult {
  index: number;
}

@Component
export struct HistoryListPage {
  @StorageProp('theme') theme: string = 'light';
  @State isLoading: boolean = false;
  @State playHistory: PlayHistoryItem[] = [];

  aboutToAppear() {
    void this.loadHistory();
  }

  private async loadHistory(): Promise<void> {
    this.isLoading = true;
    try {
      this.playHistory = await getPlayHistory(120);
    } catch (err) {
      hilog.warn(0x0001, 'HistoryListPage', 'loadHistory failed: %{public}s', JSON.stringify(err));
      this.playHistory = [];
    } finally {
      this.isLoading = false;
    }
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    } catch (_e) {
      hilog.info(0x0001, 'HistoryListPage', '%{public}s', msg);
    }
  }

  private async clearHistoryWithConfirm(): Promise<void> {
    try {
      const confirmed = await new Promise<boolean>((resolve) => {
        this.getUIContext().getPromptAction().showDialog({
          title: '清空试听列表',
          message: '确认清空最近听过的歌曲记录？',
          buttons: [
            { text: '取消', color: DesignTokens.labelSecondary(this.theme) },
            { text: '确定', color: DesignTokens.accent() },
          ],
        }, (_err: object, data: PromptActionResult) => {
          resolve(data.index === 1);
        });
      });
      if (!confirmed) {
        return;
      }
      await clearPlayHistory();
      this.playHistory = [];
      this.toast('已清空试听列表');
    } catch (e) {
      hilog.warn(0x0001, 'HistoryListPage', 'clear history failed: %{public}s', JSON.stringify(e));
      this.toast('清空失败');
    }
  }

  private async playHistorySong(song: PlayHistoryItem): Promise<void> {
    try {
      const musicInfo: AppMusicInfo = {
        id: song.id,
        name: song.name,
        singer: song.singer,
        source: song.source as MusicSource,
        songmid: song.songmid || song.id,
        interval: formatPlayTime(song.duration),
        img: song.pic || null,
        pic: song.pic || undefined,
        lrc: null,
        albumName: song.album || '',
        album: song.album || '',
        albumId: '',
        hash: '',
        types: [],
        _types: new Map(),
        typeUrl: new Map(),
        otherSource: null,
      };
      const url: string | null = await getMusicUrl({
        musicInfo,
        quality: '128k',
        isRefresh: false,
        allowToggleSource: true,
      });
      if (!url) {
        this.toast('无法获取播放链接');
        return;
      }
      const songInfo: SongInfo = {
        id: song.id,
        url,
        title: song.name,
        artist: song.singer,
        album: song.album || '',
        artwork: song.pic || null,
        duration: song.duration,
        source: song.source,
      };
      playerService.setPlayList([songInfo], 0);
      await playerService.setSource(songInfo, url, song.duration);
      await playerService.play();
    } catch (error) {
      hilog.error(0x0001, 'HistoryListPage', 'play history song failed: %{public}s', JSON.stringify(error));
      this.toast('播放失败');
    }
  }

  @Builder
  private Header() {
    Row() {
      Stack() {
        Circle({ width: 34, height: 34 })
          .fill(DesignTokens.mutedFill(this.theme))
        Image($r('app.media.ic_pd_back'))
          .width(16)
          .height(16)
          .fillColor(DesignTokens.labelPrimary(this.theme))
      }
      .onClick(() => {
        navigationService.back();
      })

      Text('试听列表')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .margin({ left: 12 })
        .layoutWeight(1)

      if (this.playHistory.length > 0) {
        Text('清空')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.accent())
          .padding({ left: 8, right: 4, top: 6, bottom: 6 })
          .onClick(() => {
            void this.clearHistoryWithConfirm();
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
    .backgroundColor(DesignTokens.chromeBar(this.theme))
  }

  @Builder
  private SongRow(song: PlayHistoryItem, index: number) {
    Row() {
      Text((index + 1).toString())
        .fontSize(12)
        .fontColor(DesignTokens.labelTertiary(this.theme))
        .width(24)
        .textAlign(TextAlign.Center)

      Column() {
        Text(song.name)
          .fontSize(16)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(song.singer + (song.album ? ` · ${song.album}` : ''))
          .fontSize(12)
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8, right: 8 })

      Stack() {
        Circle({ width: 30, height: 30 })
          .fill(DesignTokens.mutedFill(this.theme))
        Image($r('app.media.ic_pd_play'))
          .width(12)
          .height(12)
          .fillColor(DesignTokens.accent())
          .margin({ left: 1 })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
    .onClick(() => {
      void this.playHistorySong(song);
    })
  }

  build() {
    Column() {
      this.Header()

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(DesignTokens.accent())
          Text('正在读取试听列表…')
            .fontSize(14)
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .margin({ top: 12 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.playHistory.length === 0) {
        Column() {
          Text('暂无试听记录')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.labelSecondary(this.theme))
          Text('播放过的歌曲会出现在这里')
            .fontSize(13)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ space: 10 }) {
          ForEach(this.playHistory, (song: PlayHistoryItem, index: number) => {
            ListItem() {
              this.SongRow(song, index)
            }
            .padding({ left: 16, right: 16 })
          }, (song: PlayHistoryItem, index: number) => `${song.id}_${song.source}_${song.playedAt}_${index}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ top: 10, bottom: 20 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }
}
