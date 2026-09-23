/**
 * 播放历史页
 *
 * 重构后：统一使用 UI Kit（NavBar / ListRow / StateView）+ DialogService，
 * 页面只保留数据加载与播放逻辑，视觉与其它列表页完全一致。
 */
import hilog from '@ohos.hilog';
import { playerService, SongInfo } from '../service/PlayerService';
import { getMusicUrl } from '../core/music/MusicFeatureEntry';
import {
  getPlayHistory,
  clearPlayHistory,
  removePlayHistoryItem,
  PlayHistoryItem,
} from '../service/PlayHistoryService';
import type { MusicInfo as AppMusicInfo, MusicSource } from '../types/MusicTypes';
import { formatPlayTime } from '../utils/CommonUtils';
import { DesignTokens } from '../theme/DesignTokens';
import { Breakpoints } from '../theme/Breakpoints';
import { LazyDataSource } from '../utils/LazyDataSource';
import { SkeletonListItem } from '../components/common/SkeletonView';
import { scrollerOffsetY } from '../utils/ScrollTools';
import { t, tf } from '../service/LocalizationService';
import { appConfirm, appToast } from '../service/DialogService';
import { NavBar } from '../components/ui/NavBar';
import { ListRow } from '../components/ui/ListRow';
import { StateView } from '../components/ui/StateView';
import { RefreshContainer } from '../components/ui/RefreshContainer';
import { hapticService } from '../service/HapticService';
import { PlayerBar } from '../components/player/PlayerBar';
import { pageScrollKey, ScrollMemoryHandle } from '../service/ScrollMemoryService';

const DOMAIN = 0x0001;
const TAG = 'HistoryListPage';
/** 播放历史最多展示条数 */
const HISTORY_LIMIT = 120;

@Component
export struct HistoryListPage {
  @StorageProp('theme') theme: string = 'light';
  /** 一多：窗口宽度（vp），大屏内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
  @StorageProp('langVersion') langVersion: number = 0;
  /** 设置 → 列表 → 记住列表滚动位置 */
  @StorageProp('rememberScrollPosition') rememberScrollPosition: boolean = true;
  @State isLoading: boolean = true;
  /** 下拉刷新中（静默刷新，保留当前列表不闪骨架） */
  @State isRefreshing: boolean = false;
  /** 大标题滚动收缩：列表下滚后切到居中常规标题 */
  @State navCollapsed: boolean = false;
  private listScroller: Scroller = new Scroller();
  /** 滚动位置记忆（key 为固定页面，恢复时机与定时器都在把手内部） */
  private scrollMemory: ScrollMemoryHandle = new ScrollMemoryHandle(pageScrollKey('history'), this.listScroller);
  private scrollMemoryRestored: boolean = false;
  @State playHistory: PlayHistoryItem[] = [];
  /** LazyForEach 数据源：长列表只创建可视区的行 */
  private historySource: LazyDataSource<PlayHistoryItem> = new LazyDataSource<PlayHistoryItem>();

  aboutToAppear() {
    void this.loadHistory();
  }

  /**
   * 读取播放历史。silent = true 表示下拉刷新：不显示骨架、失败也不清空现有列表。
   */
  private async loadHistory(silent: boolean = false): Promise<void> {
    if (!silent) {
      this.isLoading = true;
    }
    try {
      this.playHistory = await getPlayHistory(HISTORY_LIMIT);
      this.historySource.reload(this.playHistory);
      this.afterHistoryLoaded();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadHistory failed: %{public}s', JSON.stringify(err));
      if (!silent) {
        this.playHistory = [];
        this.historySource.reload(this.playHistory);
      }
    } finally {
      this.isLoading = false;
      this.isRefreshing = false;
    }
  }

  /** 数据进列表后：标记就绪，首次进入时落回上次的滚动位置（下拉刷新不重复恢复） */
  private afterHistoryLoaded(): void {
    this.scrollMemory.markLoaded();
    if (!this.scrollMemoryRestored) {
      this.scrollMemoryRestored = true;
      this.scrollMemory.restore(this.rememberScrollPosition);
    }
  }

  aboutToDisappear(): void {
    // 离开页面记录位置（关闭「记住滚动位置」时写入会被内部忽略）
    this.scrollMemory.save(this.rememberScrollPosition);
    this.scrollMemory.dispose();
  }

  /** 下拉刷新入口：重读本地历史 */
  private onPullRefresh(): void {
    hapticService.selection();
    this.isRefreshing = true;
    void this.loadHistory(true);
  }

  /** 侧滑删除这一条历史（不需要二次确认：删的只是一条记录，代价低且可再听一次补回） */
  private async removeHistoryAt(index: number): Promise<void> {
    if (index < 0 || index >= this.playHistory.length) {
      return;
    }
    const item = this.playHistory[index];
    const remained = await removePlayHistoryItem(item.id, item.source, item.playedAt);
    this.playHistory = remained;
    this.historySource.reload(this.playHistory);
    hapticService.light();
    appToast(t('toast_deleted'));
  }

