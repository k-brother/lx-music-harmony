// 歌单详情页 - 对应 src/screens/SonglistDetail/index.tsx
// 显示歌单信息和歌曲列表

import hilog from '@ohos.hilog';
import { PlayerBar } from '../components/player/PlayerBar';
import { getSongListDetail, getMusicUrl, setDownloadContext, download, type SongListDetailResult } from '../core/music/MusicFeatureEntry';
import { NavigationParams } from '../service/NavigationService';
import { playerService, SongInfo } from '../service/PlayerService';
import { navigationService } from '../service/NavigationService';
import { common } from '@kit.AbilityKit';
import storageService, { StorageKeys } from '../service/StorageService';
import { addMusicToList, getUserList, getUserListMusic, LIST_IDS, MusicItem, ListInfo } from '../service/ListService';
import type { MusicInfo, MusicSource } from '../types/MusicTypes';
import { DesignTokens } from '../theme/DesignTokens';
import { NavBackButton } from '../components/common/NavBackButton';
import { t } from '../service/LocalizationService';

interface MenuActionItem {
  label: string;
  action: () => void;
}

interface SonglistCollectionEntry {
  id: string;
  source: string;
  name: string;
  creator: string;
  pic: string;
  desc: string;
  playCount: number;
  collectTime: number;
}

@Component
export struct SonglistDetailPage {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @State renderKey: number = Date.now();
  @State listName: string = t('songlist_title');
  @State creator: string = t('unknown');
  @State description: string = '';
  @State playCount: string = '0';
  @State songList: SongItem[] = [];
  @State isLoading: boolean = true;
  @State hasError: boolean = false;
  @State headerCompact: boolean = false;
  @State listCoverLoadFailed: boolean = false;

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
  private songListScroller: Scroller = new Scroller();

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

