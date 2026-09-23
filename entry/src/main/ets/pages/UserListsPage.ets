import { t, tf, sourceLabel } from '../service/LocalizationService';
import { syncUserListFromOnline } from '../service/UserListSyncService';
import { appConfirm, appToast } from '../service/DialogService';
import { showPlaylistActionMenu, type PlaylistMenuTarget } from './Home/Mylist/ListMenuActions';
// 自建歌单管理页面
import hilog from '@ohos.hilog';
import { navigationService, RouteName } from '../service/NavigationService';
import { DesignTokens } from '../theme/DesignTokens';
import { Breakpoints } from '../theme/Breakpoints';
import { scrollerOffsetY } from '../utils/ScrollTools';
import { NavBar } from '../components/ui/NavBar';
import { PlayerBar } from '../components/player/PlayerBar';
import { BottomSheet } from '../components/ui/BottomSheet';
import { StateView } from '../components/ui/StateView';
import {
  getUserList,
  getUserListMusic,
  deleteUserList,
  renameUserList,
  createUserList,
  type MusicItem,
  type ListInfo
} from '../service/ListService';

interface PromptActionResult {
  index: number;
}

interface UserListRow {
  id: string;
  name: string;
  count: number;
  pic: string | null;
  /** 绑定在线歌单时非空（可同步） */
  bindingSource: string;
  bindingListId: string;
}

@Component
export struct UserListsPage {
  /** 按压反馈：可点卡片/行变淡 */
  @Styles
  pressed() {
    .opacity(DesignTokens.pressedOpacity())
  }

  @StorageProp('theme') theme: string = 'light';
  /** 一多：窗口宽度（vp），大屏内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State userLists: UserListRow[] = [];
  @State isLoading: boolean = true;
  /** 大标题滚动收缩：列表下滚后切到居中常规标题 */
  @State navCollapsed: boolean = false;
  private scrollController: Scroller = new Scroller();
  @State showCreateSheet: boolean = false;
  @State newListName: string = '';
  @State editingList: UserListRow | null = null;
  /** 重命名面板可见性（与 editingList 同时使用，便于 BottomSheet 双向绑定） */
  @State showRenameSheet: boolean = false;
  @State editName: string = '';

  aboutToAppear() {
    void this.loadUserLists();
  }

  async loadUserLists() {
    try {
      this.isLoading = true;
      const lists: ListInfo[] = getUserList();
      const rows: UserListRow[] = [];
      for (let i = 0; i < lists.length; i++) {
        const list: ListInfo = lists[i];
        const music: MusicItem[] = getUserListMusic(list.id);
        rows.push({
          id: list.id,
          name: list.name,
          count: music.length,
          pic: list.pic && list.pic.length > 0 ? list.pic : null,
          bindingSource: list.bindingSource ?? '',
          bindingListId: list.bindingListId ?? '',
        });
      }
      this.userLists = rows;
    } catch (err) {
      hilog.error(0x0001, 'UserListsPage', 'Failed to load user lists: %{public}s', JSON.stringify(err));
    } finally {
      this.isLoading = false;
    }
  }

  private showToast(message: string): void {
    appToast(message);
  }

