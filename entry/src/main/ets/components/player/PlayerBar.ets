// 迷你播放器栏组件 - 对应 src/components/player/PlayerBar/index.tsx
// 显示在首页底部的迷你播放控制栏

import hilog from '@ohos.hilog';
import { navigationService, RouteName } from '../../service';

// 导入播放器服务
import { playerService } from '../../service/PlayerService';

// 使用与PlayerService一致的MusicInfo接口
import type { MusicInfo } from '../../service/PlayerService';
import { DesignTokens } from '../../theme/DesignTokens';

@Component
export struct PlayerBar {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('primaryColor') primaryColor: string = '#E63946';
  @Prop immersiveBottom: boolean = false;
  @State isPlay: boolean = false;
  @State musicName: string = '';
  @State singer: string = '';
  @State pic: string = '';
  @State progress: number = 0;
  @State nowPlayTimeStr: string = '00:00';
  @State maxPlayTimeStr: string = '00:00';

  // 每个实例独立订阅，避免 this 指向问题
  private unsubscribePlayState: (() => void) | null = null;
  private unsubscribeMusicInfo: (() => void) | null = null;
  private unsubscribeProgress: (() => void) | null = null;
  private alive: boolean = false;
  private navLocked: boolean = false;
  private navUnlockTimer: number = -1;
  private clickSeq: number = 0;

