// 我的 — 资料库式布局：入口卡片 + 自建歌单列表 + 新建歌单（弹层闭环）

import { t } from '../../service/LocalizationService';
import { navigationService, RouteName } from '../../service/NavigationService';
import { playerService, SongInfo } from '../../service/PlayerService';
import { getMusicUrl } from '../../core/music/MusicFeatureEntry';
import ListService, {
  getLoveList,
  getUserList,
  LIST_IDS,
  createUserList,
  MusicItem,
  ListInfo,
} from '../../service/ListService';
import { MusicInfo as AppMusicInfo, MusicSource } from '../../types/MusicTypes';
import hilog from '@ohos.hilog';
import { DesignTokens } from '../../theme/DesignTokens';
import { EventTypes, on } from '../../service/EventBus';
import { getPlayHistory, clearPlayHistory, PlayHistoryItem } from '../../service/PlayHistoryService';

interface UserListRow {
  id: string;
  name: string;
  pic: string;
  count: number;
  musicList: MyListSongRow[];
}

interface MyListSongRow {
  id: string;
  name: string;
  singer: string;
  album?: string;
  pic?: string;
  duration: number;
  source: string;
  songmid?: string;
  albumId?: string;
  hash?: string;
}

interface PromptActionResult {
  index: number;
}

@Component
export struct MylistView {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State loveList: UserListRow | null = null;
  @State userLists: UserListRow[] = [];
  @State isLoading: boolean = false;
  @State showCreateSheet: boolean = false;
  @State newListName: string = '';
  @State playHistory: MyListSongRow[] = [];
  private listUnsubscribe: (() => void) | null = null;

  aboutToAppear() {
    void this.loadMyLists();
    this.listUnsubscribe = on(EventTypes.LIST_UPDATED, () => {
      void this.loadMyLists();
    });
  }

  aboutToDisappear() {
    if (this.listUnsubscribe) {
      this.listUnsubscribe();
      this.listUnsubscribe = null;
    }
  }

  async loadMyLists(): Promise<void> {
    this.isLoading = true;
    try {
      const loveMusic: MusicItem[] = getLoveList();
      this.loveList = {
        id: LIST_IDS.LOVE,
        name: t('my_love'),
        pic: '',
        count: loveMusic.length,
        musicList: this.convertToSongRows(loveMusic),
      };

      const userListInfo: ListInfo[] = getUserList();
      const rows: UserListRow[] = [];
      for (let i = 0; i < userListInfo.length; i++) {
        const listInfo = userListInfo[i];
        const listMusic: MusicItem[] = ListService.getUserListMusic(listInfo.id);
        rows.push({
          id: listInfo.id,
          name: listInfo.name,
          pic: listInfo.pic || '',
          count: listMusic.length,
          musicList: this.convertToSongRows(listMusic),
        });
      }
      this.userLists = rows;

      const historyList = await getPlayHistory(40);
      this.playHistory = this.convertHistoryToRows(historyList);
    } catch (error) {
      hilog.error(0x0001, 'MylistView', 'Failed to load lists: %{public}s', JSON.stringify(error));
    } finally {
      this.isLoading = false;
    }
  }

  private convertToSongRows(musicList: MusicItem[]): MyListSongRow[] {
    const rows: MyListSongRow[] = [];
    for (let i = 0; i < musicList.length; i++) {
      const m = musicList[i];
      rows.push({
        id: m.id || '',
        name: m.name || '',
        singer: m.singer || '',
        album: m.album || '',
        pic: m.pic || '',
        duration: m.duration,
        source: m.source || 'local',
      });
    }
    return rows;
  }

  private convertHistoryToRows(history: PlayHistoryItem[]): MyListSongRow[] {
    const rows: MyListSongRow[] = [];
    for (let i = 0; i < history.length; i++) {
      const item = history[i];
      rows.push({
        id: item.id,
        name: item.name,
        singer: item.singer,
        album: item.album,
        pic: item.pic,
        duration: item.duration,
        source: item.source,
        songmid: item.songmid,
      });
    }
    return rows;
  }

