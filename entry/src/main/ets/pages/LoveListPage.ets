/**
 * 我喜欢的歌曲
 *
 * 重构后：NavBar + ListRow + StateView + DialogService 统一交互；
 * 行尾用 ⋮ 菜单（播放 / 取消收藏），避免原先"隐形图标"的可发现性问题。
 */
import hilog from '@ohos.hilog';
import { DesignTokens } from '../theme/DesignTokens';
import { Breakpoints } from '../theme/Breakpoints';
import { getLoveList, toggleLoveList, type MusicItem } from '../service/ListService';
import { playerService, SongInfo } from '../service/PlayerService';
import { t, tf } from '../service/LocalizationService';
import { appActionMenu, appToast } from '../service/DialogService';
import { NavBar } from '../components/ui/NavBar';
import { ListRow } from '../components/ui/ListRow';
import { StateView } from '../components/ui/StateView';

const DOMAIN = 0x0001;
const TAG = 'LoveListPage';

interface SongRow {
  id: string;
  name: string;
  singer: string;
  album: string;
  pic: string;
  duration: number;
  source: string;
}

@Component
export struct LoveListPage {
  @StorageProp('theme') theme: string = 'light';
  /** 一多：窗口宽度（vp），大屏内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
  @StorageProp('langVersion') langVersion: number = 0;
  @State songs: SongRow[] = [];
  @State isLoading: boolean = true;
  /** 正在播放的曲目 id（高亮行） */
  @State playingId: string = '';

  aboutToAppear() {
    this.loadSongs();
  }

  private loadSongs(): void {
    this.isLoading = true;
    try {
      const loveList: MusicItem[] = getLoveList();
      const rows: SongRow[] = [];
      for (let i = 0; i < loveList.length; i++) {
        const m = loveList[i];
        rows.push({
          id: m.id || '',
          name: m.name || '',
          singer: m.singer || '',
          album: m.album || '',
          pic: m.pic || '',
          duration: m.duration || 0,
          source: m.source || '',
        });
      }
      this.songs = rows;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to load: %{public}s', JSON.stringify(err));
      this.songs = [];
    } finally {
      this.isLoading = false;
    }
  }

  /** 播放：队列 = 我喜欢列表（next/prev 可在喜欢列表里连续播放） */
  private async playSong(index: number): Promise<void> {
    if (this.songs.length === 0) {
      appToast(t('list_empty'));
      return;
    }
    try {
      const songInfos: SongInfo[] = [];
      for (let i = 0; i < this.songs.length; i++) {
        const s = this.songs[i];
        songInfos.push({
          id: s.id,
          url: '',
          title: s.name,
          artist: s.singer,
          album: s.album || '',
          artwork: s.pic || null,
          duration: s.duration,
          source: s.source,
        });
      }
      playerService.setPlayList(songInfos, index);
      this.playingId = this.songs[index]?.id ?? '';
      await playerService.playSelectedFromPlayList(index);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'playSong failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_play_failed'));
    }
  }

  private async removeFromLove(song: SongRow): Promise<void> {
    try {
      const musicItem: MusicItem = {
        id: song.id,
        name: song.name,
        singer: song.singer,
        album: song.album,
        albumId: null,
        duration: song.duration,
        source: song.source,
        pic: song.pic,
        lrc: null,
      };
      await toggleLoveList(musicItem);
      this.songs = this.songs.filter((item: SongRow) => item.id !== song.id);
      appToast(t('toast_unloved'));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'removeFromLove failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_operation_failed'));
    }
  }

  /** 行菜单（⋮）：播放 / 下一首播放 / 取消收藏 */
  private async openSongMenu(song: SongRow, index: number): Promise<void> {
    const index0 = await appActionMenu(song.name, [
      t('play'),
      t('play_later'),
      t('player_unlove'),
    ], { dangerIndexes: [2] });
    if (index0 === 0) {
      void this.playSong(index);
    } else if (index0 === 1) {
      playerService.insertNext({
        id: song.id,
        url: '',
        title: song.name,
        artist: song.singer,
        album: song.album,
        artwork: song.pic || null,
        duration: song.duration,
        source: song.source,
      });
      appToast(tf('toast_play_later_added', [song.name]));
    } else if (index0 === 2) {
      void this.removeFromLove(song);
    }
  }

  @Builder
  private rowTrailing(song: SongRow, index: number) {
    Stack() {
      Circle({ width: 30, height: 30 })
        .fill(DesignTokens.mutedFill(this.theme))
      Image($r('app.media.ic_pd_more'))
        .width(14)
        .height(14)
        .fillColor(DesignTokens.labelSecondary(this.theme))
    }
    .width(DesignTokens.touchTarget())
    .height(DesignTokens.touchTarget())
    .onClick(() => {
      void this.openSongMenu(song, index);
    })
  }

  build() {
    Column() {
      NavBar({
        title: t('love_title'),
        largeTitle: true,
        trailing: (): void => {
          Text(tf('count_songs_short', [this.songs.length.toString()]))
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .padding({ right: 6 })
        },
      })

      if (this.isLoading) {
        StateView({ state: 'loading' })
          .layoutWeight(1)
          .width('100%')
      } else if (this.songs.length === 0) {
        StateView({ state: 'empty', iconRes: $r('sys.symbol.heart'), message: t('love_empty_hint') })
          .layoutWeight(1)
          .width('100%')
      } else {
        List() {
          ForEach(this.songs, (song: SongRow, index: number) => {
            ListItem() {
              ListRow({
                index: index + 1,
                title: song.name,
                subtitle: song.album ? `${song.singer} · ${song.album}` : song.singer,
                active: song.id === this.playingId,
                divider: index < this.songs.length - 1,
                onTap: (): void => {
                  void this.playSong(index);
                },
                onLongPress: (): void => {
                  void this.openSongMenu(song, index);
                },
                trailing: (): void => {
                  this.rowTrailing(song, index);
                },
              })
            }
            .padding({ left: 16, right: 8 })
          }, (song: SongRow, index: number) => `${song.id}_${index}`)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .padding({
          left: Breakpoints.contentInset(this.windowWidthVp),
          right: Breakpoints.contentInset(this.windowWidthVp),
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }
}
