// 我的 — 资料库式布局：入口卡片 + 自建歌单列表 + 新建歌单（弹层闭环）

import { t, tf } from '../../service/LocalizationService';
import { syncUserListFromOnline } from '../../service/UserListSyncService';
import { showAppToast, TOAST_DURATION_DEFAULT } from '../../utils/Toast';
import { navigationService, RouteName } from '../../service/NavigationService';
import { playerService, SongInfo } from '../../service/PlayerService';
import { getMusicUrl } from '../../core/music/MusicFeatureEntry';
import ListService, {
  getLoveList,
  getUserList,
  LIST_IDS,
  createUserList,
  deleteUserList,
  renameUserList,
  MusicItem,
  ListInfo,
} from '../../service/ListService';
import { showPlaylistActionMenu, type PlaylistMenuTarget } from './Mylist/ListMenuActions';
import { appConfirm } from '../../service/DialogService';
import { sheetService } from '../../service/SheetService';
import { MusicInfo as AppMusicInfo, MusicSource } from '../../types/MusicTypes';
import hilog from '@ohos.hilog';
import { DesignTokens } from '../../theme/DesignTokens';
import { EventTypes, on } from '../../service/EventBus';
import { getPlayHistory, PlayHistoryItem } from '../../service/PlayHistoryService';
import { BottomSheet } from '../../components/ui/BottomSheet';
import { StateView } from '../../components/ui/StateView';
import { MylistQuickCard } from './Mylist/MylistQuickCard';
import { MylistEntryRow } from './Mylist/MylistEntryRow';
import { MylistSectionHeader } from './Mylist/MylistSectionHeader';
import { UserPlaylistCard } from './Mylist/UserPlaylistCard';
import { SongRowList } from './Mylist/SongRowList';
import type { MylistSongRow as MyListSongRow } from './Mylist/MylistTypes';
import type { UserListRow } from './Mylist/MylistTypes';
import { RefreshContainer } from '../../components/ui/RefreshContainer';
import { hapticService } from '../../service/HapticService';
import { Breakpoints } from '../../theme/Breakpoints';

interface PromptActionResult {
  index: number;
}

@Component
export struct MylistView {
  @StorageProp('theme') theme: string = 'light';
  /** 一多：窗口宽度（vp），大屏内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
  /** 一多：断点（lg 下分两列） */
  @StorageProp('breakpoint') breakpoint: string = 'sm';

  /** 按压反馈：卡片轻微缩放 */
  @Styles
  pressScale() {
    .scale({ x: 0.97, y: 0.97 })
  }

  /** 按压反馈：列表行/图标变淡 */
  @Styles
  pressDim() {
    .opacity(0.65)
  }

  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State loveList: UserListRow | null = null;
  @State userLists: UserListRow[] = [];
  @State isLoading: boolean = false;
  /** 下拉刷新中 */
  @State isRefreshing: boolean = false;
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
        bindingSource: '',
        bindingListId: '',
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
          bindingSource: listInfo.bindingSource ?? '',
          bindingListId: listInfo.bindingListId ?? '',
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

  private toast(message: string): void {
    showAppToast(this.getUIContext(), message, TOAST_DURATION_DEFAULT);
  }


  private async submitNewList(): Promise<void> {
    const name = this.newListName.trim();
    if (!name) {
      this.toast(t('input_playlist_name'));
      return;
    }
    try {
      await createUserList(name);
      this.newListName = '';
      this.showCreateSheet = false;
      await this.loadMyLists();
      this.toast(tf('toast_created_quoted', [name]));
    } catch (e) {
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      hilog.error(0x0001, 'MylistView', 'createUserList: %{public}s', msg);
      this.toast(t('toast_create_list_fail'));
    }
  }










  /** 左列：快捷入口 + 本地音乐 + 我喜欢 */
  @Builder
LeftSections() {
          // 快捷入口：我喜欢 / 播放历史
          Row({ space: 10 }) {
            MylistQuickCard({
              title: t('my_love'),
              subtitle: `${this.loveList?.count ?? 0} ${t('songlist_total')}`,
              icon: $r('sys.symbol.heart_fill'),
              iconColor: DesignTokens.accent(),
              onTap: (): void => {
                navigationService.navigateTo(RouteName.LOVE_LIST);
              },
            })
            MylistQuickCard({
              title: t('my_history'),
              subtitle: `${this.playHistory.length} ${t('songlist_total')}`,
              icon: $r('sys.symbol.music_note_list'),
              iconColor: DesignTokens.labelSecondary(this.theme),
              onTap: (): void => {
                navigationService.navigateTo(RouteName.HISTORY_LIST);
              },
            })
          }
          .width('100%')
          .padding({
            left: DesignTokens.spaceGutter(),
            right: DesignTokens.spaceGutter(),
            top: 12,
            bottom: 6,
          })

          // 本地音乐入口
          MylistEntryRow({
            icon: $r('sys.symbol.folder'),
            title: t('local_music'),
            subtitle: t('local_music_desc'),
            onTap: (): void => {
              navigationService.navigateTo(RouteName.LOCAL_MUSIC);
            },
          })
            .padding({
              left: DesignTokens.spaceGutter(),
              right: DesignTokens.spaceGutter(),
            })

          // 我喜欢
          MylistSectionHeader({
            title: t('my_love'),
            subtitle: t('mylist_loved_songs'),
            actionText: this.loveList && this.loveList.musicList.length > 0 ? t('view_all') : '',
            onAction: (): void => {
              navigationService.navigateTo(RouteName.LOVE_LIST);
            },
          })
          if (!this.loveList || this.loveList.musicList.length === 0) {
            StateView({ state: 'empty', iconRes: $r('sys.symbol.heart'), message: t('love_empty_hint') })
              .width('100%')
              .height(140)
          } else {
            SongRowList({
              songs: this.loveList.musicList.slice(0, 6),
              onPlay: (song: MyListSongRow): void => {
                void this.playHistorySong(song);
              },
            })
          }
}

