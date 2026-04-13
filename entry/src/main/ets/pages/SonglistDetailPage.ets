// 歌单详情页 - 对应 src/screens/SonglistDetail/index.tsx
// 显示歌单信息和歌曲列表

import hilog from '@ohos.hilog';
import { PlayerBar } from '../components/player/PlayerBar';
import { getSongListDetail, getMusicUrl, type SongListDetailResult } from '../core/music/MusicFeatureEntry';
import { NavigationParams } from '../service/NavigationService';
import { playerService, SongInfo } from '../service/PlayerService';
import { navigationService } from '../service/NavigationService';
import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { addMusicToList, LIST_IDS, MusicItem } from '../service/ListService';
import type { MusicInfo, MusicSource } from '../types/MusicTypes';

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
  @State listName: string = '歌单';
  @State creator: string = '未知';
  @State description: string = '';
  @State playCount: string = '0';
  @State songList: SongItem[] = [];
  @State isLoading: boolean = true;
  @State hasError: boolean = false;

  // 歌单信息
  @State listInfo: SonglistInfo = {
    source: '',
    id: '',
    name: '加载中...',
    creator: '',
    pic: '',
    desc: '',
    playCount: 0,
  };

  // 防止重复加载标志
  private detailLoaded: boolean = false;

  aboutToAppear() {
    hilog.info(0x0001, 'SonglistDetail', 'SonglistDetailPage appearing');
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
      // 封面和基本信息
      Row() {
        // 歌单封面
        if (this.listInfo.pic) {
          Image(this.listInfo.pic)
            .width(120)
            .height(120)
            .borderRadius(8)
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            Text('🎵')
              .fontSize(40)
              .fontColor('#CCCCCC')
          }
          .width(120)
          .height(120)
          .backgroundColor('#E0E0E0')
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }

        Column() {
          // 歌单名称
          Text(this.listInfo.name)
            .fontSize(16)
            .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
            .fontWeight(FontWeight.Medium)
            .maxLines(2)
            .margin({ bottom: 8 })

          // 创建者
          Text('创建者: ' + this.listInfo.creator)
            .fontSize(12)
            .fontColor('#999999')
            .maxLines(1)
            .margin({ bottom: 4 })

          // 播放量
          Text('播放: ' + this.formatPlayCountDisplay(this.listInfo.playCount))
            .fontSize(12)
            .fontColor('#999999')
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .padding({ left: 12 })
      }
      .width('100%')
      .padding(16)

      // 操作按钮
      Row() {
        // 播放全部
        Row() {
          Image($r('sys.symbol.play_fill'))
            .width(18)
            .height(18)
            .fillColor('#FFFFFF')
          Text('播放全部')
            .fontSize(14)
            .fontColor('#FFFFFF')
            .margin({ left: 6 })
        }
        .padding({ left: 20, right: 20, top: 8, bottom: 8 })
        .backgroundColor('#E63946')
        .borderRadius(20)
        .onClick(() => {
          this.playAll();
        })

        // 收藏
        Row() {
          Image($r('sys.symbol.heart'))
            .width(18)
            .height(18)
            .fillColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          Text('收藏')
            .fontSize(14)
            .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
            .margin({ left: 6 })
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(this.theme === 'dark' ? '#2C2C2C' : '#F0F0F0')
        .borderRadius(20)
        .onClick(() => {
          this.toggleCollect();
        })

        // 下载
        Row() {
          Image($r('sys.symbol.arrow_down_circle'))
            .width(18)
            .height(18)
            .fillColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          Text('下载')
            .fontSize(14)
            .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
            .margin({ left: 6 })
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(this.theme === 'dark' ? '#2C2C2C' : '#F0F0F0')
        .borderRadius(20)
        .onClick(() => {
          this.downloadAll();
        })
      }

      // 描述
      if (this.listInfo.desc) {
        Text(this.listInfo.desc)
          .fontSize(12)
          .fontColor('#999999')
          .maxLines(2)
          .padding({ left: 16, right: 16, top: 12 })
      }

      // 分割线
      Divider()
        .color('#F0F0F0')
        .margin({ top: 12 })
    }
    .width('100%')
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
  }

  @Builder
  SongList() {
    List() {
      ForEach(this.songList, (song: SongItem, index: number) => {
        ListItem() {
          Row() {
            // 序号
            Text((index + 1).toString())
              .fontSize(12)
              .fontColor('#999999')
              .width(32)
              .textAlign(TextAlign.Center)

            // 歌曲信息
            Column() {
              Text(song.name)
                .fontSize(15)
                .fontColor(song.isPlaying ? '#E63946' : (this.theme === 'dark' ? '#FFFFFF' : '#333333'))
                .maxLines(1)
              Text(song.singer + ' - ' + song.album)
                .fontSize(12)
                .fontColor('#999999')
                .maxLines(1)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            // 播放按钮
            if (song.isPlaying) {
              Image($r('sys.symbol.play'))
                .width(20)
                .height(20)
                .fillColor('#E63946')
            }

            // 更多按钮
            Image($r('sys.symbol.ellipsis_circle'))
              .width(20)
              .height(20)
              .fillColor('#999999')
              .onClick(() => {
                this.showSongMenu(song);
              })
          }
          .width('100%')
          .padding({ left: 8, right: 8, top: 12, bottom: 12 })
        }
        .onClick(() => {
          this.playSong(index);
        })
      })
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
    .divider({ strokeWidth: 0.5, color: '#F0F0F0', startMargin: 40 })
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
        name: result.info.name || '未知歌单',
        creator: result.info.author || '未知',
        pic: result.info.img || '',
        desc: result.info.desc || '',
        playCount: this.parsePlayCount(result.info.play_count),
      };
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
      return (count / 100000000).toFixed(1) + '亿';
    } else if (count >= 10000) {
      return (count / 10000).toFixed(1) + '万';
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
        quality: '128k',
        isRefresh: false,
        onToggleSource: null,
        allowToggleSource: true,
      });

      if (!url || url.length === 0) {
        hilog.error(0x0001, 'SonglistDetail', 'Failed to get music URL for song: %{public}s', song.name);
        return;
      }

      // 更新songInfo的URL
      songInfos[index].url = url;
      
      // 设置播放列表（现在URL已经可用）
      playerService.setPlayList(songInfos, index);
      hilog.info(0x0001, 'SonglistDetail', 'PlayList set with %{public}d songs, starting from index %{public}d', songInfos.length, index);

      hilog.info(0x0001, 'SonglistDetail', 'Got music URL, setting source and playing...');
      await playerService.setSource(songInfos[index], url, song.duration);
      await playerService.play();
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
      quality: '128k',
      isRefresh: false,
      onToggleSource: null,
      allowToggleSource: true,
    });

    if (!url || url.length === 0) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to get music URL for first song: %{public}s', firstSong.name);
      return;
    }

    // 更新第一首歌曲的URL
    songInfos[0].url = url;
    
    // 设置播放列表（现在第一首歌曲的URL已经可用）
    playerService.setPlayList(songInfos, 0);

    hilog.info(0x0001, 'SonglistDetail', 'Got music URL, setting source and playing...');
    await playerService.setSource(songInfos[0], url, firstSong.duration);
    await playerService.play();
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

  // 检查歌单是否已收藏
  private async isSonglistCollected(): Promise<boolean> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'music_collections');
      
      // 获取收藏列表
      const collectionsJson = await pref.get('songlists', '[]') as string;
      const collections = JSON.parse(collectionsJson) as Array<Record<string, Object>>;
      
      // 检查当前歌单是否在收藏列表中
      return collections.some((item: Record<string, Object>) => 
        item.id === this.listInfo.id && item.source === this.listInfo.source
      );
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to check collection status: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  // 添加到收藏
  private async addToCollections(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'music_collections');
      
      // 获取现有收藏列表
      const collectionsJson = await pref.get('songlists', '[]') as string;
      const collections: SonglistCollectionEntry[] = JSON.parse(collectionsJson) as SonglistCollectionEntry[];
      
      const exists = collections.some((item: SonglistCollectionEntry) =>
        item.id === this.listInfo.id && item.source === this.listInfo.source
      );
      
      if (!exists) {
        // 添加新收藏
        const newCollection: SonglistCollectionEntry = {
          id: this.listInfo.id,
          source: this.listInfo.source,
          name: this.listInfo.name,
          creator: this.listInfo.creator,
          pic: this.listInfo.pic,
          desc: this.listInfo.desc,
          playCount: this.listInfo.playCount,
          collectTime: Date.now()
        };
        
        collections.push(newCollection);
        
        // 保存收藏列表
        await pref.put('songlists', JSON.stringify(collections));
        await pref.flush();
        
        hilog.info(0x0001, 'SonglistDetail', 'Added to collections: %{public}s', this.listInfo.name);
      }
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to add to collections: %{public}s', JSON.stringify(err));
      const msg = err instanceof Error ? err.message : JSON.stringify(err);
      throw new Error(msg);
    }
  }

  // 从收藏中移除
  private async removeFromCollections(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'music_collections');
      
      // 获取现有收藏列表
      const collectionsJson = await pref.get('songlists', '[]') as string;
      let collections: SonglistCollectionEntry[] = JSON.parse(collectionsJson) as SonglistCollectionEntry[];
      
      collections = collections.filter((item: SonglistCollectionEntry) =>
        !(item.id === this.listInfo.id && item.source === this.listInfo.source)
      );
      
      // 保存更新后的收藏列表
      await pref.put('songlists', JSON.stringify(collections));
      await pref.flush();
      
      hilog.info(0x0001, 'SonglistDetail', 'Removed from collections: %{public}s', this.listInfo.name);
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to remove from collections: %{public}s', JSON.stringify(err));
      const msg = err instanceof Error ? err.message : JSON.stringify(err);
      throw new Error(msg);
    }
  }

  // 显示提示
  private showToast(message: string): void {
    // 在实际应用中，这里应该显示一个Toast提示
    // 暂时使用日志输出
    hilog.info(0x0001, 'SonglistDetail', 'Toast: %{public}s', message);
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
        '下载确认',
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
      const urlStr: string | null = await getMusicUrl({
        musicInfo: musicInfo,
        quality: '128k',
        isRefresh: false,
        onToggleSource: null,
        allowToggleSource: true,
      });
      
      if (!urlStr || urlStr.length === 0) {
        throw new Error('无法获取音乐URL');
      }
      
      const downloadTask: DownloadTask = {
        id: `${song.id}-${Date.now()}`,
        songId: song.id,
        songName: song.name,
        singer: song.singer,
        album: song.album,
        source: song.source,
        url: urlStr,
        quality: '128k',
        status: 'pending',
        progress: 0,
        createTime: Date.now()
      };
      
      await this.saveDownloadTask(downloadTask);
      await this.startDownload(downloadTask);
      
      hilog.info(0x0001, 'SonglistDetail', 'Download task created: %{public}s', song.name);
      
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to download song %{public}s: %{public}s',
        song.name, JSON.stringify(err));
      const msg = err instanceof Error ? err.message : JSON.stringify(err);
      throw new Error(msg);
    }
  }

  // 保存下载任务
  private async saveDownloadTask(task: DownloadTask): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'music_downloads');
      
      // 获取现有下载任务
      const tasksJson = await pref.get('tasks', '[]') as string;
      const tasks = JSON.parse(tasksJson) as DownloadTask[];
      
      // 添加新任务
      tasks.push(task);
      
      // 保存任务列表
      await pref.put('tasks', JSON.stringify(tasks));
      await pref.flush();
      
      hilog.info(0x0001, 'SonglistDetail', 'Download task saved: %{public}s', task.id);
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to save download task: %{public}s', JSON.stringify(err));
      const msg = err instanceof Error ? err.message : JSON.stringify(err);
      throw new Error(msg);
    }
  }

  // 开始下载（模拟实现）
  private async startDownload(task: DownloadTask): Promise<void> {
    // 启动下载服务
    hilog.info(0x0001, 'SonglistDetail', 'Starting download: %{public}s', task.songName);
    
    try {
      // TODO: 调用真实的下载服务
      await new Promise<void>((resolve: () => void) => {
        setTimeout((): void => {
          resolve();
        }, 1000);
      });
      
      await this.updateDownloadTaskStatus(task.id, 'completed', 100);
      
      hilog.info(0x0001, 'SonglistDetail', 'Download completed: %{public}s', task.songName);
    } catch (error) {
      hilog.error(0x0001, 'SonglistDetail', 'Download failed: %{public}s', JSON.stringify(error));
      await this.updateDownloadTaskStatus(task.id, 'failed', 0);
    }
  }

  // 更新下载任务状态
  private async updateDownloadTaskStatus(taskId: string, status: DownloadTaskStatus, progress: number): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const pref = await preferences.getPreferences(context, 'music_downloads');
      
      // 获取现有下载任务
      const tasksJson = await pref.get('tasks', '[]') as string;
      const tasks = JSON.parse(tasksJson) as DownloadTask[];
      
      // 更新任务状态
      const taskIndex = tasks.findIndex(t => t.id === taskId);
      if (taskIndex !== -1) {
        tasks[taskIndex].status = status;
        tasks[taskIndex].progress = progress;
        
        // 保存更新后的任务列表
        await pref.put('tasks', JSON.stringify(tasks));
        await pref.flush();
        
        hilog.info(0x0001, 'SonglistDetail', 'Download task updated: %{public}s - %{public}s', taskId, status);
      }
    } catch (err) {
      hilog.error(0x0001, 'SonglistDetail', 'Failed to update download task: %{public}s', JSON.stringify(err));
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
      { label: '添加到歌单', action: (): void => { this.addToPlaylist(song); } },
      { label: '下载', action: (): void => { this.downloadSongFromMenu(song); } },
      { label: '分享', action: (): void => { this.shareSong(song); } },
      { label: '查看歌手', action: (): void => { this.viewArtist(song); } },
      { label: '查看专辑', action: (): void => { this.viewAlbum(song); } }
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
      // 状态栏
      Row()
        .width('100%')
        .height(24)
        .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')

      // 顶部导航栏
      Row() {
        Image($r('sys.symbol.chevron_left'))
          .width(24)
          .height(24)
          .fillColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .onClick(() => {
            navigationService.back();
          })

        Text('歌单详情')
          .fontSize(16)
          .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })

        Blank()

        Image($r('sys.symbol.magnifyingglass'))
          .width(22)
          .height(22)
          .fillColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
          .margin({ right: 16 })
      }
      .width('100%')
      .height(44)
      .padding({ left: 12 })

      if (this.isLoading) {
        // 加载中
        Column() {
          LoadingProgress()
            .width(32)
            .height(32)
          Text('加载中...')
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

      // 播放器栏
      PlayerBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme === 'dark' ? '#121212' : '#FFFFFF')
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


