// 歌单详情页 - 对应 src/screens/SonglistDetail/index.tsx
// 显示歌单信息和歌曲列表

import hilog from '@ohos.hilog';
import { showAppToast, TOAST_DURATION_SHORT } from '../utils/Toast';
import { PlayerBar } from '../components/player/PlayerBar';
import { getSongListDetail, setDownloadContext, download, type SongListDetailResult } from '../core/music/MusicFeatureEntry';
import { NavigationParams } from '../service/NavigationService';
import { playerService, SongInfo } from '../service/PlayerService';
import { navigationService } from '../service/NavigationService';
import { common } from '@kit.AbilityKit';
import { addMusicToList, getUserList, getUserListMusic, LIST_IDS, MusicItem, ListInfo } from '../service/ListService';
import { createUserList, moveMusicInList, removeMusicsFromList, replaceUserListMusic } from '../service/ListService';
import type { BusinessError } from '@kit.BasicServicesKit';
import { emitSearchRequest } from '../service/EventBus';
import { buildShareText, getMusicDetailPageUrl } from '../core/music/MusicDetailUrl';
import { shareText } from '../service/ShareService';
import {
  collectOnlineSonglist,
  uncollectOnlineSonglist,
  syncUserListFromOnline,
  isOnlineSonglistCollected,
} from '../service/UserListSyncService';
import { findUserListByBinding } from '../service/ListService';
import { dislikeList } from '../core/dislike/DislikeList';
import { showSongItemMenu, showSonglistMoreMenu } from './SonglistDetail/SonglistMenus';
import { songRowToListItem, songRowToMusicInfo, songRowToQueueItem } from '../core/list/SongMappers';
import { appActionMenu } from '../service/DialogService';
import { ListRow } from '../components/ui/ListRow';
import { NavBar } from '../components/ui/NavBar';
import { InputSheet } from '../components/ui/InputSheet';
import { SelectSheet } from '../components/ui/SelectSheet';
import type { SettingOption } from '../components/ui/SettingsTypes';
import type { SongItem, SonglistInfo } from './SonglistDetail/SonglistTypes';
import { SonglistDetailHeader } from './SonglistDetail/SonglistDetailHeader';
import { SonglistBatchBar } from './SonglistDetail/SonglistBatchBar';
import { SonglistSortSheet } from './SonglistDetail/SonglistSortSheet';
import type { MusicInfo } from '../types/MusicTypes';
import { DesignTokens } from '../theme/DesignTokens';
import { formatPlayTime } from '../utils/CommonUtils';
import { SkeletonListItem } from '../components/common/SkeletonView';
import { ErrorView } from '../components/common/ErrorView';
import { t, tf, sourceLabel } from '../service/LocalizationService';
import { type SortField, type SortOrder } from '../utils/ListTools';
import {
  sortRows,
  dedupeRows,
  countDuplicateGroupsOf,
  persistLocalOrder,
} from './SonglistDetail/SonglistListOps';
import { loadScrollOffset, saveScrollOffset } from './SonglistDetail/SonglistScrollMemory';
import { buildQueue, buildFullQueue, resolvePlayUrl, toMusicInfo } from './SonglistDetail/SonglistPlayback';

interface PromptActionResult {
  index: number;
}

interface MenuActionItem {
  label: string;
  action: () => void;
}

@Component
export struct SonglistDetailPage {
  @StorageProp('theme') theme: string = 'light';
  // 列表显示项（设置 → 列表设置）
  @StorageProp('showListSource') showListSource: boolean = true;
  @StorageProp('showListAlbum') showListAlbum: boolean = true;
  @StorageProp('showListDuration') showListDuration: boolean = true;
  @StorageProp('rememberScrollPosition') rememberScrollPosition: boolean = true;
  /** 收藏/同步进行中（避免重复触发） */
  private collectBusy: boolean = false;
  /** 点击列表项：播放整个列表 / 只播这一首（设置 → 列表） */
  @StorageProp('listClickPlay') listClickPlay: boolean = false;

  /** 按压反馈：列表行/按钮变淡 */
  @Styles
  pressDim() {
    .opacity(0.65)
  }

  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State creator: string = t('unknown');
  @State playCount: string = '0';
  @State songList: SongItem[] = [];
  @State isLoading: boolean = true;
  @State hasError: boolean = false;
  @State headerCompact: boolean = false;
  @State listCoverLoadFailed: boolean = false;

  // ===== 列表能力：多选 / 排序 / 去重（对齐安卓版歌单菜单）=====
  /** 多选模式：行点击变为勾选，底部出现批量操作栏 */
  @State selectMode: boolean = false;
  /** 已选下标（用下标而非 id，重复歌曲也能精确删掉某一首） */
  @State selectedIndexes: number[] = [];
  /** 排序设置面板 */
  @State showSortSheet: boolean = false;
  @State sortField: string = 'name';
  @State sortOrder: string = 'up';
  /** 去重时是否忽略 Live/伴奏等版本后缀 */
  @State dedupeFilterVariant: boolean = true;

  // ===== 本地列表的「调整位置 / 移动到其他列表」（对齐安卓版 change_position / move_to）=====
  @State showMovePositionSheet: boolean = false;
  @State movePositionValue: string = '';
  private movePositionTarget: SongItem | null = null;
  @State showMoveToListSheet: boolean = false;
  @State moveToListOptions: SettingOption[] = [];
  private moveToListTarget: SongItem | null = null;

  // 歌单信息
  @State listInfo: SonglistInfo = {
    source: '',
    id: '',
    name: t('loading'),
    creator: '',
    pic: '',
    desc: '',
    playCount: 0,
  };

  // 防止重复加载标志
  private detailLoaded: boolean = false;
  /** 最近一次加载的歌单参数，用于失败重试 */
  private lastSourceId: string = '';
  private lastListId: string = '';
  private songListScroller: Scroller = new Scroller();

  /** 失败重试：用上次的参数重新拉取 */
  private reloadDetail(): void {
    if (this.lastSourceId.length === 0 || this.lastListId.length === 0) {
      return;
    }
    void this.loadSonglistDetail(this.lastSourceId, this.lastListId);
  }

  /** 列表副标题：歌手 [· 专辑] [· 音源]，按设置裁剪 */
  private buildSubtitle(song: SongItem): string {
    const parts: string[] = [];
    if (song.singer && song.singer.length > 0) {
      parts.push(song.singer);
    }
    if (this.showListAlbum && song.album && song.album.length > 0) {
      parts.push(song.album);
    }
    if (this.showListSource && song.source && song.source.length > 0) {
      parts.push(sourceLabel(song.source));
    }
    return parts.join(' · ');
  }