  private canRenderCover(url: string): boolean {
    const value = (url ?? '').trim();
    return value.startsWith('http://') || value.startsWith('https://') || value.startsWith('//');
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

  onBackPressed(): boolean {
    navigationService.back();
    return true;
  }

  @Builder
  Header() {
    Column() {
      if (!this.headerCompact) {
        Row() {
          Column({ space: 6 }) {
            Stack() {
              if (!this.listCoverLoadFailed && this.canRenderCover(this.listInfo.pic)) {
                Image(this.listInfo.pic)
                  .width(106)
                  .height(106)
                  .borderRadius(12)
                  .objectFit(ImageFit.Cover)
                  .onError(() => {
                    this.listCoverLoadFailed = true;
                  })
              } else {
                Image($r('app.media.ic_player_cover_placeholder'))
                .width(106)
                .height(106)
                .borderRadius(12)
                .objectFit(ImageFit.Cover)
              }

              Text(this.getSourceLabel())
                .fontSize(10)
                .fontColor('#FFFFFF')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor(DesignTokens.accent())
                .borderRadius(9)
                .margin({ right: 4, bottom: 4 })
            }
            .width(106)
            .height(106)
            .align(Alignment.BottomEnd)
          }

          Column({ space: 8 }) {
            Text(this.listInfo.name)
              .fontSize(DesignTokens.fontTitle())
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .fontWeight(FontWeight.Medium)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Row() {
              Text(t('songlist_creator') + ': ' + (this.listInfo.creator || t('unknown')))
                .fontSize(DesignTokens.fontCaption())
                .fontColor(DesignTokens.labelSecondary(this.theme))
                .maxLines(1)
                .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Row() {
              Text(`播放: ${this.formatPlayCountDisplay(this.listInfo.playCount)}`)
                .fontSize(DesignTokens.fontCaption())
                .fontColor(DesignTokens.labelSecondary(this.theme))
                .maxLines(1)
              Text(`共 ${this.songList.length} 首`)
                .fontSize(DesignTokens.fontCaption())
                .fontColor(DesignTokens.labelSecondary(this.theme))
                .margin({ left: 8 })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          .margin({ left: 14, right: 10 })

          Column({ space: 8 }) {
            Row({ space: 5 }) {
              Image($r('app.media.ic_pd_play'))
                .width(14)
                .height(14)
                .fillColor('#FFFFFF')
              Text('播放全部')
                .fontSize(DesignTokens.fontCaption())
                .fontColor('#FFFFFF')
                .fontWeight(FontWeight.Medium)
            }
            .height(34)
            .width(112)
            .backgroundColor(DesignTokens.accent())
            .borderRadius(17)
            .justifyContent(FlexAlign.Center)
            .onClick(() => void this.playAll())

            Row({ space: 5 }) {
              Image($r('app.media.ic_common_heart'))
                .width(14)
                .height(14)
                .fillColor(DesignTokens.labelPrimary(this.theme))
              Text('收藏')
                .fontSize(DesignTokens.fontCaption())
                .fontColor(DesignTokens.labelPrimary(this.theme))
            }
            .height(34)
            .width(112)
            .backgroundColor(DesignTokens.mutedFill(this.theme))
            .borderRadius(17)
            .justifyContent(FlexAlign.Center)
            .onClick(() => void this.toggleCollect())

          }
          .alignItems(HorizontalAlign.End)
        }
        .width('100%')
      } else {
        Row() {
          Row({ space: 8 }) {
            Row({ space: 5 }) {
              Image($r('app.media.ic_pd_play'))
                .width(14)
                .height(14)
                .fillColor('#FFFFFF')
              Text('播放全部')
                .fontSize(DesignTokens.fontCaption())
                .fontColor('#FFFFFF')
                .fontWeight(FontWeight.Medium)
            }
            .height(34)
            .width(112)
            .backgroundColor(DesignTokens.accent())
            .borderRadius(17)
            .justifyContent(FlexAlign.Center)
            .onClick(() => void this.playAll())

            Row({ space: 5 }) {
              Image($r('app.media.ic_common_heart'))
                .width(14)
                .height(14)
                .fillColor(DesignTokens.labelPrimary(this.theme))
              Text('收藏')
                .fontSize(DesignTokens.fontCaption())
                .fontColor(DesignTokens.labelPrimary(this.theme))
            }
            .height(34)
            .width(112)
            .backgroundColor(DesignTokens.mutedFill(this.theme))
            .borderRadius(17)
            .justifyContent(FlexAlign.Center)
            .onClick(() => void this.toggleCollect())

            Text(this.getSourceLabel())
              .fontSize(10)
              .fontColor('#FFFFFF')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor(DesignTokens.accent())
              .borderRadius(9)
          }

          Text(`共 ${this.songList.length} 首`)
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelSecondary(this.theme))
        }
        .width('100%')
        .margin({ top: 4 })
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Center)
      }

      if (this.listInfo.desc) {
        Text(this.listInfo.desc)
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .maxLines(2)
          .margin({ top: this.headerCompact ? 6 : 10 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(14)
    .border({ width: 0.33, color: DesignTokens.cardBorder(this.theme) })
    .margin({ left: 12, right: 12, top: 8, bottom: 10 })
  }

  @Builder
  SongList() {
    List({ space: 8, scroller: this.songListScroller }) {
      ForEach(this.songList, (song: SongItem, index: number) => {
        ListItem() {
          Row() {
            Text((index + 1).toString())
              .fontSize(DesignTokens.fontCaption())
              .fontColor(song.isPlaying ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme))
              .width(28)
              .textAlign(TextAlign.Center)

            Column({ space: 2 }) {
              Text(song.name)
                .fontSize(DesignTokens.fontBody())
                .fontColor(song.isPlaying ? DesignTokens.accent() : DesignTokens.labelPrimary(this.theme))
                .maxLines(1)
              Text(song.singer + ' - ' + song.album)
                .fontSize(DesignTokens.fontCaption())
                .fontColor(DesignTokens.labelSecondary(this.theme))
                .maxLines(1)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            .margin({ left: 10, right: 10 })

            Stack() {
              Circle({ width: 28, height: 28 })
                .fill(DesignTokens.mutedFill(this.theme))
              Image($r('app.media.ic_common_download'))
                .width(14)
                .height(14)
                .fillColor(DesignTokens.labelSecondary(this.theme))
            }
            .onClick(() => {
              void this.downloadSongFromMenu(song);
            })
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 12, bottom: 12 })
          .backgroundColor(DesignTokens.card(this.theme))
          .borderRadius(12)
          .border({ width: 0.33, color: DesignTokens.cardBorder(this.theme) })
        }
        .onClick(() => {
          void this.playSong(index);
        })
      })
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

      const items: SongItem[] = [];
      for (let i = 0; i < localSongs.length; i++) {
        const song = localSongs[i];
        items.push({
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

      this.songList = items;
      this.detailLoaded = true;
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to load local song list: %{public}s', JSON.stringify(err));
      this.hasError = true;
      this.detailLoaded = false;
    } finally {
      this.isLoading = false;
    }
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
      // 将整个歌单转换为 SongInfo 数组并设置到播放器
      const songInfos: SongInfo[] = [];
      for (let i = 0; i < this.songList.length; i++) {
        const s = this.songList[i];
        const songArtwork = s.pic || this.listInfo.pic || null;
        const songInfo: SongInfo = {
          id: s.id,
          url: '', // 稍后动态获取
          title: s.name,
          artist: s.singer,
          album: s.album,
          artwork: songArtwork,
          duration: s.duration,
          source: s.source,
        };
        songInfos.push(songInfo);
      }

      // 获取当前歌曲的 URL
      const musicInfo: MusicInfo = {
        id: song.id,
        name: song.name,
        singer: song.singer,
        source: song.source as 'kw' | 'kg' | 'tx' | 'wy' | 'mg',
        songmid: song.songmid || song.id,
        strMediaMid: song.source === 'tx' && song.strMediaMid && song.strMediaMid.length > 0 ? song.strMediaMid : undefined,
        copyrightId: song.copyrightId && song.copyrightId.length > 0 ? song.copyrightId : undefined,
        interval: this.formatPlayTime(song.duration),
        img: song.pic || null,
        lrc: null,
        albumName: song.album,
        album: song.album,
        albumId: song.albumId || '',
        hash: song.hash || '',
        types: [],
        _types: new Map(),
        typeUrl: new Map(),
        otherSource: null,
      } as MusicInfo;

      hilog.info(0x0001, 'SonglistDetail', 'Getting music URL for song: %{public}s', song.name);
      const url: string | null = await getMusicUrl({
        musicInfo: musicInfo,
        isRefresh: false,
        onToggleSource: null,
        allowToggleSource: true,
      });

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
      
      // 设置播放列表（现在URL已经可用）
      playerService.setPlayList(songInfos, index);
      hilog.info(0x0001, 'SonglistDetail', 'PlayList set with %{public}d songs, starting from index %{public}d', songInfos.length, index);

      hilog.info(0x0001, 'SonglistDetail', 'Got music URL, setting source and playing...');
      await playerService.playFromSelection(songInfos[index], url, song.duration);
      hilog.info(0x0001, 'SonglistDetail', 'Song playback started successfully');
    } catch (error) {
      hilog.error(0x0001, 'SonglistDetail', 'Play song failed: %{public}s', JSON.stringify(error));
    }
  }

  // 播放全部歌曲
  async playAll(): Promise<void> {
    if (this.songList.length === 0) return;
    hilog.info(0x0001, 'SonglistDetail', 'Play all songs from index 0');
    // 设置整个播放列表，从第一首开始
    const songInfos: SongInfo[] = [];
    for (let i = 0; i < this.songList.length; i++) {
      const s = this.songList[i];
      const songArtwork = s.pic || this.listInfo.pic || null;
      const songInfo: SongInfo = {
        id: s.id,
        url: '',
        title: s.name,
        artist: s.singer,
        album: s.album,
        artwork: songArtwork,
        duration: s.duration,
        source: s.source,
      };
      songInfos.push(songInfo);
    }
    // 获取第一首的 URL 并播放
    const firstSong = this.songList[0];
    const musicInfo: MusicInfo = {
      id: firstSong.id,
      name: firstSong.name,
      singer: firstSong.singer,
      source: firstSong.source as 'kw' | 'kg' | 'tx' | 'wy' | 'mg',
      songmid: firstSong.songmid || firstSong.id,
      strMediaMid: firstSong.source === 'tx' && firstSong.strMediaMid && firstSong.strMediaMid.length > 0 ?
        firstSong.strMediaMid : undefined,
      copyrightId: firstSong.copyrightId && firstSong.copyrightId.length > 0 ? firstSong.copyrightId : undefined,
      interval: this.formatPlayTime(firstSong.duration),
      img: firstSong.pic || null,
      lrc: null,
      albumName: firstSong.album,
      album: firstSong.album,
      albumId: firstSong.albumId || '',
      hash: firstSong.hash || '',
      types: [],
      _types: new Map(),
      typeUrl: new Map(),
      otherSource: null,
    } as MusicInfo;
    const url: string | null = await getMusicUrl({
      musicInfo: musicInfo,
      isRefresh: false,
      onToggleSource: null,
      allowToggleSource: true,
    });

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

  // 收藏歌单
  async toggleCollect(): Promise<void> {
    try {
      hilog.info(0x0001, 'SonglistDetail', 'Collect songlist: %{public}s', this.listInfo.name);
      
      // 检查是否已收藏
      const isCollected = await this.isSonglistCollected();
      
      if (isCollected) {
        // 取消收藏
        await this.removeFromCollections();
        this.showToast('已取消收藏: ' + this.listInfo.name);
      } else {
        // 添加收藏
        await this.addToCollections();
        this.showToast('已收藏: ' + this.listInfo.name);
      }
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(0x0001, 'SonglistDetail', 'Failed to toggle collect: %{public}s', errorMsg);
      this.showToast('操作失败: ' + errorMsg);
    }
  }

  /** 读取收藏的歌单列表（统一走 StorageService 的同一份存储） */
  private async loadCollections(): Promise<SonglistCollectionEntry[]> {
    const json = await storageService.getString(StorageKeys.COLLECTION_SONGLISTS, '[]');
    if (!json || json.length === 0) {
      return [];
    }
    try {
      return JSON.parse(json) as SonglistCollectionEntry[];
    } catch (err) {
      hilog.warn(0x0001, 'SonglistDetail', 'Parse collections failed: %{public}s', JSON.stringify(err));
      return [];
    }
  }

  private async saveCollections(collections: SonglistCollectionEntry[]): Promise<void> {
    await storageService.setString(StorageKeys.COLLECTION_SONGLISTS, JSON.stringify(collections));
  }

  private isSameSonglist(item: SonglistCollectionEntry): boolean {
    return item.id === this.listInfo.id && item.source === this.listInfo.source;
  }

  // 检查歌单是否已收藏
  private async isSonglistCollected(): Promise<boolean> {
    try {
      const collections = await this.loadCollections();
      return collections.some((item: SonglistCollectionEntry) => this.isSameSonglist(item));
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to check collection status: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  // 添加到收藏
  private async addToCollections(): Promise<void> {
    try {
      const collections = await this.loadCollections();
      if (collections.some((item: SonglistCollectionEntry) => this.isSameSonglist(item))) {
        return;
      }
      collections.push({
        id: this.listInfo.id,
        source: this.listInfo.source,
        name: this.listInfo.name,
        creator: this.listInfo.creator,
        pic: this.listInfo.pic,
        desc: this.listInfo.desc,
        playCount: this.listInfo.playCount,
        collectTime: Date.now()
      });
      await this.saveCollections(collections);
      hilog.info(0x0001, 'SonglistDetail', 'Added to collections: %{public}s', this.listInfo.name);
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to add to collections: %{public}s', JSON.stringify(err));
      throw new Error(err instanceof Error ? err.message : JSON.stringify(err));
    }
  }

  // 从收藏中移除
  private async removeFromCollections(): Promise<void> {
    try {
      const collections = await this.loadCollections();
      const remaining = collections.filter((item: SonglistCollectionEntry) => !this.isSameSonglist(item));
      await this.saveCollections(remaining);
      hilog.info(0x0001, 'SonglistDetail', 'Removed from collections: %{public}s', this.listInfo.name);
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to remove from collections: %{public}s', JSON.stringify(err));
      throw new Error(err instanceof Error ? err.message : JSON.stringify(err));
    }
  }

  // 显示提示
  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message, duration: 1800 });
    } catch (_e) {
      hilog.info(0x0001, 'SonglistDetail', 'Toast: %{public}s', message);
    }
  }

  // 下载歌单
  async downloadAll(): Promise<void> {
    try {
      hilog.info(0x0001, 'SonglistDetail', 'Download songlist: %{public}s', this.listInfo.name);
      
      if (this.songList.length === 0) {
        this.showToast('歌单为空，无法下载');
        return;
      }
      
      // 确认下载
      const confirmed = await this.showConfirmDialog(
        t('download_confirm_title'),
        `确定要下载歌单 "${this.listInfo.name}" 中的 ${this.songList.length} 首歌曲吗？`
      );
      
      if (!confirmed) {
        this.showToast('已取消下载');
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
          this.showToast(`下载中... (${i + 1}/${this.songList.length})`);
        } catch (err) {
          hilog.error(0x0001, 'SonglistDetail', 'Failed to download song %{public}s: %{public}s', 
            song.name, JSON.stringify(err));
          failCount++;
        }
      }
      
      // 显示结果
      if (successCount > 0) {
        this.showToast(`下载完成: ${successCount} 首成功, ${failCount} 首失败`);
      } else {
        this.showToast('下载失败，请检查网络连接');
      }
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(0x0001, 'SonglistDetail', 'Failed to download songlist: %{public}s', errorMsg);
      this.showToast('下载失败: ' + errorMsg);
    }
  }

  private formatDurationForMusicInfo(seconds: number): string {
    const s = Math.max(0, Math.floor(seconds));
    const m = Math.floor(s / 60);
    const sec = s % 60;
    return `${m.toString().padStart(2, '0')}:${sec.toString().padStart(2, '0')}`;
  }

  private buildMusicInfoForDownload(song: SongItem): MusicInfo {
    const src = song.source as MusicSource;
    const sid = song.songmid || song.id;
    return {
      id: sid,
      name: song.name,
      singer: song.singer,
      source: src,
      interval: this.formatDurationForMusicInfo(song.duration),
      img: song.pic || null,
      lrc: null,
      songmid: sid,
      strMediaMid: src === 'tx' && song.strMediaMid && song.strMediaMid.length > 0 ? song.strMediaMid : undefined,
      copyrightId: song.copyrightId && song.copyrightId.length > 0 ? song.copyrightId : undefined,
      album: song.album,
      albumName: song.album,
      albumId: song.albumId ?? '',
      hash: song.hash ?? '',
      types: [],
      _types: new Map(),
      typeUrl: new Map(),
      otherSource: null,
    };
  }

  // 下载单首歌曲
  private async downloadSong(song: SongItem): Promise<void> {
    try {
      const musicInfo: MusicInfo = this.buildMusicInfoForDownload(song);
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

  // 显示确认对话框（模拟实现）
  private async showConfirmDialog(title: string, message: string): Promise<boolean> {
    // 在实际应用中，这里应该显示一个确认对话框
    // 暂时返回true（用户确认）
    hilog.info(0x0001, 'SonglistDetail', 'Confirm dialog: %{public}s - %{public}s', title, message);
    return true;
  }

  showSongMenu(song: SongItem): void {
    try {
      hilog.info(0x0001, 'SonglistDetail', 'Show menu for: %{public}s', song.name);
      
      // 显示操作菜单
      this.showActionMenu(song);
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(0x0001, 'SonglistDetail', 'Failed to show song menu: %{public}s', errorMsg);
    }
  }

  // 显示操作菜单
  private showActionMenu(song: SongItem): void {
    // 在实际应用中，这里应该显示一个操作菜单
    // 暂时使用日志输出并执行默认操作
    
    const actions: MenuActionItem[] = [
      { label: t('player_add_to_list'), action: (): void => { this.addToPlaylist(song); } },
      { label: t('player_download'), action: (): void => { this.downloadSongFromMenu(song); } },
      { label: t('player_share'), action: (): void => { this.shareSong(song); } },
      { label: t('player_view_artist'), action: (): void => { this.viewArtist(song); } },
      { label: t('player_view_album'), action: (): void => { this.viewAlbum(song); } }
    ];
    
    hilog.info(0x0001, 'SonglistDetail', 'Action menu for %{public}s:', song.name);
    for (const action of actions) {
      hilog.info(0x0001, 'SonglistDetail', '  - %{public}s', action.label);
    }
    
    // 默认执行第一个操作：添加到歌单
    this.addToPlaylist(song);
  }

  // 添加到歌单
  private async addToPlaylist(song: SongItem): Promise<void> {
    try {
      const musicItem: MusicItem = {
        id: song.id,
        name: song.name,
        singer: song.singer,
        album: song.album,
        albumId: song.albumId ?? null,
        duration: song.duration,
        source: song.source,
        pic: song.pic,
        lrc: null
      };
      
      await addMusicToList(LIST_IDS.DEFAULT, musicItem);
      
      this.showToast(`已添加到默认列表: ${song.name}`);
      hilog.info(0x0001, 'SonglistDetail', 'Added to playlist: %{public}s', song.name);
      
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.error(0x0001, 'SonglistDetail', 'Failed to add to playlist: %{public}s', errorMsg);
      this.showToast('添加到歌单失败: ' + errorMsg);
    }
  }

  // 下载单曲（从菜单调用）
  private async downloadSongFromMenu(song: SongItem): Promise<void> {
    try {
      // 调用之前实现的downloadSong方法
      await this.downloadSong(song);
      this.showToast(`开始下载: ${song.name}`);
    } catch (err) {
      const errorMsg = err instanceof Error ? err.message : JSON.stringify(err);
      this.showToast('下载失败: ' + errorMsg);
    }
  }

  // 分享歌曲
  private shareSong(song: SongItem): void {
    // 在实际应用中，这里应该调用系统分享功能
    hilog.info(0x0001, 'SonglistDetail', 'Sharing song: %{public}s', song.name);
    this.showToast(`分享: ${song.name} - ${song.singer}`);
  }

  // 查看歌手
  private viewArtist(song: SongItem): void {
    // 在实际应用中，这里应该跳转到歌手页面
    hilog.info(0x0001, 'SonglistDetail', 'Viewing artist: %{public}s', song.singer);
    this.showToast(`查看歌手: ${song.singer}`);
  }

  // 查看专辑
  private viewAlbum(song: SongItem): void {
    // 在实际应用中，这里应该跳转到专辑页面
    hilog.info(0x0001, 'SonglistDetail', 'Viewing album: %{public}s', song.album);
    this.showToast(`查看专辑: ${song.album}`);
  }

  build() {
    Column() {
      Row() {
        NavBackButton()

        Text('歌单详情')
          .fontSize(DesignTokens.fontTitle())
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })

        Blank()
      }
      .width('100%')
      .height(60)
      .padding({ left: 14, right: 14, top: 8, bottom: 6 })
      .backgroundColor(DesignTokens.chromeBar(this.theme))

      if (this.isLoading) {
        // 加载中
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
          Text(t('loading'))
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.hasError) {
        // 加载失败
        Column() {
          Text('加载失败')
            .fontSize(16)
            .fontColor('#999999')
          Text('请返回重试')
            .fontSize(14)
            .fontColor('#CCCCCC')
            .margin({ top: 8 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.songList.length === 0) {
        // 空状态
        Column() {
          Text('暂无歌曲')
            .fontSize(14)
            .fontColor('#999999')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 歌单信息头部
        this.Header()

        // 歌曲列表
        this.SongList()
      }

      // 播放器栏（组件内部处理底部沉浸）
      PlayerBar({ immersiveBottom: true })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}

// 歌曲项类型
interface SongItem {
  id: string;
  name: string;
  singer: string;
  album: string;
  duration: number;
  isPlaying: boolean;
  source: string;
  pic: string;
  albumId?: string;
  songmid?: string;
  /** QQ 源文件 mid，取链与 vkey 必需；与 song mid 可能不同 */
  strMediaMid?: string;
  hash?: string;
  /** 咪咕取播放链必需 */
  copyrightId?: string;
}

// 歌单信息类型
interface SonglistInfo {
  source: string;
  id: string;
  name: string;
  creator: string;
  pic: string;
  desc: string;
  playCount: number;
}

// 下载任务状态
type DownloadTaskStatus = 'pending' | 'downloading' | 'completed' | 'failed' | 'paused';

// 下载任务类型
interface DownloadTask {
  id: string;
  songId: string;
  songName: string;
  singer: string;
  album: string;
  source: string;
  url: string;
  quality: string;
  status: DownloadTaskStatus;
  progress: number;
  createTime: number;
}