  /** 右列：播放历史 + 自建歌单 */
  @Builder
  RightSections() {
    this.HistorySection()
    this.UserListsSection()
  }

  /** 播放历史：有记录时展示最近 6 首，没有则给空态（标题右侧「查看全部」进历史页） */
  @Builder
  HistorySection() {
    // 播放历史
    MylistSectionHeader({
      title: t('my_history'),
      subtitle: t('history_empty_hint'),
      actionText: this.playHistory.length > 0 ? t('view_all') : '',
      topPadding: 12,
      onAction: (): void => {
        navigationService.navigateTo(RouteName.HISTORY_LIST);
      },
    })
    if (this.playHistory.length === 0) {
      StateView({ state: 'empty', iconRes: $r('sys.symbol.clock'), message: t('history_empty_hint') })
        .width('100%')
        .height(140)
    } else {
      SongRowList({
        songs: this.playHistory.slice(0, 6),
        onPlay: (song: MyListSongRow): void => {
          void this.playHistorySong(song);
        },
      })
    }
  }

  /** 自建歌单：无歌单给空态，有则列出卡片（打开 / 播放 / 同步 / 菜单） */
  @Builder
  UserListsSection() {
    // 自建歌单
    MylistSectionHeader({
      title: t('songlist_title'),
      subtitle: t('mylist_local_hint'),
      actionText: t('view_all'),
      showPrimaryAction: true,
      primaryText: t('my_create_list'),
      topPadding: 12,
      onAction: (): void => {
        navigationService.navigateTo(RouteName.USER_LISTS);
      },
      onPrimaryAction: (): void => {
        this.newListName = '';
        this.showCreateSheet = true;
      },
    })
    if (this.userLists.length === 0) {
      StateView({ state: 'empty', iconRes: $r('sys.symbol.folder'), message: t('mylist_empty_hint') })
        .width('100%')
        .height(180)
    } else {
      Column({ space: 10 }) {
        ForEach(this.userLists, (list: UserListRow) => {
          UserPlaylistCard({
            name: list.name,
            count: list.count,
            pic: list.pic,
            bindingSource: list.bindingSource,
            bindingListId: list.bindingListId,
            onOpen: (): void => {
              this.navigateToList(list.id, list.name, 'local');
            },
            onPlay: (): void => {
              void this.playList(list);
            },
            onSync: (): void => {
              void this.syncList(list);
            },
            onMenu: (): void => {
              void this.openListMenu(list);
            },
          })
            .padding({ left: DesignTokens.spaceGutter(), right: DesignTokens.spaceGutter() })
        }, (list: UserListRow) => list.id)
      }
      .width('100%')
      .padding({ bottom: 32 })
    }
  }