  /** 行尾时长（无时长信息时不显示占位） */
  private formatSongDuration(song: SongItem): string {
    if (!song.duration || song.duration <= 0) {
      return '';
    }
    return formatPlayTime(song.duration);
  }

  /** 滚动位置记忆的存储键（按歌单区分） */
  /** 退出页面时记住滚动位置（读写由 SonglistScrollMemory 负责） */
  private saveScrollPosition(): void {
    void saveScrollOffset(this.lastSourceId, this.lastListId, this.getSongListOffsetY(),
      this.rememberScrollPosition, this.detailLoaded);
  }

  /** 列表渲染后恢复上次滚动位置 */
  private async restoreScrollPosition(): Promise<void> {
    if (!this.rememberScrollPosition) {
      return;
    }
    const offset = await loadScrollOffset(this.lastSourceId, this.lastListId);
    if (offset <= 0) {
      return;
    }
    // 等一帧让列表完成布局，否则 scrollTo 会被忽略
    setTimeout(() => {
      try {
        this.songListScroller.scrollTo({ xOffset: 0, yOffset: offset, animation: false });
        hilog.info(0x0001, 'SonglistDetail', 'Scroll restored to %{public}d', offset);
      } catch (err) {
        hilog.warn(0x0001, 'SonglistDetail', 'scrollTo failed: %{public}s', JSON.stringify(err));
      }
    }, 120);
  }

  private getSongListOffsetY(): number {
    try {
      const y = this.songListScroller.currentOffset().yOffset;
      if (typeof y === 'number' && isFinite(y)) {
        return y;
      }
      return 0;
    } catch (_e) {
      return 0;
    }
  }

  private getSourceLabel(): string {
    const src = (this.listInfo.source ?? '').trim();
    if (src.length === 0) {
      return '--';
    }
    return src.toUpperCase();
  }


  aboutToAppear() {
    hilog.info(0x0001, 'SonglistDetail', 'SonglistDetailPage appearing');
    // 初始化下载上下文
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    setDownloadContext(context);
    // 防止重复加载
    if (this.detailLoaded) {
      hilog.info(0x0001, 'SonglistDetail', 'Detail already loaded, skipping');
      return;
    }
    // 从导航参数获取歌单信息
    const params = navigationService.getCurrentParams() as NavigationParams;
    if (params && params.songListId && params.songListSource) {
      hilog.info(0x0001, 'SonglistDetail', 'Loading with params - id: %{public}s, source: %{public}s',
        params.songListId, params.songListSource);
      this.loadSonglistDetail(params.songListSource, params.songListId);
    } else {
      hilog.warn(0x0001, 'SonglistDetail', 'No navigation params found');
      this.isLoading = false;
      this.hasError = true;
    }
  }

  aboutToDisappear(): void {
    this.saveScrollPosition();
  }

  onBackPressed(): boolean {
    navigationService.back();
    return true;
  }

  /** 头部：交给 SonglistDetailHeader（展开/收缩两态） */
  @Builder
  Header() {
    SonglistDetailHeader({
      listName: this.listInfo.name,
      creator: this.listInfo.creator,
      description: this.listInfo.desc,
      cover: this.listInfo.pic,
      sourceLabel: this.getSourceLabel(),
      songCount: this.songList.length,
      playCount: this.listInfo.playCount,
      compact: this.headerCompact,
      onPlayAll: (): void => {
        void this.playAll();
      },
      onCollect: (): void => {
        void this.toggleCollect();
      },
    })
  }

  @Builder
  SongList() {
    List({ space: 8, scroller: this.songListScroller }) {
      ForEach(this.songList, (song: SongItem, index: number) => {
        ListItem() {
          ListRow({
            index: index + 1,
            title: song.name,
            subtitle: this.buildSubtitle(song),
            trailingText: this.showListDuration ? this.formatSongDuration(song) : '',
            active: song.isPlaying,
            divider: false,
            onTap: (): void => {
              if (this.selectMode) {
                this.toggleSelect(index);
              } else {
                void this.playSong(index);
              }
            },
            onLongPress: (): void => {
              if (!this.selectMode) {
                void this.openSongMenu(song);
              }
            },
            trailing: (): void => {
              this.SongRowTrailing(song, index);
            },
          })
        }
        .stateStyles({ pressed: this.pressDim })
      }, (song: SongItem, index: number) => `${song.id}_${song.source}_${index}`)
    }
    .width('100%')
    .layoutWeight(1)
    .padding({ left: 12, right: 12, bottom: 8 })
    .edgeEffect(EdgeEffect.None)
    .onDidScroll(() => {
      const y = this.getSongListOffsetY();
      if (y > 18 && !this.headerCompact) {
        this.headerCompact = true;
      } else if (y <= 4 && this.headerCompact) {
        this.headerCompact = false;
      }
    })
  }

  /** 行尾：多选态给勾选圆点，普通态给 ⋮ 菜单 */
  @Builder
  SongRowTrailing(song: SongItem, index: number) {
    if (this.selectMode) {
      Stack() {
        if (this.isSelected(index)) {
          SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
            .fontSize(26)
            .fontColor([DesignTokens.accent()])
        } else {
          Circle({ width: 22, height: 22 })
            .fill(Color.Transparent)
            .stroke(DesignTokens.labelTertiary(this.theme))
            .strokeWidth(1.5)
        }
      }
      .width(DesignTokens.touchTarget())
      .height(DesignTokens.touchTarget())
    } else {
      Stack() {
        Circle({ width: 28, height: 28 })
          .fill(DesignTokens.mutedFill(this.theme))
        Image($r('app.media.ic_pd_more'))
          .width(14)
          .height(14)
          .fillColor(DesignTokens.labelSecondary(this.theme))
      }
      .width(DesignTokens.touchTarget())
      .height(DesignTokens.touchTarget())
      .onClick(() => {
        void this.openSongMenu(song);
      })
    }
  }

