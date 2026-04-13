// SongList 视图 - 歌单列表视图
// 优化：字体放大、标签筛选、下拉刷新

import hilog from '@ohos.hilog';
import {
  musicSdk,
  type SongListResult,
  type SongListInfo,
  type SingleMusicSdkInterface,
} from '../../core/music/MusicFeatureEntry';
import { RouteName, navigateTo, NavigationParams } from '../../service/NavigationService';

// 排序选项接口
interface SortOption {
  name: string;
  tid: string;
}

// 标签选项接口
interface TagOption {
  name: string;
  tid: string;
}

// 歌单项接口
interface SongListItemData {
  id: string;
  name: string;
  author: string;
  img: string;
  play_count: string;
  desc: string;
  total: number;
  source: string;
}

@Component
export struct SongListView {
  @Prop sourceId: string = 'kw';
  @Prop @Watch("onReCreateKeyChange") reCreateKey: number = 0;
  @StorageProp('theme') theme: string = 'light';

  // 排序选项
  private sortOptions: SortOption[] = [];
  @State selectedSort: string = 'hot';

  // 标签选项
  @State tagOptions: TagOption[] = [];
  @State selectedTag: string = '';

  // 歌单数据
  @State songLists: SongListItemData[] = [];
  @State isLoading: boolean = true;
  @State isRefreshing: boolean = false;
  @State currentPage: number = 1;
  @State hasMore: boolean = true;
  // 请求版本控制，防止竞态
  private requestEpoch: number = 0;

  aboutToAppear() {
    // 初始化排序选项
    const hotOption: SortOption = { name: '最热', tid: 'hot' };
    const newOption: SortOption = { name: '最新', tid: 'new' };
    const defaultOption: SortOption = { name: '默认', tid: 'default' };
    this.sortOptions = [hotOption, newOption, defaultOption];
    this.loadTags();
    this.loadSongList(true);
  }

  // reCreateKey 变化时重新加载（响应音乐源切换）
  onReCreateKeyChange(newKey: number): void {
    hilog.info(0x0001, 'SongListView', 'reCreateKey changed to %{public}d, reloading...', newKey);
    this.loadTags();
    this.loadSongList(true);
  }

  // 加载标签
  async loadTags(): Promise<void> {
    try {
      let sdk: SingleMusicSdkInterface | undefined;
      if (this.sourceId === 'kw') sdk = musicSdk.kw;
      else if (this.sourceId === 'kg') sdk = musicSdk.kg;
      else if (this.sourceId === 'tx') sdk = musicSdk.tx;
      else if (this.sourceId === 'wy') sdk = musicSdk.wy;
      else if (this.sourceId === 'mg') sdk = musicSdk.mg;

      if (!sdk?.songList) return;

      const result = await sdk.songList.getTags();
      if (result && result.tags) {
        const tags: TagOption[] = [];
        tags.push({ name: '全部', tid: '' });
        for (let i = 0; i < result.tags.length; i++) {
          const t = result.tags[i];
          tags.push({ name: t.name || '', tid: t.id || '' });
        }
        this.tagOptions = tags;
      }
    } catch (err) {
      hilog.error(0x0001, 'SongListView', 'Load tags failed: %{public}s', JSON.stringify(err));
    }
  }

  // 加载歌单列表
  async loadSongList(isRefresh: boolean = false): Promise<void> {
    if (this.isLoading && !isRefresh) return;
    // 递增版本号，标记新的请求开始
    const currentEpoch = ++this.requestEpoch;
    if (isRefresh) {
      this.currentPage = 1;
      this.hasMore = true;
      this.isRefreshing = true;
    }
    this.isLoading = true;

    try {
      let sdk: SingleMusicSdkInterface | undefined;
      if (this.sourceId === 'kw') sdk = musicSdk.kw;
      else if (this.sourceId === 'kg') sdk = musicSdk.kg;
      else if (this.sourceId === 'tx') sdk = musicSdk.tx;
      else if (this.sourceId === 'wy') sdk = musicSdk.wy;
      else if (this.sourceId === 'mg') sdk = musicSdk.mg;

      if (!sdk?.songList) {
        this.isLoading = false;
        return;
      }

      const tagId = this.selectedTag || '';
      const sortId = this.selectedSort === 'default' ? '' : this.selectedSort;
      const result: SongListResult = await sdk.songList.getList(sortId, tagId, this.currentPage);

      // 检查版本是否过期（用户可能已切换到其他源）
      if (currentEpoch !== this.requestEpoch) {
        hilog.info(0x0001, 'SongListView', 'Stale request ignored, current epoch: %{public}d', this.requestEpoch);
        return;
      }

      const items: SongListItemData[] = [];
      for (let i = 0; i < result.list.length; i++) {
        const sl: SongListInfo = result.list[i];
        const item: SongListItemData = {
          id: sl.id || '',
          name: sl.name || '',
          author: sl.author || '',
          img: sl.img || '',
          play_count: sl.play_count || '0',
          desc: sl.desc || '',
          total: sl.total || 0,
          source: this.sourceId,
        };
        items.push(item);
      }

      if (isRefresh) {
        this.songLists = items;
      } else {
        this.songLists = this.songLists.concat(items);
      }

      this.hasMore = items.length >= (result.limit || 20);
      this.currentPage++;
    } catch (err) {
      // 检查版本是否过期
      if (currentEpoch !== this.requestEpoch) {
        return;
      }
      hilog.error(0x0001, 'SongListView', 'Load song list failed: %{public}s', JSON.stringify(err));
    } finally {
      if (currentEpoch === this.requestEpoch) {
        this.isLoading = false;
        this.isRefreshing = false;
      }
    }
  }

