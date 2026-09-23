/**
 * 我喜欢的歌曲
 *
 * 重构后：NavBar + ListRow + StateView + DialogService 统一交互；
 * 行尾用 ⋮ 菜单（播放 / 取消收藏），避免原先"隐形图标"的可发现性问题。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DesignTokens } from '../theme/DesignTokens';
import { Breakpoints } from '../theme/Breakpoints';
import { LazyDataSource } from '../utils/LazyDataSource';
import { SkeletonListItem } from '../components/common/SkeletonView';
import { scrollerOffsetY } from '../utils/ScrollTools';
import { getLoveList, toggleLoveList, type MusicItem } from '../service/ListService';
import { playerService, SongInfo } from '../service/PlayerService';
import { t, tf } from '../service/LocalizationService';
import { appActionMenu, appToast } from '../service/DialogService';
import { NavBar } from '../components/ui/NavBar';
import { ListRow } from '../components/ui/ListRow';
import { StateView } from '../components/ui/StateView';
import { RefreshContainer } from '../components/ui/RefreshContainer';
import { hapticService } from '../service/HapticService';
import { PlayerBar } from '../components/player/PlayerBar';
import { navigationService, RouteName } from '../service/NavigationService';
import { playKeyOfIds } from '../service/PlayerService';
import { pageScrollKey, ScrollMemoryHandle } from '../service/ScrollMemoryService';

const DOMAIN = 0x0001;
const TAG = 'LoveListPage';

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
  /** 一多：窗口宽度（vp），大屏内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
  @StorageProp('langVersion') langVersion: number = 0;
  /** 设置 → 列表 → 记住列表滚动位置 */
  @StorageProp('rememberScrollPosition') rememberScrollPosition: boolean = true;
  @State songs: SongRow[] = [];
  /** LazyForEach 数据源：长列表只创建可视区的行 */
  private loveSource: LazyDataSource<SongRow> = new LazyDataSource<SongRow>();
  @State isLoading: boolean = true;
  /** 下拉刷新中（静默重读，保留当前列表不闪骨架） */
  @State isRefreshing: boolean = false;
  /** 大标题滚动收缩：列表下滚后切到居中常规标题 */
  @State navCollapsed: boolean = false;
  private listScroller: Scroller = new Scroller();
  /** 滚动位置记忆（固定页面 key；定时器与恢复时序在把手内部） */
  private scrollMemory: ScrollMemoryHandle = new ScrollMemoryHandle(pageScrollKey('love'), this.listScroller);
  private scrollMemoryRestored: boolean = false;
  /** 正在播放的曲目 id（高亮行） */
  /** 正在播放的那首的全局 key（源|songmid），列表高亮据此计算 */
  @StorageProp('playingSongKey') playingSongKey: string = '';

  aboutToAppear() {
    this.loadSongs();
  }

  /** 下拉刷新入口：重读「我喜欢」（本地数据，很快） */
  private onPullRefresh(): void {
    hapticService.selection();
    this.isRefreshing = true;
    this.loadSongs(true);
  }

  /** silent = true 表示下拉刷新：不闪骨架，失败也不清空现有列表 */
  private loadSongs(silent: boolean = false): void {
    if (!silent) {
      this.isLoading = true;
    }
    try {
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
      this.loveSource.reload(this.songs);
      this.afterSongsLoaded();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to load: %{public}s', JSON.stringify(err));
      if (!silent) {
        this.songs = [];
        this.loveSource.reload(this.songs);
      }
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
    }
  }

  /** 数据进列表后：标记就绪，首次进入时落回上次位置（下拉刷新不重复恢复） */
  private afterSongsLoaded(): void {
    this.scrollMemory.markLoaded();
    if (!this.scrollMemoryRestored) {
      this.scrollMemoryRestored = true;
      this.scrollMemory.restore(this.rememberScrollPosition);
    }
  }

  aboutToDisappear(): void {
    this.scrollMemory.save(this.rememberScrollPosition);
    this.scrollMemory.dispose();
  }

  /** 播放：队列 = 我喜欢列表（next/prev 可在喜欢列表里连续播放） */
  private async playSong(index: number): Promise<void> {
    if (this.songs.length === 0) {
      appToast(t('list_empty'));
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
      await playerService.playSelectedFromPlayList(index);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'playSong failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_play_failed'));
    }
  }

  private async removeFromLove(song: SongRow): Promise<void> {
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
      this.songs = this.songs.filter((item: SongRow) => item.id !== song.id);
      this.loveSource.reload(this.songs);
      appToast(t('toast_unloved'));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'removeFromLove failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_operation_failed'));
    }
  }

  /** 侧滑「取消收藏」：与本地音乐/历史页同一套操作区视觉 */
  @Builder
  SwipeUnloveAction(song: SongRow) {
    Row() {
      Text(t('player_unlove'))
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(DesignTokens.onAccent())
        .fontWeight(FontWeight.Medium)
    }
    .width(96)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(DesignTokens.danger())
    .onClick(() => {
      hapticService.light();
      void this.removeFromLove(song);
    })
  }

  /** 行菜单（⋮）：播放 / 下一首播放 / 取消收藏 */
  private async openSongMenu(song: SongRow, index: number): Promise<void> {
    const index0 = await appActionMenu(song.name, [
      t('play'),
      t('play_later'),
      t('player_unlove'),
    ], { dangerIndexes: [2] });
    if (index0 === 0) {
      void this.playSong(index);
    } else if (index0 === 1) {
      playerService.insertNext({
        id: song.id,
        url: '',
        title: song.name,
        artist: song.singer,
        album: song.album,
        artwork: song.pic || null,
        duration: song.duration,
        source: song.source,
      });
      appToast(tf('toast_play_later_added', [song.name]));
    } else if (index0 === 2) {
      void this.removeFromLove(song);
    }
  }

  @Builder
  private rowTrailing(song: SongRow, index: number) {
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
      void this.openSongMenu(song, index);
    })
  }

  build() {
    Column() {
      NavBar({
        title: t('love_title'),
        largeTitle: true,
        collapsed: this.navCollapsed,
        trailing: (): void => {
          Text(tf('count_songs_short', [this.songs.length.toString()]))
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .padding({ right: 6 })
        },
      })

      if (this.isLoading) {
        // 骨架行代替转圈：与歌单/榜单/评论页统一
        Column() {
          ForEach([0, 1, 2, 3, 4], (index: number) => {
            SkeletonListItem()
          }, (index: number) => `skeleton_${index}`)
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.songs.length === 0) {
        // 空态给行动项：直接回歌单广场挑一张来播
        StateView({
          state: 'empty',
          iconRes: $r('sys.symbol.heart'),
          message: t('love_empty_hint'),
          actionText: t('empty_go_songlist'),
          onAction: (): void => {
            navigationService.backTo(RouteName.HOME);
          },
        })
          .layoutWeight(1)
          .width('100%')
      } else {
        // 下拉刷新：重读「我喜欢」（自定义组件后面不能直接挂通用属性，用一层 Column 承担剩余高度）
        Column() {
          RefreshContainer({
            refreshing: $isRefreshing,
            onRefresh: (): void => {
              this.onPullRefresh();
            },
          }) {
            this.LoveList()
          }
        }
        .layoutWeight(1)
        .width('100%')
      }

      // 迷你播放条：喜欢列表也能看见当前播放并一键回播放页（与首页/本地音乐一致）
      PlayerBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }

  /** 喜欢列表（LazyForEach + 大标题滚动收缩 + 大屏内容列居中） */
  @Builder
  LoveList() {
    List({ scroller: this.listScroller }) {
      LazyForEach(this.loveSource, (song: SongRow, index: number) => {
        ListItem() {
          // 行内容用一层 Column 承担左右留白：侧滑操作区能贴住屏幕右缘（与本地音乐一致）
          Column() {
            ListRow({
              index: index + 1,
              title: song.name,
              // 结构化字段交给行组件按「设置 → 列表」拼装
              singer: song.singer,
              album: song.album,
              sourceId: song.source,
              durationSeconds: song.duration,
              active: playKeyOfIds(song.source, song.id, song.id) === this.playingSongKey,
              divider: index < this.songs.length - 1,
              onTap: (): void => {
                void this.playSong(index);
              },
              onLongPress: (): void => {
                void this.openSongMenu(song, index);
              },
              trailing: (): void => {
                this.rowTrailing(song, index);
              },
            })
          }
          .padding({ left: 16, right: 8 })
          .width('100%')
        }
        // 侧滑取消收藏（长按菜单里也有同一项，这里给更快的手势入口）
        .swipeAction({
          end: {
            builder: (): void => {
              this.SwipeUnloveAction(song);
            },
            onAction: (): void => {
              hapticService.light();
              void this.removeFromLove(song);
            },
            actionAreaDistance: 56,
          },
        })
      }, (song: SongRow, index: number) => `${song.id}_${index}`)
    }
    .layoutWeight(1)
    .width('100%')
    .scrollBar(BarState.Off)
    .onDidScroll(() => {
      const y = scrollerOffsetY(this.listScroller);
      if (y > 18 && !this.navCollapsed) {
        this.navCollapsed = true;
      } else if (y <= 4 && this.navCollapsed) {
        this.navCollapsed = false;
      }
    })
    .cachedCount(6)
    .padding({
      left: Breakpoints.contentInset(this.windowWidthVp),
      right: Breakpoints.contentInset(this.windowWidthVp),
    })
  }
}
