/**
 * 本地音乐页
 * 导入（系统文件选择器）→ 扫描元数据 → 列表展示 → 播放（file:// 直接播，无需网络）
 */
import hilog from '@ohos.hilog';
import { showAppToast, TOAST_DURATION_SHORT } from '../utils/Toast';
import filePicker from '@ohos.file.picker';
import { common } from '@kit.AbilityKit';
import { NavBackButton } from '../components/common/NavBackButton';
import { PlayerBar } from '../components/player/PlayerBar';
import { DesignTokens } from '../theme/DesignTokens';
import { t, tf } from '../service/LocalizationService';
import { localMusicService } from '../service/LocalMusicService';
import { playerService, type SongInfo } from '../service/PlayerService';
import { getLocalPicUrl, type LocalMusicInfo } from '../core/music/local/LocalPlayback';
import { EmptyView } from '../components/common/EmptyView';

const DOMAIN: number = 0x0001;
const TAG: string = 'LocalMusicPage';

@Component
export struct LocalMusicPage {
  @StorageProp('theme') theme: string = 'light';

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
  @State tracks: LocalMusicInfo[] = [];
  @State isLoading: boolean = false;
  @State playingId: string = '';
  /** 元数据编辑弹窗 */
  @State showEditDialog: boolean = false;
  @State editName: string = '';
  @State editSinger: string = '';
  @State editAlbum: string = '';
  private editingTrack: LocalMusicInfo | null = null;
  private coverLoaded: Set<string> = new Set();

  aboutToAppear(): void {
    void this.loadLibrary();
  }