  private normalizeCoverUrl(rawUrl: string): string {
    const url = (rawUrl ?? '').trim();
    if (url.length === 0) {
      return '';
    }
    if (url.startsWith('//')) {
      return `https:${url}`;
    }
    if (url.startsWith('http://') && (url.includes('kuwo.cn') || url.includes('kwcdn.kuwo.cn'))) {
      return `https://${url.substring(7)}`;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    return '';
  }

  private canRenderMiniCover(url: string): boolean {
    const value = (url ?? '').trim();
    if (value.length === 0) {
      return false;
    }
    return value.startsWith('http://') || value.startsWith('https://') || value.startsWith('//');
  }

  aboutToAppear() {
    this.alive = true;
    hilog.info(0x0001, 'PlayerBar', 'aboutToAppear, registering listeners, navLocked=%{public}s', this.navLocked.toString());

    // 订阅播放状态变化
    this.unsubscribePlayState = playerService.onPlayStateChange((isPlay: boolean) => {
      if (!this.alive) {
        return;
      }
      hilog.info(0x0001, 'PlayerBar', 'isPlay changed to %{public}s', isPlay.toString());
      this.isPlay = isPlay;
    });

    // 订阅音乐信息变化
    this.unsubscribeMusicInfo = playerService.onMusicInfoChange((info: MusicInfo) => {
      if (!this.alive) {
        return;
      }
      hilog.info(0x0001, 'PlayerBar', 'musicInfo updated - name: %{public}s, pic: %{public}s', info.name, info.pic || 'null');
      this.musicName = info.name;
      this.singer = info.singer;
      this.pic = this.normalizeCoverUrl(info.pic || info.img || '');
    });

    // 订阅进度变化
    this.unsubscribeProgress = playerService.onProgressInfoChange((prog) => {
      if (!this.alive) {
        return;
      }
      this.progress = prog.progress;
      this.nowPlayTimeStr = prog.nowPlayTimeStr;
      this.maxPlayTimeStr = prog.maxPlayTimeStr;
    });

    // 初始化时获取当前播放状态和音乐信息
    this.isPlay = playerService.isPlaying();

    // 获取当前音乐信息
    const currentMusicInfo = playerService.getCurrentMusicInfo();
    if (currentMusicInfo && currentMusicInfo.name) {
      this.musicName = currentMusicInfo.name;
      this.singer = currentMusicInfo.singer;
      this.pic = this.normalizeCoverUrl(currentMusicInfo.pic || currentMusicInfo.img || '');
    }
  }

  aboutToDisappear() {
    this.alive = false;
    if (this.navUnlockTimer !== -1) {
      clearTimeout(this.navUnlockTimer);
      this.navUnlockTimer = -1;
    }
    this.navLocked = false;
    hilog.info(0x0001, 'PlayerBar', 'aboutToDisappear, unregistering listeners');

    if (this.unsubscribePlayState) {
      this.unsubscribePlayState();
      this.unsubscribePlayState = null;
    }
    if (this.unsubscribeMusicInfo) {
      this.unsubscribeMusicInfo();
      this.unsubscribeMusicInfo = null;
    }
    if (this.unsubscribeProgress) {
      this.unsubscribeProgress();
      this.unsubscribeProgress = null;
    }
  }

  // 播放/暂停 - 先获取实际状态再执行
  async togglePlay(): Promise<void> {
    // 每次点击前先获取实际播放状态
    const actualIsPlaying = playerService.isPlaying();
    hilog.info(0x0001, 'PlayerBar', 'togglePlay: actual state is %{public}s', actualIsPlaying.toString());

    if (actualIsPlaying) {
      hilog.info(0x0001, 'PlayerBar', 'Calling pause...');
      await playerService.pause();
    } else {
      hilog.info(0x0001, 'PlayerBar', 'Calling play...');
      await playerService.play();
    }
    // 状态会通过 onPlayStateChange 回调自动更新
  }

  // 上一曲
  async playPrev(): Promise<void> {
    await playerService.playPrev();
  }

  // 下一曲
  async playNext(): Promise<void> {
    await playerService.playNext();
  }

  private navigateToPlayDetailSafely(): void {
    this.clickSeq += 1;
    const clickId = this.clickSeq;
    hilog.info(0x0001, 'PlayerBar',
      'coverClick id=%{public}d, navLocked=%{public}s, music=%{public}s, picLen=%{public}d',
      clickId, this.navLocked.toString(), this.musicName || '-', this.pic.length);
    if (this.navLocked) {
      hilog.warn(0x0001, 'PlayerBar', 'coverClick id=%{public}d skipped by navLocked', clickId);
      return;
    }
    this.navLocked = true;
    if (this.navUnlockTimer !== -1) {
      clearTimeout(this.navUnlockTimer);
      this.navUnlockTimer = -1;
    }
    this.navUnlockTimer = setTimeout(() => {
      this.navLocked = false;
      this.navUnlockTimer = -1;
      hilog.info(0x0001, 'PlayerBar', 'coverClick id=%{public}d unlock timer fired', clickId);
    }, 350);
    try {
      hilog.info(0x0001, 'PlayerBar', 'coverClick id=%{public}d navigateTo playdetail', clickId);
      navigationService.navigateTo(RouteName.PLAY_DETAIL);
    } catch (e) {
      this.navLocked = false;
      hilog.error(0x0001, 'PlayerBar', 'coverClick id=%{public}d navigate exception: %{public}s', clickId, JSON.stringify(e));
      console.error('PlayerBar: Navigation failed:', JSON.stringify(e));
    }
  }

  @Builder
  private BarCore() {
    Row() {
      if (this.canRenderMiniCover(this.pic)) {
        Image(this.pic)
          .width(48)
          .height(48)
          .borderRadius(DesignTokens.radiusCover())
          .objectFit(ImageFit.Cover)
          .onError(() => {
            this.pic = '';
          })
          .onClick(() => {
            this.navigateToPlayDetailSafely();
          })
      } else {
        Image($r('app.media.ic_player_cover_placeholder'))
          .width(48)
          .height(48)
          .borderRadius(DesignTokens.radiusCover())
          .objectFit(ImageFit.Cover)
          .onClick(() => {
            this.navigateToPlayDetailSafely();
          })
      }

      Column() {
        Text(this.musicName || '未在播放')
          .fontSize(DesignTokens.fontBody())
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.singer || '选择歌曲开始收听')
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      Row({ space: 10 }) {
        Stack() {
          Circle({ width: DesignTokens.ctrlSm(), height: DesignTokens.ctrlSm() })
            .fill(DesignTokens.mutedFill(this.theme))
          Image($r('app.media.ic_pd_prev'))
            .width(DesignTokens.iconSm())
            .height(DesignTokens.iconSm())
            .fillColor(DesignTokens.labelPrimary(this.theme))
        }
        .onClick(() => {
          void this.playPrev();
        })

        Stack() {
          Circle({ width: 36, height: 36 })
            .fill(DesignTokens.accent())
          if (this.isPlay) {
            Image($r('app.media.ic_pd_pause'))
              .width(13)
              .height(13)
              .fillColor('#FFFFFF')
          } else {
            Image($r('app.media.ic_pd_play'))
              .width(13)
              .height(13)
              .fillColor('#FFFFFF')
              .margin({ left: 1 })
          }
        }
        .onClick(() => {
          void this.togglePlay();
        })

        Stack() {
          Circle({ width: DesignTokens.ctrlSm(), height: DesignTokens.ctrlSm() })
            .fill(DesignTokens.mutedFill(this.theme))
          Image($r('app.media.ic_pd_next'))
            .width(DesignTokens.iconSm())
            .height(DesignTokens.iconSm())
            .fillColor(DesignTokens.labelPrimary(this.theme))
        }
        .onClick(() => {
          void this.playNext();
        })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(62)
    .padding({ left: 14, right: 14, top: 5, bottom: 5 })
    .margin({
      left: DesignTokens.spaceGutter(),
      right: DesignTokens.spaceGutter(),
      bottom: this.immersiveBottom ? 0 : 4,
    })
    .backgroundColor(DesignTokens.chromeBar(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .border({ width: 0.33, color: DesignTokens.cardBorder(this.theme) })
    .shadow({
      radius: 16,
      color: 'rgba(0,0,0,0.08)',
      offsetX: 0,
      offsetY: 4,
    })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    if (this.immersiveBottom) {
      Column() {
        this.BarCore()
        Blank()
          .width('100%')
          .height(10)
      }
      .width('100%')
      .backgroundColor(DesignTokens.tabBarBg(this.theme))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    } else {
      this.BarCore()
    }
  }
}
