/**
 * 播放历史页
 *
 * 重构后：统一使用 UI Kit（NavBar / ListRow / StateView）+ DialogService，
 * 页面只保留数据加载与播放逻辑，视觉与其它列表页完全一致。
 */
import hilog from '@ohos.hilog';
import { playerService, SongInfo } from '../service/PlayerService';
import { getMusicUrl } from '../core/music/MusicFeatureEntry';
import { getPlayHistory, clearPlayHistory, PlayHistoryItem } from '../service/PlayHistoryService';
import type { MusicInfo as AppMusicInfo, MusicSource } from '../types/MusicTypes';
import { formatPlayTime } from '../utils/CommonUtils';
import { DesignTokens } from '../theme/DesignTokens';
import { t, tf } from '../service/LocalizationService';
import { appConfirm, appToast } from '../service/DialogService';
import { NavBar } from '../components/ui/NavBar';
import { ListRow } from '../components/ui/ListRow';
import { StateView } from '../components/ui/StateView';

const DOMAIN = 0x0001;
const TAG = 'HistoryListPage';
/** 播放历史最多展示条数 */
const HISTORY_LIMIT = 120;

@Component
export struct HistoryListPage {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('langVersion') langVersion: number = 0;
  @State isLoading: boolean = true;
  @State playHistory: PlayHistoryItem[] = [];

  aboutToAppear() {
    void this.loadHistory();
  }

  private async loadHistory(): Promise<void> {
    this.isLoading = true;
    try {
      this.playHistory = await getPlayHistory(HISTORY_LIMIT);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadHistory failed: %{public}s', JSON.stringify(err));
      this.playHistory = [];
    } finally {
      this.isLoading = false;
    }
  }

  private async clearHistory(): Promise<void> {
    const confirmed = await appConfirm(t('history_clear'), t('history_clear'), { danger: true });
    if (!confirmed) {
      return;
    }
    try {
      await clearPlayHistory();
      this.playHistory = [];
      appToast(t('toast_history_cleared'));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clearHistory failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_clear_failed'));
    }
  }

  /** 点击历史条目：重新取链并播放 */
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
        isRefresh: false,
        allowToggleSource: true,
      });
      if (!url) {
        appToast(t('toast_no_play_url'));
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
      // 队列 = 当前历史列表，方便连续播放
      const queue: SongInfo[] = [];
      let startIndex = 0;
      for (let i = 0; i < this.playHistory.length; i++) {
        const item = this.playHistory[i];
        if (item.id === song.id && item.source === song.source) {
          startIndex = i;
        }
        queue.push({
          id: item.id,
          url: item.id === song.id ? url : '',
          title: item.name,
          artist: item.singer,
          album: item.album || '',
          artwork: item.pic || null,
          duration: item.duration,
          source: item.source,
        });
      }
      playerService.setPlayList(queue, startIndex);
      await playerService.playFromSelection(songInfo, url, song.duration);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'play history song failed: %{public}s', JSON.stringify(error));
      appToast(t('toast_play_failed'));
    }
  }

  @Builder
  private trailingActions() {
    if (this.playHistory.length > 0) {
      Text(t('history_clear'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.accent())
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .onClick(() => {
          void this.clearHistory();
        })
    }
  }

  build() {
    Column() {
      NavBar({
        title: t('history_title'),
        largeTitle: true,
        trailing: (): void => {
          this.trailingActions();
        },
      })

      if (this.isLoading) {
        StateView({ state: 'loading', message: t('loading') })
          .layoutWeight(1)
          .width('100%')
      } else if (this.playHistory.length === 0) {
        StateView({
          state: 'empty',
          iconRes: $r('sys.symbol.clock'),
          message: t('history_empty_hint'),
        })
          .layoutWeight(1)
          .width('100%')
      } else {
        List() {
          ForEach(this.playHistory, (song: PlayHistoryItem, index: number) => {
            ListItem() {
              ListRow({
                index: index + 1,
                title: song.name,
                subtitle: song.album ? `${song.singer} · ${song.album}` : song.singer,
                trailingText: song.duration > 0 ? formatPlayTime(song.duration) : '',
                divider: index < this.playHistory.length - 1,
                onTap: (): void => {
                  void this.playHistorySong(song);
                },
              })
            }
            .padding({ left: 16, right: 16 })
          }, (song: PlayHistoryItem, index: number) => `${song.id}_${song.source}_${song.playedAt}_${index}`)

          ListItem() {
            Text(tf('history_count', [this.playHistory.length.toString()]))
              .fontSize(DesignTokens.fontCaption())
              .fontColor(DesignTokens.labelTertiary(this.theme))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 14, bottom: 18 })
          }
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }
}