  /** 侧滑操作区（与本地音乐页同一套视觉） */
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
      // 直接点操作区也走同一条删除路径（距离够远，误触风险低）
      void this.removeHistoryAt(index);
    })
  }

  private async clearHistory(): Promise<void> {
    const confirmed = await appConfirm(t('history_clear'), t('history_clear'), { danger: true });
    if (!confirmed) {
      return;
    }
    try {
      await clearPlayHistory();
      this.playHistory = [];
      appToast(t('toast_history_cleared'));
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'clearHistory failed: %{public}s', JSON.stringify(err));
      appToast(t('toast_clear_failed'));
    }
  }

  /** 点击历史条目：重新取链并播放 */
  private async playHistorySong(song: PlayHistoryItem): Promise<void> {
    try {
      const musicInfo: AppMusicInfo = {
        id: song.id,
        name: song.name,
        singer: song.singer,
        source: song.source as MusicSource,
        songmid: song.songmid || song.id,
        interval: formatPlayTime(song.duration),
        img: song.pic || null,
        pic: song.pic || undefined,
        lrc: null,
        albumName: song.album || '',
        album: song.album || '',
        albumId: '',
        hash: '',
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
        appToast(t('toast_no_play_url'));
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
      // 队列 = 当前历史列表，方便连续播放
      const queue: SongInfo[] = [];
      let startIndex = 0;
      for (let i = 0; i < this.playHistory.length; i++) {
        const item = this.playHistory[i];
        if (item.id === song.id && item.source === song.source) {
          startIndex = i;
        }
        queue.push({
          id: item.id,
          url: item.id === song.id ? url : '',
          title: item.name,
          artist: item.singer,
          album: item.album || '',
          artwork: item.pic || null,
          duration: item.duration,
          source: item.source,
        });
      }
      playerService.setPlayList(queue, startIndex);
      await playerService.playFromSelection(songInfo, url, song.duration);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'play history song failed: %{public}s', JSON.stringify(error));
      appToast(t('toast_play_failed'));
    }
  }

  @Builder
  private trailingActions() {
    if (this.playHistory.length > 0) {
      Text(t('history_clear'))
        .fontSize(DesignTokens.fontBody())
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.accent())
        .padding({ left: 8, right: 8, top: 6, bottom: 6 })
        .onClick(() => {
          void this.clearHistory();
        })
    }
  }

  build() {
    Column() {
      NavBar({
        title: t('history_title'),
        largeTitle: true,
        collapsed: this.navCollapsed,
        trailing: (): void => {
          this.trailingActions();
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
      } else if (this.playHistory.length === 0) {
        StateView({
          state: 'empty',
          iconRes: $r('sys.symbol.clock'),
          message: t('history_empty_hint'),
        })
          .layoutWeight(1)
          .width('100%')
      } else {
        // 下拉刷新：重读本地历史（自定义组件后面不能直接挂通用属性，用一层 Column 承担剩余高度）
        Column() {
          RefreshContainer({
            refreshing: $isRefreshing,
            onRefresh: (): void => {
              this.onPullRefresh();
            },
          }) {
            this.HistoryList()
          }
        }
        .layoutWeight(1)
        .width('100%')
      }

      // 迷你播放条：历史页也能看见当前播放并一键回播放页（与首页/本地音乐一致）
      PlayerBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }

  /** 历史列表（LazyForEach + 大标题滚动收缩 + 大屏内容列居中） */
  @Builder
  HistoryList() {
    List({ scroller: this.listScroller }) {
      LazyForEach(this.historySource, (song: PlayHistoryItem, index: number) => {
        ListItem() {
          // 行内容用一层 Column 承担左右留白：这样侧滑操作区能贴住屏幕右缘（与本地音乐一致）
          Column() {
            ListRow({
              index: index + 1,
              title: song.name,
              // 结构化字段交给行组件按「设置 → 列表」拼装（显示专辑/音源/时长全应用一致）
              singer: song.singer,
              album: song.album,
              sourceId: song.source,
              durationSeconds: song.duration,
              divider: index < this.playHistory.length - 1,
              onTap: (): void => {
                void this.playHistorySong(song);
              },
            })
          }
          .padding({ left: 16, right: 16 })
          .width('100%')
        }
        // 侧滑删除这一条（清空整表是粗操作，主流列表都支持单条移除）
        .swipeAction({
          end: {
            builder: (): void => {
              this.DeleteAction(index);
            },
            onAction: (): void => {
              void this.removeHistoryAt(index);
            },
            actionAreaDistance: 56,
          },
        })
      }, (song: PlayHistoryItem, index: number) => `${song.id}_${song.source}_${song.playedAt}_${index}`)

      ListItem() {
        Text(tf('history_count', [this.playHistory.length.toString()]))
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 14, bottom: 18 })
      }
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