  // NavDestination onReady callback
  onReady(params: Record<string, object | string | number | boolean | undefined>): void {
    // 防止重复加载
    if (this.detailLoaded) {
      hilog.info(0x0001, 'SonglistDetail', 'Detail already loaded, skipping onReady');
      return;
    }
    const songListId: string = (params.songListId as string) || '';
    const songListSource: string = (params.songListSource as string) || '';
    hilog.info(0x0001, 'SonglistDetail', 'onReady - id: %{public}s, source: %{public}s', songListId, songListSource);
    if (songListId && songListSource) {
      this.loadSonglistDetail(songListSource, songListId);
    } else {
      hilog.error(0x0001, 'SonglistDetail', 'Missing params: id=%{public}s, source=%{public}s', songListId, songListSource);
    }
  }

  async loadSonglistDetail(source: string, id: string) {
    hilog.info(0x0001, 'SonglistDetail', 'Loading detail for source: %{public}s, id: %{public}s', source, id);
    this.isLoading = true;
    this.hasError = false;
    this.lastSourceId = source;
    this.lastListId = id;

    if (source === 'local') {
      this.loadLocalSonglistDetail(id);
      return;
    }

    // 检查是否支持该源的歌单详情
    const supportedSources = ['kw', 'tx', 'kg', 'wy', 'mg'];
    if (!supportedSources.includes(source)) {
      hilog.warn(0x0001, 'SonglistDetail', 'Source %{public}s does not support song list detail', source);
      this.isLoading = false;
      this.detailLoaded = false;
      return;
    }

    try {
      const result: SongListDetailResult = await getSongListDetail(id, 1, source);
      hilog.info(0x0001, 'SonglistDetail', 'API returned: %{public}s songs, info: %{public}s',
        result.list.length.toString(), JSON.stringify(result.info));

      // 检查结果是否为空
      if (result.list.length === 0) {
        hilog.warn(0x0001, 'SonglistDetail', 'Empty song list returned for source: %{public}s', source);
      }

      this.listInfo = {
        source: source,
        id: id,
        name: result.info.name || t('unknown_playlist'),
        creator: result.info.author || t('unknown'),
        pic: result.info.img || '',
        desc: result.info.desc || '',
        playCount: this.parsePlayCount(result.info.play_count),
      };
      this.listCoverLoadFailed = false;
      const items: SongItem[] = [];
      for (let i = 0; i < result.list.length; i++) {
        const m: MusicInfo = result.list[i];
        const durationVal = this.parseDurationToSeconds(m.interval);
        const item: SongItem = {
          id: m.songmid || m.id || '',
          name: m.name || '',
          singer: m.singer || '',
          album: m.albumName || m.album || '',
          duration: durationVal,
          isPlaying: false,
          source: source,
          pic: m.img || m.pic || '',
          albumId: m.albumId || '',
          songmid: m.songmid || '',
          strMediaMid: m.strMediaMid || '',
          hash: m.hash || '',
          copyrightId: m.copyrightId || '',
        };
        items.push(item);
      }
      hilog.info(0x0001, 'SonglistDetail', 'Parsed %{public}s songs to display', items.length.toString());
      this.songList = items;
      this.detailLoaded = true;
      void this.restoreScrollPosition();
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to load song list detail: %{public}s', JSON.stringify(err));
      this.hasError = true;
      this.detailLoaded = false;
    } finally {
      this.isLoading = false;
    }
  }

  private loadLocalSonglistDetail(id: string): void {
    try {
      const listInfo: ListInfo | undefined = getUserList().find((item: ListInfo) => item.id === id);
      if (!listInfo) {
        hilog.warn(0x0001, 'SonglistDetail', 'Local list not found: %{public}s', id);
        this.hasError = true;
        this.detailLoaded = false;
        return;
      }

      const localSongs: MusicItem[] = getUserListMusic(id);
      this.listInfo = {
        source: 'local',
        id: listInfo.id,
        name: listInfo.name,
        creator: t('local_playlist'),
        pic: listInfo.pic || (localSongs[0]?.pic ?? ''),
        desc: listInfo.desc || '',
        playCount: 0,
      };
      this.listCoverLoadFailed = false;

      this.songList = this.musicRowsFromLocal(localSongs);
      this.detailLoaded = true;
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to load local song list: %{public}s', JSON.stringify(err));
      this.hasError = true;
      this.detailLoaded = false;
    } finally {
      this.isLoading = false;
    }
  }

  /** 本地曲库行 -> 页面行（首次加载与位置调整后的刷新共用一份映射） */
  private musicRowsFromLocal(list: MusicItem[]): SongItem[] {
    const rows: SongItem[] = [];
    for (let i = 0; i < list.length; i++) {
      const song = list[i];
      rows.push({
        id: song.id || '',
        name: song.name || '',
        singer: song.singer || '',
        album: song.album || '',
        duration: song.duration || 0,
        isPlaying: false,
        source: song.source || 'local',
        pic: song.pic || '',
        albumId: song.albumId || '',
        songmid: song.id || '',
        hash: '',
        strMediaMid: '',
        copyrightId: '',
      });
    }
    return rows;
  }

  parsePlayCount(countStr: string): number {
    if (!countStr) return 0;
    const num = parseFloat(countStr);
    return isNaN(num) ? 0 : num;
  }

  parseDurationToSeconds(interval: string | null): number {
    if (!interval) return 0;
    const parts = interval.split(':');
    if (parts.length === 2) {
      const minutes = parseInt(parts[0]);
      const seconds = parseInt(parts[1]);
      if (!isNaN(minutes) && !isNaN(seconds)) {
        return minutes * 60 + seconds;
      }
    }
    return 0;
  }

  formatPlayCountDisplay(count: number): string {
    if (count >= 100000000) {
      return (count / 100000000).toFixed(1) + ' ' + t('billion_unit');
    } else if (count >= 10000) {
      return (count / 10000).toFixed(1) + ' ' + t('ten_thousand_unit');
    }
    return count.toString();
  }