  build() {
    Stack() {
      if (this.isLoading) {
        StateView({ state: 'loading' })
          .width('100%')
          .height('100%')
      } else {
        RefreshContainer({
          refreshing: $isRefreshing,
          onRefresh: (): void => {
            hapticService.selection();
            hilog.info(0x0001, 'MylistView', 'Pull-to-refresh: reload my lists');
            this.loadMyLists().then((): void => {
              this.isRefreshing = false;
            }).catch((): void => {
              this.isRefreshing = false;
            });
          },
        }) {
          Scroll() {
            Column() {
              // 一多：lg（平板横屏 / PC）分两列，窄屏保持单列；两列顺序与单列自上而下一致
              if (Breakpoints.isLarge(this.breakpoint)) {
                Row({ space: 0 }) {
                  Column() {
                    this.LeftSections()
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)

                  Column() {
                    this.RightSections()
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)
              } else {
                Column() {
                  this.LeftSections()
                  this.RightSections()
                }
                .width('100%')
              }
            }
            .width('100%')
            // 大屏内容列居中：只在这里加一次留白，各区块只管自己的 16vp 边距
            .padding({
              left: Breakpoints.contentInset(this.windowWidthVp),
              right: Breakpoints.contentInset(this.windowWidthVp),
            })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
      }

      // 新建歌单面板（底部面板，替代居中弹窗）
      if (this.showCreateSheet) {
        BottomSheet({
          visible: $showCreateSheet,
          title: t('my_create_list'),
          content: (): void => {
            this.CreateListForm();
          },
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }

  /** 新建歌单表单 */
  @Builder
  CreateListForm() {
    Column() {
      TextInput({ placeholder: t('input_playlist_name'), text: this.newListName })
        .height(DesignTokens.touchTarget())
        .width('100%')
        .backgroundColor(DesignTokens.mutedFill(this.theme))
        .borderRadius(12)
        .padding({ left: 14, right: 14 })
        .fontSize(DesignTokens.fontTitle())
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .placeholderColor(DesignTokens.labelTertiary(this.theme))
        .onChange((value: string) => {
          this.newListName = value;
        })

      Row({ space: 12 }) {
        Button(t('cancel'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(DesignTokens.touchTarget())
          .fontSize(DesignTokens.fontTitle())
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .backgroundColor(DesignTokens.mutedFill(this.theme))
          .onClick(() => {
            this.showCreateSheet = false;
            this.newListName = '';
          })
        Button(t('create_list_btn'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(DesignTokens.touchTarget())
          .fontSize(DesignTokens.fontTitle())
          .fontColor(Color.White)
          .backgroundColor(DesignTokens.accent())
          .onClick(() => {
            void this.submitNewList();
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
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
        this.toast(t('toast_no_play_url'));
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
      this.toast(t('toast_play_failed'));
    }
  }

  async playList(list: UserListRow): Promise<void> {
    if (list.musicList.length === 0) {
      this.toast(t('songlist_empty'));
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
        this.toast(t('toast_no_play_url'));
        return;
      }
      songInfos[0].url = url;
      playerService.setPlayList(songInfos, 0);
      await playerService.playFromSelection(songInfos[0], url, firstSong.duration);
    } catch (error) {
      hilog.error(0x0001, 'MylistView', 'Play list failed: %{public}s', JSON.stringify(error));
      this.toast(t('toast_play_failed'));
    }
  }

  navigateToList(listId: string, listName: string, source: string): void {
    navigationService.navigateTo(RouteName.SONGLIST_DETAIL, {
      songListId: listId,
      songListName: listName,
      songListSource: source,
    });
  }
  /**
   * 歌单卡片「更多」菜单：打开 / 更新内容 / 重命名 / 删除
   * 与「全部歌单」页共用同一份菜单定义（见 Mylist/ListMenuActions）。
   */
  private async openListMenu(list: UserListRow): Promise<void> {
    const target: PlaylistMenuTarget = {
      name: list.name,
      bindingListId: list.bindingListId ?? '',
    };
    const action = await showPlaylistActionMenu(target);
    if (action === 'open') {
      this.navigateToList(list.id, list.name, 'local');
    } else if (action === 'sync') {
      void this.syncList(list);
    } else if (action === 'rename') {
      await this.renameList(list);
    } else if (action === 'delete') {
      await this.deleteList(list);
    }
  }

  /** 重命名：走全局面板输入（设置里也用同一个） */
  private async renameList(list: UserListRow): Promise<void> {
    const name = await sheetService.input(t('list_rename_title'), list.name);
    const trimmed = name.trim();
    hilog.info(0x0001, 'MylistView', 'renameList: id=%{public}s, old=%{public}s, input=%{public}s',
      list.id, list.name, name);
    if (trimmed.length === 0 || trimmed === list.name) {
      return;
    }
    try {
      await renameUserList(list.id, trimmed);
      await this.loadMyLists();
      this.toast(t('toast_playlist_renamed'));
      hilog.info(0x0001, 'MylistView', 'renameList done: %{public}s -> %{public}s', list.id, trimmed);
    } catch (err) {
      hilog.error(0x0001, 'MylistView', 'renameList failed: %{public}s', JSON.stringify(err));
      this.toast(t('toast_operation_failed'));
    }
  }

  /** 删除（危险操作，二次确认） */
  private async deleteList(list: UserListRow): Promise<void> {
    const confirmed = await appConfirm(
      t('confirm_delete_title'),
      tf('confirm_delete_quoted', [list.name]),
      { danger: true, confirmText: t('delete') });
    if (!confirmed) {
      return;
    }
    try {
      await deleteUserList(list.id);
      await this.loadMyLists();
      this.toast(t('toast_playlist_deleted'));
    } catch (err) {
      hilog.error(0x0001, 'MylistView', 'deleteList failed: %{public}s', JSON.stringify(err));
      this.toast(t('toast_operation_failed'));
    }
  }

  /** 列表级同步：拉取绑定在线歌单的最新内容 */
  private async syncList(list: UserListRow): Promise<void> {
    this.toast(t('toast_syncing'));
    try {
      const result = await syncUserListFromOnline(list.id);
      if (result.ok) {
        this.toast(tf('toast_sync_done_count', [String(result.count)]));
      } else {
        this.toast(t('toast_sync_local_failed'));
      }
      await this.loadMyLists();
    } catch (err) {
      hilog.warn(0x0001, 'MylistView', 'syncList failed: %{public}s', JSON.stringify(err));
      this.toast(t('toast_sync_local_failed'));
    }
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
