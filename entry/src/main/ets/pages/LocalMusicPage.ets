/**
 * 本地音乐页
 * 导入（系统文件选择器）→ 扫描元数据 → 列表展示 → 播放（file:// 直接播，无需网络）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { showAppToast, TOAST_DURATION_SHORT } from '../utils/Toast';
import { picker as filePicker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { PlayerBar } from '../components/player/PlayerBar';
import { DesignTokens } from '../theme/DesignTokens';
import { t, tf } from '../service/LocalizationService';
import { localMusicService } from '../service/LocalMusicService';
import { playerService, type SongInfo } from '../service/PlayerService';
import { getLocalPicUrl, type LocalMusicInfo } from '../core/music/local/LocalPlayback';
import { NavBar } from '../components/ui/NavBar';
import { RefreshContainer } from '../components/ui/RefreshContainer';
import { StateView } from '../components/ui/StateView';
import { hapticService } from '../service/HapticService';
import { appActionMenu, appConfirm } from '../service/DialogService';
import { SkeletonListItem } from '../components/common/SkeletonView';
import { EditMetadataSheet } from './LocalMusic/EditMetadataSheet';
import { LocalMusicActions } from './LocalMusic/LocalMusicActions';
import { TrackRow } from './LocalMusic/TrackRow';
import { Breakpoints } from '../theme/Breakpoints';
import { LazyDataSource } from '../utils/LazyDataSource';
import { pageScrollKey, ScrollMemoryHandle } from '../service/ScrollMemoryService';
import { playKeyOfIds } from '../service/PlayerService';
import { asNumber, asText } from '../utils/ValueCoerce';

const DOMAIN: number = 0x0001;
const TAG: string = 'LocalMusicPage';
/** 每次进入页面最多解析多少首的内嵌封面（原生解码，分批做） */
const MAX_COVER_EXTRACT_PER_VISIT: number = 12;

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
  /** 正在播放的那首的全局 key（源|songmid），列表高亮据此计算 */
  @StorageProp('playingSongKey') playingSongKey: string = '';
  /** 下拉刷新中（重新扫描曲库时保留当前列表） */
  @State isRefreshing: boolean = false;
  /** 元数据编辑弹窗 */
  @State showEditDialog: boolean = false;
  private editingTrack: LocalMusicInfo | null = null;
  private coverLoaded: Set<string> = new Set();
  /** 列表滚动控制与位置记忆（设置 → 列表 → 记住滚动位置） */
  private trackScroller: Scroller = new Scroller();
  private scrollMemory: ScrollMemoryHandle = new ScrollMemoryHandle(pageScrollKey('localMusic'), this.trackScroller);
  private scrollMemoryRestored: boolean = false;
  @StorageProp('rememberScrollPosition') rememberScrollPosition: boolean = true;

  aboutToAppear(): void {
    void this.loadLibrary();
  }

  aboutToDisappear(): void {
    // 离开页面记住位置（关闭「记住滚动位置」时写入会被内部忽略）
    this.scrollMemory.save(this.rememberScrollPosition);
    this.scrollMemory.dispose();
  }

  private async loadLibrary(): Promise<void> {
    this.isLoading = true;
    try {
      const list = localMusicService.getLibrary();
      // 老版本存下来的条目可能缺字段/类型不同，进 UI 前统一收敛（@Prop 会校验类型）
      const normalized: LocalMusicInfo[] = [];
      for (let i = 0; i < list.length; i++) {
        normalized.push(LocalMusicPage.sanitize(list[i]));
      }
      this.tracks = normalized;
      this.trackSource.reload(this.tracks);
      void this.loadCovers(normalized);
      // 数据进列表后：首次进入落回上次位置（重扫/下拉刷新不重复恢复）
      this.scrollMemory.markLoaded();
      if (!this.scrollMemoryRestored) {
        this.scrollMemoryRestored = true;
        this.scrollMemory.restore(this.rememberScrollPosition);
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'loadLibrary failed: %{public}s', JSON.stringify(err));
    } finally {
      this.isLoading = false;
    }
  }

  /** 曲库条目字段收敛：字符串给空串、时长给有限数字、封面缺省为空 */
  private static sanitize(track: LocalMusicInfo): LocalMusicInfo {
    const fixed: LocalMusicInfo = {
      id: asText(track.id),
      name: asText(track.name),
      singer: asText(track.singer),
      album: asText(track.album),
      duration: asNumber(track.duration),
      interval: asText(track.interval),
      filePath: asText(track.filePath),
      size: asNumber(track.size),
      picUrl: asText(track.picUrl),
    };
    return fixed;
  }

  /** 首次展示时异步补内嵌封面，避免卡住列表 */
  private async loadCovers(list: LocalMusicInfo[]): Promise<void> {
    // 每进一次页面最多解析这么多首：封面解析要走系统 AVMetadataExtractor（原生解码），
    // 一次刷一整个曲库既慢又容易把内存顶上去；没解析到的下次进来继续。
    let extracted: number = 0;
    for (let i = 0; i < list.length && extracted < MAX_COVER_EXTRACT_PER_VISIT; i++) {
      const track = list[i];
      if (this.coverLoaded.has(track.id)) {
        continue;
      }
      this.coverLoaded.add(track.id);
      extracted += 1;
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

  /**
   * 导入入口：让用户选「系统音频选择器」还是「文件管理」。
   *
   * 系统音频选择器由华为音乐提供，部分设备上打开是空白页（真机实测），
   * 所以给一条一定能用的通路：从文件管理里按扩展名挑音频。
   */
  private async chooseImportSource(): Promise<void> {
    const picked = await appActionMenu(t('local_import_title'), [
      t('local_import_from_music'),
      t('local_import_from_files'),
    ]);
    if (picked === 0) {
      await this.importMusic(false);
    } else if (picked === 1) {
      await this.importMusic(true);
    }
  }

  /** @param fromFiles true = 走文件管理选择器 */
  private async importMusic(fromFiles: boolean): Promise<void> {
    this.isLoading = true;
    const before = this.tracks.length;
    try {
      if (fromFiles) {
        await localMusicService.importFromFilePicker();
      } else {
        await localMusicService.importFromPicker();
      }
      await this.loadLibrary();
      const added = this.tracks.length - before;
      if (added <= 0) {
        // 取消选择 / 一首都没复制进来时给明确反馈，而不是一句「已导入 0 首」
        this.showToast(t('local_import_none'));
      } else {
        this.showToast(tf('local_imported', [added.toString()]));
      }
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

  /**
   * 下拉刷新：重新扫描本地曲库。
   * 与顶栏「重新扫描」的区别：不显示骨架、不弹提示，只在顶部转一圈（用户主动下拉时不打断当前浏览）。
   */
  private async refreshLibrary(): Promise<void> {
    try {
      await localMusicService.rescan();
      await this.loadLibrary();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'refreshLibrary failed: %{public}s', JSON.stringify(err));
    } finally {
      this.isRefreshing = false;
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

  @Builder
  TopBar() {
    // 统一顶部栏：返回按钮触控区/标题字号/沉浸式安全区都由 NavBar 负责
    NavBar({
      title: t('local_music'),
      trailing: (): void => {
        this.NavActions();
      },
    })
  }

  /**
   * 顶栏右侧的三个动作（播放全部 / 重新扫描 / 导入）。
   *
   * 必须放在 @Builder 方法里：把 LocalMusicActions 直接内联在 trailing 箭头函数里时，
   * ArkUI 不会把它当 builder 编译，运行时组件调用返回 undefined 直接崩（点击「本地音乐」闪退）。
   */
  @Builder
  NavActions() {
    LocalMusicActions({
      hasTracks: this.tracks.length > 0,
      onPlayAll: (): void => {
        void this.playTrack(0);
      },
      onRescan: (): void => {
        void this.rescan();
      },
      onImport: (): void => {
        void this.chooseImportSource();
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
          void this.chooseImportSource();
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
        // 下拉刷新：重新扫描曲库（自定义组件后面不能直接挂通用属性，用一层 Column 承担剩余高度）
        Column() {
          RefreshContainer({
            refreshing: $isRefreshing,
            onRefresh: (): void => {
              hapticService.selection();
              this.isRefreshing = true;
              void this.refreshLibrary();
            },
          }) {
            this.TrackList()
          }
        }
        .layoutWeight(1)
        .width('100%')
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
    // 顶部/底部安全区都由页面自己绘制（深色模式下底部手势区不能透出系统白底）
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /** 本地曲库列表（LazyForEach + 侧滑删除 + 大屏内容列居中） */
  @Builder
  TrackList() {
    List({ scroller: this.trackScroller }) {
      LazyForEach(this.trackSource, (track: LocalMusicInfo, index: number) => {
        ListItem() {
          TrackRow({
            title: track.name,
            // 结构化字段交给行组件按「设置 → 列表」拼装（本地音乐与其它列表一致）
            singer: track.singer,
            album: track.album,
            durationSeconds: Math.floor(track.duration / 1000),
            coverUrl: track.picUrl ?? '',
            active: playKeyOfIds('local', track.id, track.id) === this.playingSongKey,
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
        // key 带上序号：老数据里 id 可能重复/为空，重复 key 会让 LazyForEach 出现错行甚至崩
      }, (track: LocalMusicInfo, index: number) => `${track.id}_${index}`)
    }
    .width('100%')
    .layoutWeight(1)
    .cachedCount(6)
    .padding({
      left: Breakpoints.contentInset(this.windowWidthVp),
      right: Breakpoints.contentInset(this.windowWidthVp),
    })
  }
}

interface PromptDialogResult {
  index: number;
}