  // 切换排序
  onSortChange(sortId: string): void {
    if (this.selectedSort === sortId) return;
    this.selectedSort = sortId;
    this.loadSongList(true);
  }

  // 切换标签
  onTagChange(tagId: string): void {
    if (this.selectedTag === tagId) return;
    this.selectedTag = tagId;
    this.loadSongList(true);
  }

  // 跳转到歌单详情
  openSonglistDetail(item: SongListItemData): void {
    const navParams: NavigationParams = {
      songListId: item.id,
      songListName: item.name,
      songListSource: item.source,
    };
    navigateTo(RouteName.SONGLIST_DETAIL, navParams);
  }

  build() {
    Column() {
      // 筛选栏
      this.FilterBar()

      // 歌单列表
      if (this.isLoading && this.songLists.length === 0) {
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
      } else if (this.songLists.length === 0) {
        Column() {
          Text('暂无歌单')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        this.SongListGrid()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
  }

  @Builder
  FilterBar() {
    Column() {
      // 排序按钮行 - 靠左排列，减小尺寸
      Scroll() {
        Row() {
          ForEach(this.sortOptions, (option: SortOption) => {
            Text(option.name)
              .fontSize(12)
              .padding({ left: 10, right: 10, top: 5, bottom: 5 })
              .backgroundColor(this.selectedSort === option.tid ? '#E63946' : (this.theme === 'dark' ? '#2C2C2C' : '#F0F0F0'))
              .fontColor(this.selectedSort === option.tid ? '#FFFFFF' : (this.theme === 'dark' ? '#CCCCCC' : '#666666'))
              .fontWeight(this.selectedSort === option.tid ? FontWeight.Bold : FontWeight.Normal)
              .borderRadius(14)
              .margin({ right: 6 })
              .onClick(() => {
                this.onSortChange(option.tid);
              })
          })
        }
        .padding({ left: 12, top: 8 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      // 标签横向滚动
      if (this.tagOptions.length > 1) {
        Scroll() {
          Row() {
            ForEach(this.tagOptions, (tag: TagOption) => {
              Text(tag.name)
                .fontSize(12)
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .backgroundColor(this.selectedTag === tag.tid ? '#E63946' : 'transparent')
                .fontColor(this.selectedTag === tag.tid ? '#FFFFFF' : '#999999')
                .borderRadius(12)
                .margin({ right: 6 })
                .onClick(() => {
                  this.onTagChange(tag.tid);
                })
            })
          }
          .padding({ left: 12, top: 8, bottom: 8 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .backgroundColor(this.theme === 'dark' ? '#1A1A1C' : '#FFFFFF')
  }

  @Builder
  SongListGrid() {
    Grid() {
      ForEach(this.songLists, (item: SongListItemData) => {
        GridItem() {
          this.SongListCard(item)
        }
      })

      // 加载更多
      if (this.hasMore) {
        GridItem() {
          Column() {
            if (this.isLoading) {
              LoadingProgress()
                .width(24)
                .height(24)
                .color('#999999')
            } else {
              Text('加载更多')
                .fontSize(12)
                .fontColor('#999999')
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            if (!this.isLoading) {
              this.loadSongList(false);
            }
          })
        }
        .padding(12)
      }
    }
    .columnsTemplate('1fr 1fr 1fr')
    .rowsGap(10)
    .columnsGap(10)
    .padding(12)
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
    .onReachEnd(() => {
      if (!this.isLoading && this.hasMore) {
        this.loadSongList(false);
      }
    })
  }

  @Builder
  SongListCard(item: SongListItemData) {
    Column() {
      // 封面
      Stack() {
        if (item.img) {
          Image(item.img)
            .width('100%')
            .aspectRatio(1)
            .borderRadius(10)
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Text('🎵')
              .fontSize(32)
              .fontColor('#CCCCCC')
          }
          .width('100%')
          .aspectRatio(1)
          .backgroundColor(this.theme === 'dark' ? '#2C2C2C' : '#E8E8E8')
          .borderRadius(10)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }

        // 播放量
        Row() {
          Image($r('sys.symbol.play_fill'))
            .width(10)
            .height(10)
            .fillColor('#FFFFFF')
          Text(this.formatPlayCount(item.play_count))
            .fontSize(10)
            .fontColor('#FFFFFF')
            .margin({ left: 3 })
        }
        .padding({ left: 6, right: 6, top: 3, bottom: 3 })
        .backgroundColor('rgba(0, 0, 0, 0.4)')
        .borderRadius(10)
        .position({ x: 6, y: 6 })
      }
      .width('100%')
      .aspectRatio(1)

      // 信息
      Column() {
        Text(item.name)
          .fontSize(13)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(item.author)
          .fontSize(11)
          .fontColor('#999999')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ top: 8 })
    }
    .width('100%')
    .padding(8)
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
    .borderRadius(12)
    .onClick(() => {
      this.openSonglistDetail(item);
    })
  }

  private formatPlayCount(count: string): string {
    const num = parseFloat(count);
    if (isNaN(num)) return '0';
    if (num >= 100000000) return (num / 100000000).toFixed(1) + '亿';
    if (num >= 10000) return (num / 10000).toFixed(1) + '万';
    return num.toString();
  }
}