  /** 列表级同步：重新拉取绑定的在线歌单内容（安卓 syncSourceList） */
  private async syncList(list: UserListRow): Promise<void> {
    if (list.bindingListId.length === 0) {
      return;
    }
    this.showToast(t('toast_syncing'));
    try {
      const result = await syncUserListFromOnline(list.id);
      if (result.ok) {
        this.showToast(tf('toast_sync_done_count', [String(result.count)]));
      } else {
        this.showToast(t('toast_sync_local_failed'));
      }
      await this.loadUserLists();
    } catch (err) {
      hilog.warn(0x0001, 'UserListsPage', 'syncList failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_sync_local_failed'));
    }
  }

  /** 歌单行菜单：与「我的」页卡片共用同一份定义（Mylist/ListMenuActions） */
  private async openListMenu(list: UserListRow): Promise<void> {
    const target: PlaylistMenuTarget = {
      name: list.name,
      bindingListId: list.bindingListId ?? '',
    };
    const action = await showPlaylistActionMenu(target);
    if (action === 'open') {
      navigationService.navigateTo(RouteName.SONGLIST_DETAIL, {
        songListId: list.id,
        songListName: list.name,
        songListSource: 'local',
      });
    } else if (action === 'sync') {
      void this.syncList(list);
    } else if (action === 'rename') {
      this.editingList = list;
      this.editName = list.name;
      this.showRenameSheet = true;
    } else if (action === 'delete') {
      void this.deleteList(list);
    }
  }

  private async submitNewList(): Promise<void> {
    const name = this.newListName.trim();
    if (!name) {
      this.showToast(t('input_playlist_name'));
      return;
    }
    try {
      await createUserList(name);
      this.newListName = '';
      this.showCreateSheet = false;
      await this.loadUserLists();
      this.showToast(tf('toast_created_quoted', [name]));
    } catch (e) {
      this.showToast(t('toast_create_list_fail'));
    }
  }

  private async submitRename(): Promise<void> {
    if (!this.editingList) return;
    const name = this.editName.trim();
    if (!name) {
      this.showToast(t('input_playlist_name'));
      return;
    }
    try {
      await renameUserList(this.editingList.id, name);
      this.editingList = null;
      this.showRenameSheet = false;
      this.editName = '';
      await this.loadUserLists();
      this.showToast(t('toast_playlist_renamed'));
    } catch (e) {
      this.showToast(t('toast_rename_fail'));
    }
  }

  private async deleteList(list: UserListRow): Promise<void> {
    try {
      const confirmed = await appConfirm(
        t('confirm_delete_title'),
        tf('confirm_delete_quoted', [list.name]),
        { danger: true, confirmText: t('delete') });
      if (!confirmed) return;
      await deleteUserList(list.id);
      await this.loadUserLists();
      this.showToast(t('toast_playlist_deleted'));
    } catch (e) {
      this.showToast(t('toast_delete_fail'));
    }
  }

  @Builder
  ListCard(index: number) {
    // 规则（实测结论）：@Builder 参数不随状态刷新；歌单首数与「来自xxx」角标都会变，
    // 所以只传 index，内容从 this.userLists 读，同步后卡片才会跟着更新。
    if (index < 0 || index >= this.userLists.length) {
      Blank()
    } else {
      this.ListCardBody(index)
    }
  }

  @Builder
  ListCardBody(index: number) {
    Row() {
      this.ListCardCover(index)
      this.ListCardTitle(index)
      this.ListCardSyncAction(index)
      this.ListCardMoreAction(index)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
    .stateStyles({ pressed: this.pressed })
    .onClick(() => {
      navigationService.navigateTo(RouteName.SONGLIST_DETAIL, {
        songListId: this.userLists[index].id,
        songListName: this.userLists[index].name,
        songListSource: 'local',
      });
    })
  }

  /** 歌单封面（无封面时用占位图标） */
  @Builder
  ListCardCover(index: number) {
    Stack() {
      if (this.userLists[index].pic) {
        Image(this.userLists[index].pic)
          .width(52)
          .height(52)
          .borderRadius(10)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music_note_list'))
            .fontSize(DesignTokens.fontCoverIcon())
            .fontColor([DesignTokens.labelTertiary(this.theme)])
        }
        .width(52)
        .height(52)
        .borderRadius(10)
        .backgroundColor(DesignTokens.mutedFill(this.theme))
        .justifyContent(FlexAlign.Center)
      }
    }
  }

  /** 歌单名称 + 歌曲数 + 「来自 xxx」角标 */
  @Builder
  ListCardTitle(index: number) {
    Column() {
      Text(this.userLists[index].name)
        .fontSize(DesignTokens.fontTitle())
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Row() {
        Text(tf('count_songs_unit', [this.userLists[index].count.toString()]))
          .fontSize(DesignTokens.fontCallout())
          .fontColor(DesignTokens.labelTertiary(this.theme))
        if (this.userLists[index].bindingListId.length > 0) {
          Text(tf('list_bound_online', [sourceLabel(this.userLists[index].bindingSource)]))
            .fontSize(DesignTokens.fontMicro())
            .fontColor(DesignTokens.accent())
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(8)
            .border({ width: 1, color: DesignTokens.accent() })
            .margin({ left: 8 })
        }
      }
      .margin({ top: 6 })
    }
    .layoutWeight(1)
    .padding({ left: 14 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 绑定在线歌单时的「同步歌单内容」入口 */
  @Builder
  ListCardSyncAction(index: number) {
    if (this.userLists[index].bindingListId.length > 0) {
      Text(t('list_sync_content'))
        .fontSize(DesignTokens.fontCallout())
        .fontColor(DesignTokens.accent())
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .accessibilityText(t('list_sync_content'))
        .onClick(() => {
          void this.syncList(this.userLists[index]);
        })
    }
  }

  /** 行尾 ⋮ 菜单：打开 / 更新歌单内容（绑定在线歌单时）/ 重命名 / 删除 */
  @Builder
  ListCardMoreAction(index: number) {
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
    .accessibilityText(t('a11y_more'))
    .onClick(() => {
      void this.openListMenu(this.userLists[index]);
    })
  }

  @Builder
  NavCreateAction() {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: 4 }) {
        Image($r('app.media.ic_common_create'))
          .width(14)
          .height(14)
          .fillColor(Color.White)
        Text(t('list_create_short'))
          .fontSize(DesignTokens.fontCallout())
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
    }
    .height(32)
    .padding({ left: 12, right: 12 })
    .backgroundColor(DesignTokens.accent())
    .responseRegion({ x: 0, y: -6, width: '100%', height: 44 })
    .onClick(() => {
      this.newListName = '';
      this.showCreateSheet = true;
    })
  }

  /** 新建歌单面板（BottomSheet 统一容器） */
  @Builder
  CreateSheetContent() {
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
          .onClick(() => {
            void this.submitNewList();
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
  }

  /** 重命名面板（BottomSheet 统一容器） */
  @Builder
  RenameSheetContent() {
    Column() {
      TextInput({ placeholder: t('input_playlist_name'), text: this.editName })
        .height(DesignTokens.touchTarget())
        .width('100%')
        .backgroundColor(DesignTokens.mutedFill(this.theme))
        .borderRadius(12)
        .padding({ left: 14, right: 14 })
        .fontSize(DesignTokens.fontTitle())
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .placeholderColor(DesignTokens.labelTertiary(this.theme))
        .onChange((value: string) => {
          this.editName = value;
        })

      Row({ space: 12 }) {
        Button(t('cancel'))
          .type(ButtonType.Capsule)
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .backgroundColor(DesignTokens.mutedFill(this.theme))
          .layoutWeight(1)
          .onClick(() => {
            this.editingList = null;
            this.editName = '';
          })
        Button(t('save'))
          .type(ButtonType.Capsule)
          .fontColor(Color.White)
          .backgroundColor(DesignTokens.accent())
          .layoutWeight(1)
          .onClick(() => {
            void this.submitRename();
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
  }

  build() {
    Stack() {
      Column() {
        NavBar({
          title: t('mylist_user_lists'),
          largeTitle: true,
          collapsed: this.navCollapsed,
          trailing: (): void => {
            this.NavCreateAction();
          },
        })

        if (this.isLoading) {
          StateView({ state: 'loading' })
            .width('100%')
            .layoutWeight(1)
        } else if (this.userLists.length === 0) {
          StateView({ state: 'empty', iconRes: $r('sys.symbol.folder'), message: t('user_lists_empty_hint') })
            .width('100%')
            .layoutWeight(1)
        } else {
          Scroll(this.scrollController) {
            Column({ space: 10 }) {
              ForEach(this.userLists, (list: UserListRow, index: number) => {
                this.ListCard(index)
              }, (list: UserListRow) => `${list.id}_${list.count}_${list.bindingListId}`)
            }
            .width('100%')
            .padding({
              left: 16 + Breakpoints.contentInset(this.windowWidthVp),
              right: 16 + Breakpoints.contentInset(this.windowWidthVp),
              top: 8,
              bottom: 20,
            })
          }
          .align(Alignment.TopStart)
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
          .onDidScroll(() => {
            const y = scrollerOffsetY(this.scrollController);
            if (y > 18 && !this.navCollapsed) {
              this.navCollapsed = true;
            } else if (y <= 4 && this.navCollapsed) {
              this.navCollapsed = false;
            }
          })
        }

        // 迷你播放条（页面底部沉浸到安全区，与歌单详情页一致）
        PlayerBar({ immersiveBottom: true })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(DesignTokens.pageBg(this.theme))

      if (this.showCreateSheet) {
        BottomSheet({
          visible: $showCreateSheet,
          title: t('list_create_title'),
          content: (): void => {
            this.CreateSheetContent();
          },
        })
      }

      if (this.editingList !== null) {
        BottomSheet({
          visible: $showRenameSheet,
          title: t('list_rename_title'),
          content: (): void => {
            this.RenameSheetContent();
          },
        })
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
