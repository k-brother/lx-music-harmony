import { t } from '../service/LocalizationService';
// 自建歌单管理页面
import hilog from '@ohos.hilog';
import { navigationService, RouteName } from '../service/NavigationService';
import { DesignTokens } from '../theme/DesignTokens';
import { NavBackButton } from '../components/common/NavBackButton';
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
}

@Component
export struct UserListsPage {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State renderKey: number = Date.now();
  @State userLists: UserListRow[] = [];
  @State isLoading: boolean = true;
  @State showCreateSheet: boolean = false;
  @State newListName: string = '';
  @State editingList: UserListRow | null = null;
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
        });
      }
      this.userLists = rows;
    } catch (err) {
      hilog.error(0x0001, 'UserListsPage', 'Failed to load user lists: %{public}s', JSON.stringify(err));
    } finally {
      this.isLoading = false;
    }
  }

  private showToast(msg: string) {
    try {
      this.getUIContext().getPromptAction().showToast({ message: msg, duration: 2000 });
    } catch (_e) { /* ignore */ }
  }

  private async submitNewList(): Promise<void> {
    const name = this.newListName.trim();
    if (!name) {
      this.showToast('请输入歌单名称');
      return;
    }
    try {
      await createUserList(name);
      this.newListName = '';
      this.showCreateSheet = false;
      await this.loadUserLists();
      this.showToast(`已创建「${name}」`);
    } catch (e) {
      this.showToast('创建失败，请重试');
    }
  }

  private async submitRename(): Promise<void> {
    if (!this.editingList) return;
    const name = this.editName.trim();
    if (!name) {
      this.showToast('请输入歌单名称');
      return;
    }
    try {
      await renameUserList(this.editingList.id, name);
      this.editingList = null;
      this.editName = '';
      await this.loadUserLists();
      this.showToast('已重命名');
    } catch (e) {
      this.showToast('重命名失败');
    }
  }

  private async deleteList(list: UserListRow): Promise<void> {
    try {
      const confirmed = await new Promise<boolean>((resolve) => {
        this.getUIContext().getPromptAction().showDialog({
          title: t('confirm_delete_title'),
          message: `确认删除「${list.name}」？`,
          buttons: [
            { text: t('cancel'), color: DesignTokens.labelSecondary(this.theme) },
            { text: t('delete'), color: '#FF3B30' },
          ],
        }, (_err: object, data: PromptActionResult) => {
          resolve(data.index === 1);
        });
      });
      if (!confirmed) return;
      await deleteUserList(list.id);
      await this.loadUserLists();
      this.showToast('已删除');
    } catch (e) {
      this.showToast('删除失败');
    }
  }

  @Builder
  ListCard(list: UserListRow) {
    Row() {
      Stack() {
        if (list.pic) {
          Image(list.pic)
            .width(52)
            .height(52)
            .borderRadius(10)
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Image($r('sys.symbol.music_note_list'))
              .width(24)
              .height(24)
              .fillColor(DesignTokens.labelTertiary(this.theme))
          }
          .width(52)
          .height(52)
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
        Text(`${list.count} 首歌曲`)
          .fontSize(13)
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .margin({ top: 6 })
      }
      .layoutWeight(1)
      .padding({ left: 14 })
      .alignItems(HorizontalAlign.Start)

      Text('编辑')
        .fontSize(13)
        .fontColor(DesignTokens.accent())
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .onClick(() => {
          this.editingList = list;
          this.editName = list.name;
        })

      Text(t('delete'))
        .fontSize(13)
        .fontColor('#FF3B30')
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .onClick(() => {
          void this.deleteList(list);
        })
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
          Text('新建歌单')
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

  @Builder
  RenameSheetOverlay() {
    if (this.editingList) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0,0,0,0.45)')
          .onClick(() => {
            this.editingList = null;
            this.editName = '';
          })

        Column() {
          Text('重命名歌单')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .width('100%')
            .margin({ bottom: 16 })

          TextInput({ placeholder: t('input_playlist_name'), text: this.editName })
            .height(44)
            .width('100%')
            .backgroundColor(DesignTokens.mutedFill(this.theme))
            .borderRadius(12)
            .padding({ left: 14, right: 14 })
            .fontSize(16)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .placeholderColor(DesignTokens.labelTertiary(this.theme))
            .onChange((v: string) => {
              this.editName = v;
            })

          Row() {
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
              .margin({ left: 12 })
              .onClick(() => {
                void this.submitRename();
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

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          NavBackButton()
            .onClick(() => { navigationService.back(); })

          Text('自建歌单')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .layoutWeight(1)
            .textAlign(TextAlign.Center)

          Button({ type: ButtonType.Capsule }) {
            Row({ space: 4 }) {
              Image($r('app.media.ic_common_create'))
                .width(14)
                .height(14)
                .fillColor(Color.White)
              Text('新建')
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
        .width('100%')
        .padding({ left: 8, right: 16, top: 8, bottom: 8 })
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
        } else if (this.userLists.length === 0) {
          Column() {
            Text(t('no_data'))
              .fontSize(16)
              .fontColor(DesignTokens.labelSecondary(this.theme))
            Text('点击右上角新建按钮创建')
              .fontSize(13)
              .fontColor(DesignTokens.labelTertiary(this.theme))
              .margin({ top: 8 })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column({ space: 10 }) {
              ForEach(this.userLists, (list: UserListRow) => {
                this.ListCard(list)
              }, (list: UserListRow) => list.id)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 20 })
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

      this.CreateSheetOverlay()
      this.RenameSheetOverlay()
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
