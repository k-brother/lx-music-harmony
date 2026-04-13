// Mylist 视图 - 我的列表视图
// 优化：系统图标、真实API、新建/编辑歌单

import { navigationService, RouteName } from '../../service/NavigationService';
import { playerService, SongInfo } from '../../service/PlayerService';
import { getMusicUrl } from '../../core/music/MusicFeatureEntry';
import ListService, { getLoveList, getUserList, LIST_IDS, MusicItem, ListInfo } from '../../service/ListService';
import { MusicInfo as AppMusicInfo, MusicSource } from '../../types/MusicTypes';
import hilog from '@ohos.hilog';

// 用户列表行接口
interface UserListRow {
  id: string;
  name: string;
  pic: string;
  count: number;
  musicList: MyListSongRow[];
}

// 歌曲行接口
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

@Component
export struct MylistView {
  @StorageProp('theme') theme: string = 'light';
  @State defaultList: UserListRow | null = null;
  @State loveList: UserListRow | null = null;
  @State userLists: UserListRow[] = [];
  @State isLoading: boolean = false;
  @State showCreateDialog: boolean = false;
  @State newListName: string = '';

  aboutToAppear() {
    this.loadMyLists();
  }

  async loadMyLists(): Promise<void> {
    this.isLoading = true;

    try {
      // 从ListService获取真实数据
      const loveMusic: MusicItem[] = getLoveList();
      this.loveList = {
        id: LIST_IDS.LOVE,
        name: '我喜欢的',
        pic: '',
        count: loveMusic.length,
        musicList: this.convertToSongRows(loveMusic),
      };

      const userListInfo: ListInfo[] = getUserList();
      this.userLists = [];
      for (let i = 0; i < userListInfo.length; i++) {
        const listInfo = userListInfo[i];
        const listMusic: MusicItem[] = ListService.getUserListMusic(listInfo.id);
        const row: UserListRow = {
          id: listInfo.id,
          name: listInfo.name,
          pic: listInfo.pic || '',
          count: listMusic.length,
          musicList: this.convertToSongRows(listMusic),
        };
        this.userLists.push(row);
      }

      hilog.info(0x0001, 'MylistView', 'Loaded lists: love=%{public}d, user=%{public}d',
        this.loveList?.count || 0, this.userLists.length);
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

  build() {
    Column() {
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color('#E63946')
          Text('加载中...')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        this.ListContent()
      }

      // 新建歌单按钮
      Button('+ 新建歌单')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('#E63946')
        .borderRadius(20)
        .padding({ left: 20, right: 20, top: 10, bottom: 10 })
        .onClick(() => {
          this.showCreateDialog = true;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
  }

  @Builder
  ListContent() {
    List() {
      // 我喜欢的音乐
      if (this.loveList) {
        ListItem() {
          this.ListCard(this.loveList, true)
        }
        .onClick(() => {
          this.navigateToList(this.loveList!.id, '我喜欢的', 'local');
        })
      }

      // 用户创建的歌单
      ForEach(this.userLists, (list: UserListRow) => {
        ListItem() {
          this.ListCard(list, false)
        }
        .onClick(() => {
          this.navigateToList(list.id, list.name, 'local');
        })
      })
    }
    .width('100%')
    .layoutWeight(1)
    .divider({
      strokeWidth: 0.5,
      color: this.theme === 'dark' ? '#333333' : '#F0F0F0',
      startMargin: 74,
      endMargin: 0
    })
  }

  @Builder
  ListCard(list: UserListRow, isLove: boolean) {
    Row() {
      // 封面
      Stack() {
        if (list.pic) {
          Image(list.pic)
            .width(52)
            .height(52)
            .borderRadius(8)
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            if (isLove) {
              Image($r('sys.symbol.heart_fill'))
                .width(24)
                .height(24)
                .fillColor('#E63946')
            } else {
              Image($r('sys.symbol.folder'))
                .width(24)
                .height(24)
                .fillColor(this.theme === 'dark' ? '#AAAAAA' : '#999999')
            }
          }
          .width(52)
          .height(52)
          .backgroundColor(isLove ? 'rgba(230, 57, 70, 0.15)' : (this.theme === 'dark' ? '#2C2C2C' : '#E8E8E8'))
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width(52)
      .height(52)

      // 信息
      Column() {
        Text(list.name)
          .fontSize(15)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(list.count + '首')
          .fontSize(12)
          .fontColor('#999999')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .padding({ left: 12 })
      .alignItems(HorizontalAlign.Start)

      // 播放按钮
      Image($r('sys.symbol.play_circle'))
        .width(28)
        .height(28)
        .fillColor(isLove ? '#E63946' : (this.theme === 'dark' ? '#AAAAAA' : '#999999'))
        .onClick(() => {
          this.playList(list);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
  }

  async playList(list: UserListRow): Promise<void> {
    if (list.musicList.length === 0) {
      hilog.info(0x0001, 'MylistView', 'List is empty: %{public}s', list.name);
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

      // 获取第一首URL
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
        quality: '128k',
        isRefresh: false,
        allowToggleSource: true,
      });

      if (!url) {
        hilog.error(0x0001, 'MylistView', 'Failed to get URL for: %{public}s', firstSong.name);
        return;
      }

      songInfos[0].url = url;
      playerService.setPlayList(songInfos, 0);
      await playerService.setSource(songInfos[0], url, firstSong.duration);
      await playerService.play();
    } catch (error) {
      hilog.error(0x0001, 'MylistView', 'Play list failed: %{public}s', JSON.stringify(error));
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
    if (isNaN(time) || time < 0) return '00:00';
    const mins = Math.floor(time / 60);
    const secs = Math.floor(time % 60);
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }
}
