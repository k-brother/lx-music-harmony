/**
 * 本地音乐页
 * 导入（系统文件选择器）→ 扫描元数据 → 列表展示 → 播放（file:// 直接播，无需网络）
 */
import hilog from '@ohos.hilog';
import { showAppToast, TOAST_DURATION_SHORT } from '../utils/Toast';
import filePicker from '@ohos.file.picker';
import { common } from '@kit.AbilityKit';
import { PlayerBar } from '../components/player/PlayerBar';
import { DesignTokens } from '../theme/DesignTokens';
import { t, tf } from '../service/LocalizationService';
import { localMusicService } from '../service/LocalMusicService';
import { playerService, type SongInfo } from '../service/PlayerService';
import { getLocalPicUrl, type LocalMusicInfo } from '../core/music/local/LocalPlayback';
import { NavBar } from '../components/ui/NavBar';
import { StateView } from '../components/ui/StateView';
import { hapticService } from '../service/HapticService';
import { appActionMenu, appConfirm } from '../service/DialogService';
import { SkeletonListItem } from '../components/common/SkeletonView';
import { EditMetadataSheet } from './LocalMusic/EditMetadataSheet';
import { LocalMusicActions } from './LocalMusic/LocalMusicActions';
import { TrackRow } from './LocalMusic/TrackRow';
import { Breakpoints } from '../theme/Breakpoints';
import { LazyDataSource } from '../utils/LazyDataSource';

const DOMAIN: number = 0x0001;
const TAG: string = 'LocalMusicPage';

@Component
export struct LocalMusicPage {
  @StorageProp('theme') theme: string = 'light';
  /** 一多：窗口宽度（vp），大屏内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;

  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State tracks: LocalMusicInfo[] = [];
  /** LazyForEach 数据源：长列表只创建可视区的行 */
  private trackSource: LazyDataSource<LocalMusicInfo> = new LazyDataSource<LocalMusicInfo>();
  @State isLoading: boolean = false;
  @State playingId: string = '';
  /** 元数据编辑弹窗 */
  @State showEditDialog: boolean = false;
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
      this.trackSource.reload(this.tracks);
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
          this.trackSource.reload(this.tracks);
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
      // 高亮依赖页面的 playingId（不在行数据里）：显式通知该行重建
      this.trackSource.notifyChanged(index);
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
  private async showTrackMenu(track: LocalMusicInfo): Promise<void> {
    // 统一走 DialogService：取消项由系统菜单提供，「移除」用危险色
    const picked = await appActionMenu(track.name, [
      t('play'),
      t('edit_metadata'),
      t('pick_cover'),
      t('local_remove_title'),
    ], { dangerIndexes: [3] });
    if (picked === 0) {
      void this.playTrack(this.tracks.indexOf(track));
    } else if (picked === 1) {
      this.openEditDialog(track);
    } else if (picked === 2) {
      void this.pickCover(track);
    } else if (picked === 3) {
      void this.removeTrack(track);
    }
  }

  /** 打开元数据编辑弹窗 */
  private openEditDialog(track: LocalMusicInfo): void {
    this.editingTrack = track;
    this.showEditDialog = true;
  }

  /** 保存元数据（新值由编辑面板回传） */
  private async saveMetadata(name: string, singer: string, album: string): Promise<void> {
    const track = this.editingTrack;
    if (!track) {
      return;
    }
    const ok = await localMusicService.updateMetadata(track.id, name, singer, album);
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

  /** 侧滑露出的「删除」按钮 */
  @Builder
  DeleteAction(index: number) {
    Row() {
      Text(t('delete'))
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(DesignTokens.onAccent())
        .fontWeight(FontWeight.Medium)
    }
    .width(88)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(DesignTokens.danger())
    .onClick(() => {
      this.confirmRemoveTrack(index);
    })
  }

  /** 侧滑删除前二次确认（长按菜单是明确操作，不再重复确认） */
  private async confirmRemoveTrack(index: number): Promise<void> {
    if (index < 0 || index >= this.tracks.length) {
      return;
    }
    const track = this.tracks[index];
    const confirmed = await appConfirm(t('local_remove_title'), track.name, { danger: true });
    if (confirmed) {
      await this.removeTrack(track);
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

  /** 行副标题：「歌手 · 专辑」，缺歌手时只显示专辑 */
  private buildSubtitle(track: LocalMusicInfo): string {
    if (track.singer.length === 0) {
      return track.album;
    }
    return `${track.singer} · ${track.album}`;
  }

  @Builder
  TopBar() {
    // 统一顶部栏：返回按钮触控区/标题字号/沉浸式安全区都由 NavBar 负责
    NavBar({
      title: t('local_music'),
      trailing: (): void => {
        LocalMusicActions({
          hasTracks: this.tracks.length > 0,
          onRescan: (): void => {
            void this.rescan();
          },
          onImport: (): void => {
            void this.importMusic();
          },
        })
      },
    })
  }

  /** 空态：提示 + 直接导入的入口（比只给一句提示更可操作） */
  @Builder
  EmptyState() {
    Column() {
      StateView({
        state: 'empty',
        iconRes: $r('sys.symbol.music_note_list'),
        message: t('local_empty_hint'),
      })
      Button(t('local_import'))
        .fontSize(DesignTokens.fontSubhead())
        .height(DesignTokens.touchTarget())
        .backgroundColor(DesignTokens.accent())
        .borderRadius(20)
        .margin({ top: 10 })
        .onClick(() => {
          hapticService.light();
          void this.importMusic();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Column() {
      this.TopBar()

      if (this.isLoading && this.tracks.length === 0) {
        // 骨架行代替转圈：与其它列表页一致
        Column() {
          ForEach([0, 1, 2, 3, 4], (index: number) => {
            SkeletonListItem()
          }, (index: number) => `local_skeleton_${index}`)
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.tracks.length === 0) {
        this.EmptyState()
      } else {
        List() {
          LazyForEach(this.trackSource, (track: LocalMusicInfo, index: number) => {
            ListItem() {
              TrackRow({
                title: track.name,
                subtitle: this.buildSubtitle(track),
                durationText: this.formatDuration(track.duration),
                coverUrl: track.picUrl ?? '',
                active: this.playingId === track.id,
                onTap: (): void => {
                  void this.playTrack(index);
                },
                onLongPress: (): void => {
                  void this.showTrackMenu(track);
                },
              })
            }
            // 侧滑删除：删除的是应用沙箱内的副本，仍给一次确认（误触代价高）
            .swipeAction({
              end: {
                builder: (): void => {
                  this.DeleteAction(index);
                },
                onAction: (): void => {
                  this.confirmRemoveTrack(index);
                },
                actionAreaDistance: 56,
              },
            })
          }, (track: LocalMusicInfo) => track.id)
        }
        .width('100%')
        .layoutWeight(1)
        .cachedCount(6)
        .padding({
          left: Breakpoints.contentInset(this.windowWidthVp),
          right: Breakpoints.contentInset(this.windowWidthVp),
        })
      }

      PlayerBar()

      if (this.showEditDialog) {
        EditMetadataSheet({
          visible: $showEditDialog,
          name: this.editingTrack ? this.editingTrack.name : '',
          singer: this.editingTrack ? this.editingTrack.singer : '',
          album: this.editingTrack ? this.editingTrack.album : '',
          onCancel: (): void => {
            this.editingTrack = null;
          },
          onSave: (name: string, singer: string, album: string): void => {
            void this.saveMetadata(name, singer, album);
          },
        })
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