  private toast(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    } catch (_e) {
      hilog.info(0x0001, 'MylistView', '%{public}s', msg);
    }
  }

  private async clearHistoryWithConfirm(): Promise<void> {
    try {
      const confirmed = await new Promise<boolean>((resolve) => {
        this.getUIContext().getPromptAction().showDialog({
          title: t('confirm_clear_history'),
          message: t('confirm_clear_history_msg'),
          buttons: [
            { text: t('cancel'), color: DesignTokens.labelSecondary(this.theme) },
            { text: t('confirm'), color: DesignTokens.accent() },
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
      hilog.warn(0x0001, 'MylistView', 'clear history failed: %{public}s', JSON.stringify(e));
      this.toast('清空失败');
    }
  }

  private async submitNewList(): Promise<void> {
    const name = this.newListName.trim();
    if (!name) {
      this.toast('请输入歌单名称');
      return;
    }
    try {
      await createUserList(name);
      this.newListName = '';
      this.showCreateSheet = false;
      await this.loadMyLists();
      this.toast(`已创建「${name}」`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      hilog.error(0x0001, 'MylistView', 'createUserList: %{public}s', msg);
      this.toast('创建失败，请重试');
    }
  }

  @Builder
  CreateSheetOverlay() {
    if (this.showCreateSheet) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.45)')
          .onClick(() => {
            this.showCreateSheet = false;
            this.newListName = '';
          })

        Column() {
          Text(t('my_create_list'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .width('100%')
            .margin({ bottom: 16 })

          TextInput({ placeholder: t('input_playlist_name'), text: this.newListName })
            .height(44)
            .width('100%')
            .backgroundColor(DesignTokens.mutedFill(this.theme))
            .borderRadius(12)
            .padding({ left: 14, right: 14 })
            .fontSize(16)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .placeholderColor(DesignTokens.labelTertiary(this.theme))
            .onChange((v: string) => {
              this.newListName = v;
            })

          Row() {
            Button(t('cancel'))
              .type(ButtonType.Capsule)
              .fontColor(DesignTokens.labelSecondary(this.theme))
              .backgroundColor(DesignTokens.mutedFill(this.theme))
              .layoutWeight(1)
              .onClick(() => {
                this.showCreateSheet = false;
                this.newListName = '';
              })
            Button(t('create_list_btn'))
              .type(ButtonType.Capsule)
              .fontColor(Color.White)
              .backgroundColor(DesignTokens.accent())
              .layoutWeight(1)
              .margin({ left: 12 })
              .onClick(() => {
                void this.submitNewList();
              })
          }
          .width('100%')
          .margin({ top: 20 })
        }
        .width('86%')
        .padding(20)
        .backgroundColor(DesignTokens.card(this.theme))
        .borderRadius(DesignTokens.radiusCard())
        .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
        .alignSelf(ItemAlign.Center)
      }
      .width('100%')
      .height('100%')
    }
  }

  private openHistoryList(): void {
    navigationService.navigateTo(RouteName.HISTORY_LIST);
  }

  @Builder
  LibraryHero() {
    Row({ space: 10 }) {
      this.LibraryQuickCard(
        t('my_love'),
        `${this.loveList?.count ?? 0} ${t('songlist_total')}`,
        $r('sys.symbol.heart_fill'),
        DesignTokens.accent(),
        () => {
          navigationService.navigateTo(RouteName.LOVE_LIST);
        }
      )
      this.LibraryQuickCard(
        t('my_history'),
        `${this.playHistory.length} ${t('songlist_total')}`,
        $r('sys.symbol.music_note_list'),
        DesignTokens.labelSecondary(this.theme),
        () => {
          this.openHistoryList();
        }
      )
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 8 })
  }

  @Builder
  private LibraryQuickCard(
    title: string,
    subtitle: string,
    icon: Resource,
    iconColor: ResourceColor,
    onClick: () => void
  ) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.labelPrimary(this.theme))
      Text(subtitle)
        .fontSize(12)
        .fontColor(DesignTokens.labelTertiary(this.theme))
        .margin({ top: 6 })
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(iconColor)
        .margin({ top: 12 })
    }
    .layoutWeight(1)
    .height(122)
    .padding(14)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
    .onClick(onClick)
  }

  @Builder
  LoveListSection() {
    Column() {
      Row() {
        Column() {
          Text(t('my_love'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(DesignTokens.labelPrimary(this.theme))
          Text('收藏的歌曲')
            .fontSize(12)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.loveList && this.loveList.musicList.length > 0) {
          Row({ space: 2 }) {
            Text('查看全部')
              .fontSize(13)
              .fontColor(DesignTokens.accent())
              .fontWeight(FontWeight.Medium)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .onClick(() => {
                navigationService.navigateTo(RouteName.LOVE_LIST);
              })
          }
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (!this.loveList || this.loveList.musicList.length === 0) {
        Column() {
          Text(t('no_data'))
            .fontSize(14)
            .fontColor(DesignTokens.labelSecondary(this.theme))
          Text('播放时点击心形按钮收藏')
            .fontSize(12)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .margin({ top: 6 })
        }
        .width('100%')
        .padding({ top: 20, bottom: 18 })
        .alignItems(HorizontalAlign.Center)
      } else {
        Column({ space: 0 }) {
          ForEach(this.loveList.musicList.slice(0, 6), (song: MyListSongRow, index: number) => {
            this.HistorySongRow(song, index)
          }, (song: MyListSongRow, index: number) => `${song.id}_${song.source}_${index}`)
        }
        .width('100%')
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  HistorySection() {
    Column() {
      Row() {
        Column() {
          Text(t('my_history'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(DesignTokens.labelPrimary(this.theme))
          Text(t('my_history'))
            .fontSize(12)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.playHistory.length > 0) {
          Row({ space: 2 }) {
            Text('查看全部')
              .fontSize(13)
              .fontColor(DesignTokens.accent())
              .fontWeight(FontWeight.Medium)
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .onClick(() => {
                this.openHistoryList();
              })
            Text('清空')
              .fontSize(13)
              .fontColor(DesignTokens.labelTertiary(this.theme))
              .padding({ left: 10, right: 4, top: 6, bottom: 6 })
              .onClick(() => {
                void this.clearHistoryWithConfirm();
              })
          }
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.playHistory.length === 0) {
        Column() {
          Text(t('no_data'))
            .fontSize(14)
            .fontColor(DesignTokens.labelSecondary(this.theme))
          Text('播放过的歌曲会出现在这里')
            .fontSize(12)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .margin({ top: 6 })
        }
        .width('100%')
        .padding({ top: 20, bottom: 18 })
        .alignItems(HorizontalAlign.Center)
      } else {
        Column({ space: 0 }) {
          ForEach(this.playHistory.slice(0, 6), (song: MyListSongRow, index: number) => {
            this.HistorySongRow(song, index)
          }, (song: MyListSongRow, index: number) => `${song.id}_${song.source}_${index}`)
        }
        .width('100%')
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  private HistorySongRow(song: MyListSongRow, index: number) {
    Column() {
      Row() {
        Text((index + 1).toString())
          .fontSize(12)
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .width(24)
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
        .margin({ left: 8, right: 8 })

        Stack() {
          Circle({ width: 28, height: 28 })
            .fill(DesignTokens.mutedFill(this.theme))
          Image($r('app.media.ic_pd_play'))
            .width(12)
            .height(12)
            .fillColor(DesignTokens.accent())
            .margin({ left: 1 })
        }
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 10, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        void this.playHistorySong(song);
      })

      Divider()
        .strokeWidth(0.5)
        .color(DesignTokens.cardBorder(this.theme))
        .margin({ left: 8, right: 8 })
    }
    .width('100%')
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(12)
    .clip(true)
  }

  @Builder
  SectionHeader() {
    Row() {
      Column() {
        Text(t('songlist_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(DesignTokens.labelPrimary(this.theme))
        Text('本地保存的播放列表')
          .fontSize(12)
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Row({ space: 8 }) {
        Text('查看全部')
          .fontSize(13)
          .fontColor(DesignTokens.accent())
          .fontWeight(FontWeight.Medium)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .onClick(() => {
            navigationService.navigateTo(RouteName.USER_LISTS);
          })
        Button({ type: ButtonType.Capsule }) {
          Row({ space: 4 }) {
            Image($r('app.media.ic_common_create'))
              .width(14)
              .height(14)
              .fillColor(Color.White)
            Text(t('my_create_list'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
          }
        }
        .height(30)
        .padding({ left: 10, right: 10 })
        .backgroundColor(DesignTokens.accent())
        .onClick(() => {
          this.newListName = '';
          this.showCreateSheet = true;
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  UserPlaylistCard(list: UserListRow) {
    Row() {
      Stack() {
        if (list.pic) {
          Image(list.pic)
            .width(56)
            .height(56)
            .borderRadius(10)
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Image($r('sys.symbol.music_note_list'))
              .width(26)
              .height(26)
              .fillColor(DesignTokens.labelTertiary(this.theme))
          }
          .width(56)
          .height(56)
          .borderRadius(10)
          .backgroundColor(DesignTokens.mutedFill(this.theme))
          .justifyContent(FlexAlign.Center)
        }
      }

      Column() {
        Text(list.name)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(`${list.count} ${t('songlist_total')}`)
          .fontSize(13)
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .margin({ top: 6 })
      }
      .layoutWeight(1)
      .padding({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      Image($r('sys.symbol.play_circle'))
        .width(30)
        .height(30)
        .fillColor(DesignTokens.accent())
        .onClick(() => {
          void this.playList(list);
        })

      Image($r('sys.symbol.chevron_right'))
        .width(14)
        .height(14)
        .fillColor(DesignTokens.labelTertiary(this.theme))
        .margin({ left: 8 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
    .onClick(() => {
      navigationService.navigateTo(RouteName.SONGLIST_DETAIL, {
        songListId: list.id,
        songListName: list.name,
        songListSource: 'local',
      });
    })
  }

  build() {
    Stack() {
      Column() {
        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(DesignTokens.accent())
            Text(t('loading'))
              .fontSize(14)
              .fontColor(DesignTokens.labelSecondary(this.theme))
              .margin({ top: 14 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              if (this.loveList) {
                this.LibraryHero()
              }
              this.LoveListSection()
              this.HistorySection()
              this.SectionHeader()

              if (this.userLists.length === 0) {
                Column() {
                  Image($r('sys.symbol.folder'))
                    .width(56)
                    .height(56)
                    .fillColor(DesignTokens.labelTertiary(this.theme))
                    .margin({ bottom: 12 })
                  Text(t('no_data'))
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(DesignTokens.labelSecondary(this.theme))
                  Text('点击右上角「新建」创建第一个歌单，或在播放页将歌曲加入歌单')
                    .fontSize(13)
                    .fontColor(DesignTokens.labelTertiary(this.theme))
                    .textAlign(TextAlign.Center)
                    .lineHeight(20)
                    .margin({ top: 10, left: 28, right: 28 })
                }
                .width('100%')
                .padding({ top: 36, bottom: 48 })
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              } else {
                Column({ space: 10 }) {
                  ForEach(this.userLists, (list: UserListRow) => {
                    Column() {
                      this.UserPlaylistCard(list)
                    }
                    .padding({ left: 16, right: 16 })
                  }, (list: UserListRow) => list.id)
                }
                .width('100%')
                .padding({ bottom: 32 })
              }
            }
            .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(DesignTokens.pageBg(this.theme))

      this.CreateSheetOverlay()
    }
    .width('100%')
    .height('100%')
  }

  async playHistorySong(song: MyListSongRow): Promise<void> {
    try {
      const musicInfo: AppMusicInfo = {
        id: song.id,
        name: song.name,
        singer: song.singer,
        source: song.source as MusicSource,
        songmid: song.songmid || song.id,
        interval: this.formatPlayTime(song.duration),
        img: song.pic || null,
        pic: song.pic || undefined,
        lrc: null,
        albumName: song.album || '',
        album: song.album || '',
        albumId: song.albumId || '',
        hash: song.hash || '',
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
      await playerService.playFromSelection(songInfo, url, song.duration);
    } catch (error) {
      hilog.error(0x0001, 'MylistView', 'Play history song failed: %{public}s', JSON.stringify(error));
      this.toast('播放失败');
    }
  }

  async playList(list: UserListRow): Promise<void> {
    if (list.musicList.length === 0) {
      this.toast('歌单为空，无法播放');
      return;
    }
    try {
      const songInfos: SongInfo[] = [];
      for (let i = 0; i < list.musicList.length; i++) {
        const song = list.musicList[i];
        songInfos.push({
          id: song.id,
          url: '',
          title: song.name,
          artist: song.singer,
          album: song.album || '',
          artwork: song.pic || null,
          duration: song.duration,
          source: song.source,
        });
      }
      const firstSong = list.musicList[0];
      const musicInfo: AppMusicInfo = {
        id: firstSong.id,
        name: firstSong.name,
        singer: firstSong.singer,
        source: firstSong.source as MusicSource,
        songmid: firstSong.id,
        interval: this.formatPlayTime(firstSong.duration),
        img: firstSong.pic || null,
        lrc: null,
        albumName: firstSong.album || '',
        album: firstSong.album || '',
        albumId: firstSong.albumId || '',
        hash: firstSong.hash || '',
        types: [],
        _types: new Map(),
        typeUrl: new Map(),
        otherSource: null,
      };
      const url: string | null = await getMusicUrl({
        musicInfo: musicInfo,
        isRefresh: false,
        allowToggleSource: true,
      });
      if (!url) {
        this.toast('无法获取播放链接');
        return;
      }
      songInfos[0].url = url;
      playerService.setPlayList(songInfos, 0);
      await playerService.playFromSelection(songInfos[0], url, firstSong.duration);
    } catch (error) {
      hilog.error(0x0001, 'MylistView', 'Play list failed: %{public}s', JSON.stringify(error));
      this.toast('播放失败');
    }
  }

  navigateToList(listId: string, listName: string, source: string): void {
    navigationService.navigateTo(RouteName.SONGLIST_DETAIL, {
      songListId: listId,
      songListName: listName,
      songListSource: source,
    });
  }

  private formatPlayTime(time: number): string {
    if (isNaN(time) || time < 0) {
      return '00:00';
    }
    const mins = Math.floor(time / 60);
    const secs = Math.floor(time % 60);
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }
}