  private async loadLibrary(): Promise<void> {
    this.isLoading = true;
    try {
      const list = localMusicService.getLibrary();
      this.tracks = list.slice();
      void this.loadCovers(list);
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'loadLibrary failed: %{public}s', JSON.stringify(err));
    } finally {
      this.isLoading = false;
    }
  }

  /** 首次展示时异步补内嵌封面，避免卡住列表 */
  private async loadCovers(list: LocalMusicInfo[]): Promise<void> {
    for (let i = 0; i < list.length; i++) {
      const track = list[i];
      if (this.coverLoaded.has(track.id)) {
        continue;
      }
      this.coverLoaded.add(track.id);
      try {
        const cover = await getLocalPicUrl({
          musicInfo: track,
          isRefresh: false,
          allowToggleSource: false,
        });
        if (cover && cover.length > 0) {
          track.picUrl = cover;
          this.tracks = this.tracks.slice();
        }
      } catch (err) {
        hilog.info(DOMAIN, TAG, 'cover skipped for %{public}s', track.name);
      }
    }
  }

  private async importMusic(): Promise<void> {
    this.isLoading = true;
    try {
      await localMusicService.importFromPicker();
      await this.loadLibrary();
      this.showToast(tf('local_imported', [this.tracks.length.toString()]));
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'importMusic failed: %{public}s', JSON.stringify(err));
      this.showToast(t('local_import_failed'));
    } finally {
      this.isLoading = false;
    }
  }

  private async rescan(): Promise<void> {
    this.isLoading = true;
    try {
      await localMusicService.rescan();
      await this.loadLibrary();
      this.showToast(tf('local_imported', [this.tracks.length.toString()]));
    } finally {
      this.isLoading = false;
    }
  }

  /** 播放列表中的某一首（把整个本地曲库作为播放队列） */
  private async playTrack(index: number): Promise<void> {
    if (index < 0 || index >= this.tracks.length) {
      return;
    }
    const queue: SongInfo[] = [];
    for (let i = 0; i < this.tracks.length; i++) {
      queue.push(localMusicService.toSongInfo(this.tracks[i]));
    }
    playerService.setPlayList(queue, index);
    try {
      await playerService.playSelectedFromPlayList(index);
      this.playingId = this.tracks[index].id;
      this.tracks = this.tracks.slice();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'playTrack failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_play_failed'));
    }
  }

  /**
   * 长按曲目菜单。
   * 统一使用系统 ActionMenu（与歌单详情的长按菜单同一套交互），
   * 而不是各页各写一个自绘确认框。
   */
  private showTrackMenu(track: LocalMusicInfo): void {
    const primary = DesignTokens.labelPrimary(this.theme);
    this.getUIContext().getPromptAction().showActionMenu({
      title: track.name,
      buttons: [
        { text: t('play'), color: primary },
        { text: t('edit_metadata'), color: primary },
        { text: t('pick_cover'), color: primary },
        { text: t('local_remove_title'), color: DesignTokens.danger() },
        { text: t('cancel'), color: DesignTokens.labelTertiary(this.theme) },
      ],
    }, (err: BusinessError, data: PromptDialogResult) => {
      if (err) {
        return;
      }
      if (data.index === 0) {
        void this.playTrack(this.tracks.indexOf(track));
      } else if (data.index === 1) {
        this.openEditDialog(track);
      } else if (data.index === 2) {
        void this.pickCover(track);
      } else if (data.index === 3) {
        void this.removeTrack(track);
      }
    });
  }

  /** 打开元数据编辑弹窗 */
  private openEditDialog(track: LocalMusicInfo): void {
    this.editingTrack = track;
    this.editName = track.name;
    this.editSinger = track.singer;
    this.editAlbum = track.album;
    this.showEditDialog = true;
  }

  /** 保存元数据 */
  private async saveMetadata(): Promise<void> {
    const track = this.editingTrack;
    if (!track) {
      return;
    }
    const ok = await localMusicService.updateMetadata(track.id, this.editName, this.editSinger, this.editAlbum);
    if (ok) {
      this.showEditDialog = false;
      this.editingTrack = null;
      await this.loadLibrary();
      this.showToast(t('metadata_saved'));
    } else {
      this.showToast(t('metadata_name_required'));
    }
  }

  /** 选择并保存自定义封面 */
  private async pickCover(track: LocalMusicInfo): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const picker = new filePicker.PhotoViewPicker(context);
      const options = new filePicker.PhotoSelectOptions();
      options.MIMEType = filePicker.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result: filePicker.PhotoSelectResult = await picker.select(options);
      if (!result || !result.photoUris || result.photoUris.length === 0) {
        return;
      }
      const ok = await localMusicService.setCustomCover(track.id, result.photoUris[0]);
      if (ok) {
        this.coverLoaded.delete(track.id);
        await this.loadLibrary();
        this.showToast(t('cover_saved'));
      } else {
        this.showToast(t('cover_save_failed'));
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'pickCover failed: %{public}s', JSON.stringify(err));
      this.showToast(t('cover_save_failed'));
    }
  }

  private async removeTrack(track: LocalMusicInfo): Promise<void> {
    await localMusicService.remove(track.id);
    await this.loadLibrary();
    this.showToast(t('toast_deleted'));
  }

  private showToast(message: string): void {
    showAppToast(this.getUIContext(), message, TOAST_DURATION_SHORT);
  }


  private formatDuration(ms: number): string {
    const total = Math.floor(ms / 1000);
    const m = Math.floor(total / 60);
    const s = total % 60;
    return `${m}:${s.toString().padStart(2, '0')}`;
  }

  @Builder
  TopBar() {
    Row() {
      NavBackButton()
      Text(t('local_music'))
        .fontSize(DesignTokens.fontTitle())
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .margin({ left: 12 })
        .layoutWeight(1)
      if (this.tracks.length > 0) {
        Image($r('sys.symbol.arrow_clockwise'))
          .width(20)
          .height(20)
          .fillColor(DesignTokens.labelSecondary(this.theme))
          .margin({ right: 16 })
          .onClick(() => {
            void this.rescan();
          })
      }
      Image($r('sys.symbol.plus'))
        .width(20)
        .height(20)
        .fillColor(DesignTokens.accent())
        .onClick(() => {
          void this.importMusic();
        })
    }
    .width('100%')
    .height(56)
    .padding({ left: 4, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  EditMetadataDialog() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.35)')
        .onClick(() => {
          this.showEditDialog = false;
          this.editingTrack = null;
        })

      Column({ space: 10 }) {
        Text(t('edit_metadata'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .width('100%')
          .textAlign(TextAlign.Start)

        // 三个字段内联书写：@Builder 传函数回调在 ArkTS V1 里支持不稳定
        Column() {
          Text(t('metadata_name'))
            .fontSize(12)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .width('100%')
            .textAlign(TextAlign.Start)
          TextInput({ text: this.editName })
            .width('100%')
            .height(40)
            .fontSize(15)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .backgroundColor(DesignTokens.mutedFill(this.theme))
            .borderRadius(10)
            .padding({ left: 12, right: 12 })
            .margin({ top: 6 })
            .onChange((text: string) => {
              this.editName = text;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column() {
          Text(t('metadata_singer'))
            .fontSize(12)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .width('100%')
            .textAlign(TextAlign.Start)
          TextInput({ text: this.editSinger })
            .width('100%')
            .height(40)
            .fontSize(15)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .backgroundColor(DesignTokens.mutedFill(this.theme))
            .borderRadius(10)
            .padding({ left: 12, right: 12 })
            .margin({ top: 6 })
            .onChange((text: string) => {
              this.editSinger = text;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Column() {
          Text(t('metadata_album'))
            .fontSize(12)
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .width('100%')
            .textAlign(TextAlign.Start)
          TextInput({ text: this.editAlbum })
            .width('100%')
            .height(40)
            .fontSize(15)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .backgroundColor(DesignTokens.mutedFill(this.theme))
            .borderRadius(10)
            .padding({ left: 12, right: 12 })
            .margin({ top: 6 })
            .onChange((text: string) => {
              this.editAlbum = text;
            })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row({ space: 10 }) {
          Button(t('cancel'))
            .fontSize(15)
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .backgroundColor(DesignTokens.mutedFill(this.theme))
            .borderRadius(18)
            .layoutWeight(1)
            .onClick(() => {
              this.showEditDialog = false;
              this.editingTrack = null;
            })
          Button(t('confirm'))
            .fontSize(15)
            .fontColor(DesignTokens.onAccent())
            .backgroundColor(DesignTokens.accent())
            .borderRadius(18)
            .layoutWeight(1)
            .onClick(() => {
              void this.saveMetadata();
            })
        }
        .width('100%')
        .margin({ top: 6 })
      }
      .width('86%')
      .padding(18)
      .backgroundColor(DesignTokens.card(this.theme))
      .borderRadius(20)
      .border({ width: 0.33, color: DesignTokens.cardBorder(this.theme) })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  EmptyState() {
    Column() {
      EmptyView({ iconRes: $r('sys.symbol.music_note_list'), message: t('local_empty_hint') })
      Button(t('local_import'))
        .fontSize(15)
        .backgroundColor(DesignTokens.accent())
        .borderRadius(20)
        .margin({ top: 6 })
        .onClick(() => {
          void this.importMusic();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  TrackList() {
    List() {
      ForEach(this.tracks, (track: LocalMusicInfo, index: number) => {
        ListItem() {
          Row() {
            if (track.picUrl && track.picUrl.length > 0) {
              Image(`file://${track.picUrl}`)
                .width(52)
                .height(52)
                .borderRadius(8)
                .objectFit(ImageFit.Cover)
                .backgroundColor(DesignTokens.mutedFill(this.theme))
            } else {
              Image($r('app.media.ic_player_cover_placeholder'))
                .width(52)
                .height(52)
                .borderRadius(8)
                .objectFit(ImageFit.Cover)
            }

            Column() {
              Text(track.name)
                .fontSize(15)
                .fontWeight(this.playingId === track.id ? FontWeight.Medium : FontWeight.Normal)
                .fontColor(this.playingId === track.id
                  ? DesignTokens.accent() : DesignTokens.labelPrimary(this.theme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .textAlign(TextAlign.Start)
              Text(track.singer.length > 0 ? `${track.singer} · ${track.album}` : track.album)
                .fontSize(12)
                .fontColor(DesignTokens.labelTertiary(this.theme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
                .textAlign(TextAlign.Start)
                .margin({ top: 4 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            .margin({ left: 12 })

            Text(this.formatDuration(track.duration))
              .fontSize(12)
              .fontColor(DesignTokens.labelTertiary(this.theme))
          }
          .width('100%')
          .padding({
            left: DesignTokens.spaceGutter(),
            right: DesignTokens.spaceGutter(),
            top: 8,
            bottom: 8,
          })
          .stateStyles({ pressed: this.pressDim })
          .onClick(() => {
            void this.playTrack(index);
          })
          .gesture(
            LongPressGesture()
              .onAction(() => {
                this.showTrackMenu(track);
              })
          )
        }
      }, (track: LocalMusicInfo) => track.id)
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    Column() {
      this.TopBar()

      if (this.isLoading && this.tracks.length === 0) {
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color(DesignTokens.accent())
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.tracks.length === 0) {
        this.EmptyState()
      } else {
        this.TrackList()
      }

      PlayerBar()

      if (this.showEditDialog) {
        this.EditMetadataDialog()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }
}

interface PromptDialogResult {
  index: number;
}