  // 播放单首歌曲
  async playSong(index: number): Promise<void> {
    if (this.songList.length === 0) return;
    const song = this.songList[index];
    if (!song) {
      hilog.error(0x0001, 'SonglistDetail', 'Song not found at index: %{public}d', index);
      return;
    }
    hilog.info(0x0001, 'SonglistDetail', 'Playing song: %{public}s from source: %{public}s, index: %{public}d', song.name, song.source, index);

    // 更新 UI 播放状态
    for (let i = 0; i < this.songList.length; i++) {
      this.songList[i].isPlaying = (i === index);
    }
    this.songList = this.songList;

    try {
      // 队列与平台对象都交给 SonglistPlayback 统一构建
      const songInfos: SongInfo[] = buildQueue(this.songList, this.listInfo.pic);

      hilog.info(0x0001, 'SonglistDetail', 'Getting music URL for song: %{public}s', song.name);
      const url: string | null = await resolvePlayUrl(toMusicInfo(song));

      if (!url || url.length === 0) {
        hilog.error(0x0001, 'SonglistDetail', 'Failed to get music URL for song: %{public}s', song.name);
        // 失败时回滚播放态提示，避免列表看起来"在播但没声音"
        for (let i = 0; i < this.songList.length; i++) {
          this.songList[i].isPlaying = false;
        }
        this.songList = this.songList;
        this.showToast(t('toast_play_url_failed'));
        return;
      }

      // 更新songInfo的URL
      songInfos[index].url = url;
      
      // 队列语义对齐安卓版：点击行都用「整张歌单」入队并立即播放
      // - listClickPlay=true：直接用当前已加载的列表（安卓 onPlayList）
      // - listClickPlay=false（默认）：先播已加载页，随后后台补全全部页替换队列（安卓渐进式 temp list）
      playerService.setPlayList(songInfos, index);
      hilog.info(0x0001, 'SonglistDetail', 'PlayList set with %{public}d songs, starting from index %{public}d',
        songInfos.length, index);
      if (!this.listClickPlay) {
        void this.fillQueueWithAllPages(song);
      }

      hilog.info(0x0001, 'SonglistDetail', 'Got music URL, setting source and playing...');
      await playerService.playFromSelection(songInfos[index], url, song.duration);
      hilog.info(0x0001, 'SonglistDetail', 'Song playback started successfully');
    } catch (error) {
      hilog.error(0x0001, 'SonglistDetail', 'Play song failed: %{public}s', JSON.stringify(error));
    }
  }

  /**
   * 后台拉取歌单全部页并补全队列（安卓 handlePlay 里 getListDetailAll 的等价实现）
   * 只补齐当前仍在播放的那首歌所属的队列，避免切歌后覆盖
   */
  private async fillQueueWithAllPages(anchorSong: SongItem): Promise<void> {
    if (!this.listInfo.source || this.listInfo.source === 'local' || this.listInfo.id.length === 0) {
      return;
    }
    const queue = await buildFullQueue(this.listInfo.source, this.listInfo.id, this.listInfo.pic, this.songList.length);
    if (!queue) {
      return;
    }
    playerService.refineQueueWithFullList(queue);
    hilog.info(0x0001, 'SonglistDetail', 'Queue filled with all pages: %{public}d songs (anchor=%{public}s)',
      queue.length, anchorSong.name);
  }

  // 播放全部歌曲
  async playAll(): Promise<void> {
    if (this.songList.length === 0) return;
    hilog.info(0x0001, 'SonglistDetail', 'Play all songs from index 0');
    // 设置整个播放列表，从第一首开始
    const songInfos: SongInfo[] = buildQueue(this.songList, this.listInfo.pic);
    const firstSong = this.songList[0];
    const url: string | null = await resolvePlayUrl(toMusicInfo(firstSong));

    if (!url || url.length === 0) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to get music URL for first song: %{public}s', firstSong.name);
      this.showToast(t('toast_play_url_failed'));
      return;
    }

    // 更新第一首歌曲的URL
    songInfos[0].url = url;
    
    // 设置播放列表（现在第一首歌曲的URL已经可用）
    playerService.setPlayList(songInfos, 0);

