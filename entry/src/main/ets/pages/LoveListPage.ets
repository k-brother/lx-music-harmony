// 我喜欢的歌曲列表页面
import hilog from '@ohos.hilog';
import { navigationService } from '../service/NavigationService';
import { DesignTokens } from '../theme/DesignTokens';
import { NavBackButton } from '../components/common/NavBackButton';
import { getLoveList, toggleLoveList, type MusicItem } from '../service/ListService';
import { playerService, SongInfo } from '../service/PlayerService';
import { t } from '../service/LocalizationService';

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
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State renderKey: number = Date.now();
  @State songs: SongRow[] = [];
  @State isLoading: boolean = true;

  aboutToAppear() {
    void this.loadSongs();
  }

  private loadSongs() {
    try {
      this.isLoading = true;
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
      hilog.error(0x0001, 'LoveListPage', 'Failed to load: %{public}s', JSON.stringify(err));
    } finally {
      this.isLoading = false;
    }
  }

  private showToast(msg: string) {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    } catch (_e) { /* ignore */ }
  }

  private async playSong(index: number) {
    if (this.songs.length === 0) {
      this.showToast('列表为空');
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
      // 由播放器按索引取播放地址（受"自动播放"设置控制）
      await playerService.playSelectedFromPlayList(index);
    } catch (e) {
      this.showToast('播放失败');
    }
  }

  private async removeFromLove(song: SongRow) {
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
      this.songs = this.songs.filter(s => s.id !== song.id);
      this.showToast('已取消喜欢');
    } catch (e) {
      this.showToast('操作失败');
    }
  }

  @Builder
  SongRowItem(song: SongRow, index: number) {
    Row() {
      Text((index + 1).toString())
        .fontSize(12)
        .fontColor(DesignTokens.labelTertiary(this.theme))
        .width(28)
        .textAlign(TextAlign.Center)

      Column() {
        Text(song.name)
          .fontSize(15)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(song.singer)
          .fontSize(12)
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 8 })

      Image($r('app.media.ic_common_download'))
        .width(20)
        .height(20)
        .fillColor(DesignTokens.labelTertiary(this.theme))
        .margin({ right: 12 })
        .opacity(0)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      void this.playSong(index);
    })
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          NavBackButton()
            .onClick(() => { navigationService.back(); })

          Text(t('love_title'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Text(`${this.songs.length} 首`)
            .fontSize(13)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .padding({ right: 16 })
        }
        .width('100%')
        .padding({ left: 8, right: 8, top: 8, bottom: 8 })
        .alignItems(VerticalAlign.Center)

        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.songs.length === 0) {
          Column() {
          Text(t('love_empty'))
              .fontSize(16)
              .fontColor(DesignTokens.labelSecondary(this.theme))
            Text(t('no_data'))
              .fontSize(13)
              .fontColor(DesignTokens.labelTertiary(this.theme))
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 0 }) {
              ForEach(this.songs, (song: SongRow, index: number) => {
                Column() {
                  this.SongRowItem(song, index)
                  Divider()
                    .strokeWidth(0.5)
                    .color(DesignTokens.cardBorder(this.theme))
                    .margin({ left: 28 })
                }
              }, (song: SongRow, _index: number) => song.id)
            }
            .width('100%')
          }
          .align(Alignment.TopStart)
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(DesignTokens.pageBg(this.theme))
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