    hilog.info(0x0001, 'SonglistDetail', 'Got music URL, setting source and playing...');
    await playerService.playFromSelection(songInfos[0], url, firstSong.duration);
  }

  // 格式化秒数为时间字符串
  formatPlayTime(seconds: number): string {
    if (isNaN(seconds) || seconds < 0) return '00:00';
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
  }

  /**
   * 收藏歌单（对齐安卓版 handleCollect）
   * - 未收藏：创建绑定在线歌单的自建歌单（全量拉取歌曲），在「我的列表」可见
   * - 已收藏：弹菜单，可「更新歌单内容」（列表级同步）或「取消收藏」
   */
  async toggleCollect(): Promise<void> {
    if (this.listInfo.source === 'local') {
      this.showToast(t('toast_local_list_no_collect'));
      return;
    }
    if (this.collectBusy) {
      return;
    }
    try {
      hilog.info(0x0001, 'SonglistDetail', 'Collect songlist: %{public}s', this.listInfo.name);
      const collected = isOnlineSonglistCollected(this.listInfo.source, this.listInfo.id);
      if (collected) {
        this.openCollectedMenu();
        return;
      }
      // 未收藏：全量拉取并创建绑定列表（耗时操作，期间禁止重复触发）
      this.collectBusy = true;
      this.showToast(t('toast_collecting'));
      const result = await collectOnlineSonglist(
        this.listInfo.source, this.listInfo.id, this.listInfo.name, this.listInfo.pic);
      this.showToast(tf('toast_collected_count', [String(result.localCount ?? 0)]));
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(0x0001, 'SonglistDetail', 'Failed to toggle collect: %{public}s', errorMsg);
      this.showToast(t('toast_operation_failed') + ': ' + errorMsg);
    } finally {
      this.collectBusy = false;
    }
  }

  /** 已收藏时的菜单：更新内容 / 取消收藏 */
  private openCollectedMenu(): void {
    const primary = DesignTokens.labelPrimary(this.theme);
    const tertiary = DesignTokens.labelTertiary(this.theme);
    this.getUIContext().getPromptAction().showActionMenu({
      title: this.listInfo.name,
      buttons: [
        { text: t('list_sync_content'), color: primary },
        { text: t('toast_uncollected_action'), color: DesignTokens.danger() },
        { text: t('cancel'), color: tertiary },
      ],
    }, (err: BusinessError, data: PromptActionResult) => {
      if (err) {
        return;
      }
      if (data.index === 0) {
        void this.syncBoundList();
      } else if (data.index === 1) {
        void this.uncollect();
      }
    });
  }

  /** 更新歌单内容（列表级同步） */
  private async syncBoundList(): Promise<void> {
    const info = findUserListByBinding(this.listInfo.source, this.listInfo.id);
    if (!info) {
      this.showToast(t('toast_operation_failed'));
      return;
    }
    try {
      this.showToast(t('toast_syncing'));
      const result = await syncUserListFromOnline(info.id);
      if (result.ok) {
        this.showToast(tf('toast_sync_done_count', [String(result.count)]));
      } else {
        this.showToast(t('toast_sync_local_failed'));
      }
    } catch (err) {
      hilog.warn(0x0001, 'SonglistDetail', 'syncBoundList failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_sync_local_failed'));
    }
  }

  /** 取消收藏（删除对应自建歌单） */
  private async uncollect(): Promise<void> {
    try {
      const confirmed = await this.showConfirmDialog(
        t('toast_uncollected_action'),
        tf('confirm_uncollect', [this.listInfo.name]));
      if (!confirmed) {
        return;
      }
      await uncollectOnlineSonglist(this.listInfo.source, this.listInfo.id);
      this.showToast(tf('toast_uncollected', [this.listInfo.name]));
    } catch (err) {
      hilog.warn(0x0001, 'SonglistDetail', 'uncollect failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_operation_failed'));
    }
  }

  // 显示提示
  private showToast(message: string): void {
    showAppToast(this.getUIContext(), message, TOAST_DURATION_SHORT);
  }

  // 下载歌单
  async downloadAll(): Promise<void> {
    try {
      hilog.info(0x0001, 'SonglistDetail', 'Download songlist: %{public}s', this.listInfo.name);
      
      if (this.songList.length === 0) {
        this.showToast(t('toast_songlist_empty'));
        return;
      }
      
      // 确认下载
      const confirmed = await this.showConfirmDialog(
        t('download_confirm_title'),
        tf('confirm_download_songlist', [this.listInfo.name, this.songList.length.toString()])
      );
      
      if (!confirmed) {
        this.showToast(t('toast_cancel_download'));
        return;
      }
      
      // 开始下载
      let successCount = 0;
      let failCount = 0;
      
      for (let i = 0; i < this.songList.length; i++) {
        const song = this.songList[i];
        try {
          await this.downloadSong(song);
          successCount++;
          
          // 更新进度
          this.showToast(tf('toast_downloading_progress', [(i + 1).toString(), this.songList.length.toString()]));
        } catch (err) {
          hilog.error(0x0001, 'SonglistDetail', 'Failed to download song %{public}s: %{public}s', 
            song.name, JSON.stringify(err));
          failCount++;
        }
      }
      
      // 显示结果
      if (successCount > 0) {
        this.showToast(tf('toast_download_summary', [successCount.toString(), failCount.toString()]));
      } else {
        this.showToast(t('toast_download_failed_network'));
      }
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(0x0001, 'SonglistDetail', 'Failed to download songlist: %{public}s', errorMsg);
      this.showToast(t('toast_download_failed') + ': ' + errorMsg);
    }
  }



  // 下载单首歌曲
  private async downloadSong(song: SongItem): Promise<void> {
    try {
      const musicInfo: MusicInfo = songRowToMusicInfo(song);
      // 使用真实的下载服务
      const taskId = await download.startDownload({
        musicInfo: musicInfo,
      });
      hilog.info(0x0001, 'SonglistDetail', 'Download started: %{public}s, taskId: %{public}s', song.name, taskId);
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to download song %{public}s: %{public}s',
        song.name, JSON.stringify(err));
      const msg = err instanceof Error ? err.message : JSON.stringify(err);
      throw new Error(msg);
    }
  }

  /** 系统确认对话框（Promise 化，取消返回 false） */
  private showConfirmDialog(title: string, message: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      try {
        this.getUIContext().getPromptAction().showDialog({
          title,
          message,
          buttons: [
            { text: t('cancel'), color: DesignTokens.labelSecondary(this.theme) },
            { text: t('confirm'), color: DesignTokens.accent() },
          ],
        }, (err: object, data: PromptActionResult) => {
          resolve(!err && data.index === 1);
        });
      } catch (err) {
        hilog.warn(0x0001, 'SonglistDetail', 'showConfirmDialog failed: %{public}s', JSON.stringify(err));
        resolve(false);
      }
    });
  }


  // 显示操作菜单

  /** 二级菜单：多选 / 不喜欢 / 来源详情 / 查看歌手 / 查看专辑 */

  /** 下一首播放（插到当前曲目之后） */

  /** 打开该歌曲在对应平台的详情页 */

  /** 打开外部链接 */

  /** 不喜欢：按 歌曲 / 歌手 / 歌名 三种粒度屏蔽（与播放页一致） */

  /** 写入屏蔽规则（与播放页 addDislike 行为一致） */

  /** SongItem -> MusicInfo（分享/详情页链接用） */

  // ===== 多选批量操作 =====

  /** 进入多选模式，并把触发的那首歌默认选中 */
  private enterSelectMode(song?: SongItem): void {
    this.selectMode = true;
    if (song) {
      const index = this.indexOfSong(song);
      this.selectedIndexes = index >= 0 ? [index] : [];
    } else {
      this.selectedIndexes = [];
    }
  }

  private exitSelectMode(): void {
    this.selectMode = false;
    this.selectedIndexes = [];
  }

  private indexOfSong(song: SongItem): number {
    for (let i = 0; i < this.songList.length; i++) {
      if (this.songList[i] === song) {
        return i;
      }
    }
    return -1;
  }

  private isSelected(index: number): boolean {
    return this.selectedIndexes.indexOf(index) >= 0;
  }

  private toggleSelect(index: number): void {
    const next = this.selectedIndexes.slice();
    const at = next.indexOf(index);
    if (at >= 0) {
      next.splice(at, 1);
    } else {
      next.push(index);
    }
    this.selectedIndexes = next;
  }

  private selectAllSongs(): void {
    if (this.selectedIndexes.length === this.songList.length) {
      this.selectedIndexes = [];
      return;
    }
    const all: number[] = [];
    for (let i = 0; i < this.songList.length; i++) {
      all.push(i);
    }
    this.selectedIndexes = all;
  }

  private selectedSongs(): SongItem[] {
    const result: SongItem[] = [];
    for (let i = 0; i < this.selectedIndexes.length; i++) {
      const song = this.songList[this.selectedIndexes[i]];
      if (song) {
        result.push(song);
      }
    }
    return result;
  }

  /** 批量添加到自建歌单（默认列表） */
  private async batchAddToPlaylist(): Promise<void> {
    const songs = this.selectedSongs();
    if (songs.length === 0) {
      this.showToast(t('toast_no_selection'));
      return;
    }
    let added = 0;
    for (let i = 0; i < songs.length; i++) {
      try {
        await addMusicToList(LIST_IDS.DEFAULT, songRowToListItem(songs[i]));
        added++;
      } catch (err) {
        hilog.warn(0x0001, 'SonglistDetail', 'batch add failed: %{public}s', JSON.stringify(err));
      }
    }
    this.showToast(tf('toast_batch_added', [added.toString()]));
    this.exitSelectMode();
  }

  /** 批量下载 */
  private async batchDownload(): Promise<void> {
    const songs = this.selectedSongs();
    if (songs.length === 0) {
      this.showToast(t('toast_no_selection'));
      return;
    }
    const confirmed = await this.showConfirmDialog(
      t('player_download'),
      tf('confirm_download_songs', [songs.length.toString()]));
    if (!confirmed) {
      return;
    }
    let done = 0;
    for (let i = 0; i < songs.length; i++) {
      try {
        await this.downloadSong(songs[i]);
        done++;
        this.showToast(tf('toast_downloading_progress', [(i + 1).toString(), songs.length.toString()]));
      } catch (err) {
        hilog.warn(0x0001, 'SonglistDetail', 'batch download failed: %{public}s', JSON.stringify(err));
      }
    }
    this.showToast(tf('toast_batch_downloaded', [done.toString()]));
    this.exitSelectMode();
  }

  /** 批量移出本地歌单（在线歌单不支持，避免用户误以为云端被改） */
  private async batchRemove(): Promise<void> {
    const songs = this.selectedSongs();
    if (songs.length === 0) {
      this.showToast(t('toast_no_selection'));
      return;
    }
    if (this.listInfo.source !== 'local') {
      this.showToast(t('toast_online_list_readonly'));
      return;
    }
    const confirmed = await this.showConfirmDialog(
      t('list_remove_songs'),
      tf('confirm_remove_songs', [songs.length.toString()]));
    if (!confirmed) {
      return;
    }
    const ids: string[] = [];
    for (let i = 0; i < songs.length; i++) {
      ids.push(songs[i].id);
    }
    const removed = await removeMusicsFromList(this.listInfo.id, ids);
    this.songList = this.songList.filter((song: SongItem) => !this.containsSong(songs, song));
    this.exitSelectMode();
    this.showToast(tf('toast_removed_count', [removed.toString()]));
  }

  private containsSong(songs: SongItem[], target: SongItem): boolean {
    for (let i = 0; i < songs.length; i++) {
      if (songs[i] === target) {
        return true;
      }
    }
    return false;
  }

  // ===== 排序 =====



  private applySort(): void {
    const field = this.sortField as SortField;
    const order = this.sortOrder as SortOrder;
    const locale = this.language.replace('_', '-');
    this.songList = sortRows(this.songList, field, order, locale);
    this.showSortSheet = false;
    this.showToast(tf('toast_sorted_count', [this.songList.length.toString()]));

    // 本地列表排序结果要落库，否则退出再进又变回原顺序
    if (this.canEditLocalList()) {
      void persistLocalOrder(this.listInfo.id, this.songList);
    }
  }

  // ===== 去重 =====

  private async runDedupe(): Promise<void> {
    if (this.songList.length < 2) {
      this.showToast(t('list_dedupe_none'));
      return;
    }
    const duplicateGroups = countDuplicateGroupsOf(this.songList, this.dedupeFilterVariant);
    if (duplicateGroups === 0) {
      this.showToast(t('list_dedupe_none'));
      return;
    }
    const confirmed = await this.showConfirmDialog(
      t('list_dedupe'),
      tf('confirm_dedupe_songs', [duplicateGroups.toString()]));
    if (!confirmed) {
      return;
    }
    const outcome = dedupeRows(this.songList, this.dedupeFilterVariant);
    const removed = outcome.removed;
    this.songList = outcome.rows;
    // 本地歌单：同步把重复项从存储里删掉，避免下次进来又出现
    if (this.listInfo.source === 'local') {
      await this.persistLocalOrder();
    }
    this.exitSelectMode();
    this.showToast(tf('toast_dedupe_done', [removed.toString()]));
  }

  /** 把当前顺序写回本地歌单（排序/去重后调用） */
  private async persistLocalOrder(): Promise<void> {
    if (this.listInfo.source !== 'local') {
      return;
    }
    try {
      const existing = getUserListMusic(this.listInfo.id);
      const byId = new Map<string, MusicItem>();
      for (let i = 0; i < existing.length; i++) {
        byId.set(existing[i].id, existing[i]);
      }
      for (let i = 0; i < this.songList.length; i++) {
        const song = this.songList[i];
        if (!byId.has(song.id)) {
          byId.set(song.id, songRowToListItem(song));
        }
      }
      const keep: MusicItem[] = [];
      for (let i = 0; i < this.songList.length; i++) {
        const item = byId.get(this.songList[i].id);
        if (item && keep.indexOf(item) < 0) {
          keep.push(item);
        }
      }
      await replaceUserListMusic(this.listInfo.id, keep);
    } catch (err) {
      hilog.warn(0x0001, 'SonglistDetail', 'persistLocalOrder failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 把在线歌单同步成本地自建歌单（同名则覆盖更新） */
  private async syncToLocalList(): Promise<void> {
    if (this.songList.length === 0) {
      this.showToast(t('toast_songlist_empty'));
      return;
    }
    const name = this.listInfo.name || t('songlist_title');
    const confirmed = await this.showConfirmDialog(
      t('list_sync_local'),
      tf('confirm_sync_local', [name, this.songList.length.toString()]));
    if (!confirmed) {
      return;
    }
    try {
      const existing = getUserList().find((item: ListInfo) => item.name === name);
      let listId = existing ? existing.id : '';
      if (!listId) {
        const created = await createUserList(name);
        listId = created.id;
      }
      const items: MusicItem[] = [];
      for (let i = 0; i < this.songList.length; i++) {
        items.push(songRowToListItem(this.songList[i]));
      }
      await replaceUserListMusic(listId, items);
      this.showToast(tf('toast_sync_local_done', [name, items.length.toString()]));
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'syncToLocalList failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_sync_local_failed'));
    }
  }

  /** 打开单曲菜单（长按行 / 行尾 ⋮）：动作集合见 SonglistMenus */
  private async openSongMenu(song: SongItem): Promise<void> {
    await showSongItemMenu(song, {
      onPlayLater: (target: SongItem): void => {
        playerService.insertNext(songRowToQueueItem(target));
        this.showToast(tf('toast_play_later_added', [target.name]));
      },
      onAddToList: (target: SongItem): void => {
        void this.addToPlaylist(target);
      },
      onDownload: (target: SongItem): void => {
        void this.downloadSongFromMenu(target);
      },
      onShare: (target: SongItem): void => {
        void this.shareSong(target);
      },
      onSelectMode: (target: SongItem): void => {
        this.enterSelectMode(target);
      },
      onDislike: (target: SongItem): void => {
        void this.showDislikeMenu(target);
      },
      onSourceDetail: (target: SongItem): void => {
        this.openSourceDetail(target);
      },
      onViewArtist: (target: SongItem): void => {
        this.viewArtist(target);
      },
      onViewAlbum: (target: SongItem): void => {
        this.viewAlbum(target);
      },
      onMovePosition: (target: SongItem): void => {
        this.openMovePosition(target);
      },
      onMoveToList: (target: SongItem): void => {
        this.openMoveToList(target);
      },
    }, {
      // 只有本地（我的）列表能改顺序/移动；在线歌单是只读的
      canEditPosition: this.canEditLocalList(),
      canMoveToList: this.canEditLocalList() && this.buildMoveTargetOptions().length > 0,
    });
  }

  /** 打开该歌曲在对应平台的详情页（外部浏览器） */
  private openSourceDetail(song: SongItem): void {
    const url = getMusicDetailPageUrl(songRowToMusicInfo(song));
    if (url.length === 0) {
      this.showToast(t('toast_operation_failed'));
      return;
    }
    this.openUrl(url);
  }

  /** 用系统浏览器打开链接 */
  private openUrl(url: string): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.startAbility({ action: 'ohos.want.action.viewData', uri: url })
        .catch((err: Error) => {
          hilog.warn(0x0001, 'SonglistDetail', 'openUrl failed: %{public}s', err.message);
          this.showToast(t('toast_operation_failed'));
        });
    } catch (err) {
      hilog.warn(0x0001, 'SonglistDetail', 'openUrl failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_operation_failed'));
    }
  }

  /** 不喜欢：歌曲 / 歌手 / 歌名三种粒度（与播放页同一套规则） */
  private async showDislikeMenu(song: SongItem): Promise<void> {
    const picked = await appActionMenu(t('dislike_title'), [
      t('dislike_song'),
      t('dislike_singer'),
      t('dislike_name'),
    ]);
    if (picked < 0) {
      return;
    }
    try {
      await dislikeList.load();
      if (picked === 0) {
        await dislikeList.add(song.name, song.singer);
      } else if (picked === 1) {
        await dislikeList.add('', song.singer);
      } else {
        await dislikeList.add(song.name, '');
      }
      this.showToast(tf('dislike_added', [dislikeList.count().toString()]));
    } catch (err) {
      hilog.warn(0x0001, 'SonglistDetail', 'addDislike failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_operation_failed'));
    }
  }

  /** 顶部「更多」菜单：排序 / 去重 / 多选 / 同步到本地歌单（动作集合见 SonglistMenus） */
  private async openMoreMenu(): Promise<void> {
    await showSonglistMoreMenu(this.listInfo.name, {
      onSort: (): void => {
        this.showSortSheet = true;
      },
      onDedupe: (): void => {
        void this.runDedupe();
      },
      onSelectMode: (): void => {
        this.enterSelectMode();
      },
      onSyncLocal: (): void => {
        void this.syncToLocalList();
      },
    });
  }


  // ===== 调整位置 / 移动到其他列表（仅本地列表）=====

  /** 在线歌单是只读的：只有本地（我的）列表能改顺序和移动 */
  private canEditLocalList(): boolean {
    return this.listInfo.source === 'local' && this.listInfo.id.length > 0;
  }

  /** 按存储顺序刷新本地列表（位置调整/移动后调用，避免看到的顺序和库里不一致） */
  private refreshLocalRows(): void {
    if (!this.canEditLocalList()) {
      return;
    }
    this.songList = this.musicRowsFromLocal(getUserListMusic(this.listInfo.id));
  }

  /** 可移动的目标列表（排除当前列表） */
  private buildMoveTargetOptions(): SettingOption[] {
    const options: SettingOption[] = [];
    const lists: ListInfo[] = getUserList();
    for (const list of lists) {
      if (list.id === this.listInfo.id) {
        continue;
      }
      options.push({ label: list.name, value: list.id });
    }
    return options;
  }

  /** 调整位置：面板默认填当前所在位置 */
  private openMovePosition(song: SongItem): void {
    let index = -1;
    for (let i = 0; i < this.songList.length; i++) {
      if (this.songList[i].id === song.id) {
        index = i;
        break;
      }
    }
    this.movePositionTarget = song;
    this.movePositionValue = (index + 1).toString();
    this.showMovePositionSheet = true;
  }

  /** 应用位置调整 */
  private async applyMovePosition(value: string): Promise<void> {
    const song = this.movePositionTarget;
    this.movePositionTarget = null;
    if (!song) {
      return;
    }

    const position = parseInt(value.trim(), 10);
    if (isNaN(position) || position < 1 || position > this.songList.length) {
      this.showToast(tf('list_position_invalid', [this.songList.length.toString()]));
      return;
    }

    try {
      const moved = await moveMusicInList(this.listInfo.id, song.id, position);
      this.refreshLocalRows();
      this.showToast(moved ? tf('list_position_moved', [position.toString()]) : t('list_position_unchanged'));
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'applyMovePosition failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_operation_failed'));
    }
  }

  /** 移动到其他列表 */
  private openMoveToList(song: SongItem): void {
    const options = this.buildMoveTargetOptions();
    if (options.length === 0) {
      this.showToast(t('list_move_no_target'));
      return;
    }
    this.moveToListTarget = song;
    this.moveToListOptions = options;
    this.showMoveToListSheet = true;
  }

  /** 「移动」= 加入目标列表 + 从当前列表移除（与安卓版 move_to 语义一致） */
  private async applyMoveToList(listId: string): Promise<void> {
    const song = this.moveToListTarget;
    this.moveToListTarget = null;
    if (!song || listId.length === 0) {
      return;
    }

    try {
      await addMusicToList(listId, songRowToListItem(song));
      await removeMusicsFromList(this.listInfo.id, [song.id]);
      this.refreshLocalRows();
      this.showToast(t('list_move_done'));
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'applyMoveToList failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_operation_failed'));
    }
  }

  // 添加到歌单
  private async addToPlaylist(song: SongItem): Promise<void> {
    try {
      const musicItem: MusicItem = songRowToListItem(song);
      
      await addMusicToList(LIST_IDS.DEFAULT, musicItem);
      
      this.showToast(tf('toast_added_to_default', [song.name]));
      hilog.info(0x0001, 'SonglistDetail', 'Added to playlist: %{public}s', song.name);
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(0x0001, 'SonglistDetail', 'Failed to add to playlist: %{public}s', errorMsg);
      this.showToast(t('toast_add_to_list_failed') + ': ' + errorMsg);
    }
  }

  // 下载单曲（从菜单调用）
  private async downloadSongFromMenu(song: SongItem): Promise<void> {
    try {
      // 调用之前实现的downloadSong方法
      await this.downloadSong(song);
      this.showToast(tf('toast_download_start_song', [song.name]));
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      this.showToast(t('toast_download_failed') + ': ' + errorMsg);
    }
  }

  // 分享歌曲
  private async shareSong(song: SongItem): Promise<void> {
    // 与播放页分享一致：按「设置 → 分享方式」走系统分享，失败回退剪贴板
    const musicInfo: MusicInfo = songRowToMusicInfo(song);
    const text = `[${sourceLabel(song.source)}] ${buildShareText(musicInfo)}`;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await shareText(context, text, song.name, getMusicDetailPageUrl(musicInfo));
      if (result === 'clipboard') {
        this.showToast(t('toast_share_copy'));
      } else if (result === 'failed') {
        this.showToast(t('toast_operation_failed'));
      }
    } catch (err) {
      hilog.warn(0x0001, 'SonglistDetail', 'shareSong failed: %{public}s', JSON.stringify(err));
      this.showToast(t('toast_operation_failed'));
    }
  }

  // 查看歌手
  private viewArtist(song: SongItem): void {
    if (!song.singer || song.singer.length === 0) {
      this.showToast(t('toast_operation_failed'));
      return;
    }
    // 返回首页并由首页发起一次按歌手名的搜索
    emitSearchRequest(song.singer);
    navigationService.back();
  }

  // 查看专辑
  private viewAlbum(song: SongItem): void {
    if (!song.album || song.album.length === 0) {
      this.showToast(t('toast_operation_failed'));
      return;
    }
    emitSearchRequest(song.album);
    navigationService.back();
  }

  build() {
    Column() {
      NavBar({
        title: t('songlist_title'),
        trailing: (): void => {
          this.NavTrailingAction();
        },
      })

      if (this.isLoading) {
        // 加载中：用骨架列表代替转圈，避免整屏白等
        Column() {
          ForEach([0, 1, 2, 3, 4, 5], (index: number) => {
            SkeletonListItem()
          }, (index: number) => `songlist_skeleton_${index}`)
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.hasError) {
        // 失败态：统一错误视图 + 可点的重试按钮
        Column() {
          ErrorView({ message: t('load_failed_hint') })
          Text(t('retry'))
            .fontSize(14)
            .fontColor(DesignTokens.accent())
            .border({ width: 1, color: DesignTokens.accent() })
            .borderRadius(16)
            .padding({ left: 18, right: 18, top: 6, bottom: 6 })
            .margin({ top: 16 })
            .onClick(() => {
              this.reloadDetail();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.songList.length === 0) {
        // 空状态
        Column() {
          Text(t('songlist_empty'))
            .fontSize(14)
            .fontColor(DesignTokens.labelSecondary(this.theme))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 歌单信息头部
        this.Header()

        // 歌曲列表
        this.SongList()

        // 多选批量操作栏
        if (this.selectMode) {
          this.BatchBar()
        }
      }

      // 播放器栏（组件内部处理底部沉浸）
      PlayerBar({ immersiveBottom: true })

      // 面板类浮层：必须在 build 中挂载才会渲染（此前排序面板漏挂，点了没反应）
      this.SortSheet()
      this.MovePositionSheet()
      this.MoveToListSheet()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  /** 顶栏右侧：普通态给「更多」，多选态给「完成」 */
  @Builder
  NavTrailingAction() {
    if (this.selectMode) {
      Text(t('list_select_done'))
        .fontSize(14)
        .fontColor(DesignTokens.accent())
        .padding({ left: 10, right: 4, top: 6, bottom: 6 })
        .onClick(() => {
          this.exitSelectMode();
        })
    } else {
      Stack() {
        Circle({ width: 34, height: 34 })
          .fill(DesignTokens.mutedFill(this.theme))
        Image($r('app.media.ic_pd_more'))
          .width(16)
          .height(16)
          .fillColor(DesignTokens.labelPrimary(this.theme))
      }
      .width(DesignTokens.touchTarget())
      .height(DesignTokens.touchTarget())
      .onClick(() => {
        this.openMoreMenu();
      })
    }
  }

  /** 多选批量操作栏（组件化） */
  @Builder
  BatchBar() {
    SonglistBatchBar({
      selectedCount: this.selectedIndexes.length,
      totalCount: this.songList.length,
      removable: this.listInfo.source === 'local',
      onToggleSelectAll: (): void => {
        this.selectAllSongs();
      },
      onAddToList: (): void => {
        void this.batchAddToPlaylist();
      },
      onDownload: (): void => {
        void this.batchDownload();
      },
      onRemove: (): void => {
        void this.batchRemove();
      },
    })
  }

  /** 排序面板（组件化，含字段 + 方式选择） */
  @Builder
  SortSheet() {
    SonglistSortSheet({
      visible: $showSortSheet,
      field: this.sortField,
      order: this.sortOrder,
      onApply: (field: string, order: string): void => {
        this.sortField = field;
        this.sortOrder = order;
        this.applySort();
      },
    })
  }

  /** 调整位置：输入 1 起始的位置 */
  @Builder
  MovePositionSheet() {
    InputSheet({
      visible: $showMovePositionSheet,
      title: t('list_change_position'),
      placeholder: tf('list_position_placeholder', [this.songList.length.toString()]),
      value: this.movePositionValue,
      numberOnly: true,
      onSubmit: (value: string): void => {
        void this.applyMovePosition(value);
      },
    })
  }

  /** 移动到其他列表 */
  @Builder
  MoveToListSheet() {
    SelectSheet({
      visible: $showMoveToListSheet,
      title: t('list_move_to'),
      options: this.moveToListOptions,
      value: '',
      onPick: (listId: string): void => {
        void this.applyMoveToList(listId);
      },
    })
  }
}
