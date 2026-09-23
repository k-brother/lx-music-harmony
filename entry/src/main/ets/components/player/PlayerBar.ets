// 迷你播放器栏组件 - 对应 src/components/player/PlayerBar/index.tsx
// 显示在首页底部的迷你播放控制栏

import hilog from '@ohos.hilog';
import { t } from '../../service/LocalizationService';
import { navigationService, RouteName } from '../../service';
import { normalizeCoverUrl } from '../../utils/CommonUtils';

// 导入播放器服务
import { playerService } from '../../service/PlayerService';
import { hapticService } from '../../service/HapticService';

// 使用与PlayerService一致的MusicInfo接口
import type { MusicInfo } from '../../service/PlayerService';
import { DesignTokens } from '../../theme/DesignTokens';

@Component
export struct PlayerBar {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  @StorageProp('showAnimation') showAnimation: boolean = true;

  /** 统一的按压缩放反馈（卡片/按钮通用） */
  @Styles
  pressScale() {
    .scale({ x: 0.96, y: 0.96 })
  }

  /** 统一的按压变淡反馈（列表行/图标按钮通用） */
  @Styles
  pressDim() {
    .opacity(0.6)
  }
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
      this.pic = normalizeCoverUrl(info.pic || info.img || '');
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
      this.pic = normalizeCoverUrl(currentMusicInfo.pic || currentMusicInfo.img || '');
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
    hapticService.light();
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
    hapticService.selection();
    await playerService.playPrev();
  }

  // 下一曲
  async playNext(): Promise<void> {
    hapticService.selection();
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
    }
  }

  @Builder
  private BarCore() {
    Row() {
      this.MiniCover()

      this.MiniTitle()

      this.MiniControls()
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
    .shadow(DesignTokens.floatingShadow())
    .alignItems(VerticalAlign.Center)
  }

  /** 迷你条封面：点击进入播放页；加载失败回退占位图 */
  @Builder
  private MiniCover() {
    if (this.canRenderMiniCover(this.pic)) {
      Image(this.pic)
        .width(48)
        .height(48)
        .borderRadius(DesignTokens.radiusCover())
        .objectFit(ImageFit.Cover)
        .onError(() => {
          this.pic = '';
        })
        // 无障碍：迷你条封面点进去就是播放页
        .accessibilityText(t('a11y_play'))
        .onClick(() => {
          this.navigateToPlayDetailSafely();
        })
        .animation({ duration: this.showAnimation ? 200 : 0, curve: Curve.EaseOut })
    } else {
      Image($r('app.media.ic_player_cover_placeholder'))
        .width(48)
        .height(48)
        .borderRadius(DesignTokens.radiusCover())
        .objectFit(ImageFit.Cover)
        .accessibilityText(t('a11y_play'))
        .onClick(() => {
          this.navigateToPlayDetailSafely();
        })
    }

  }

  /** 歌名 / 歌手（整块可点进播放页） */
  @Builder
  private MiniTitle() {
    Column() {
      Text(this.musicName || t('not_playing_text'))
        .fontSize(DesignTokens.fontBody())
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.singer || t('select_song_hint'))
        .fontSize(DesignTokens.fontCaption())
        .fontColor(DesignTokens.labelSecondary(this.theme))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 3 })
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .margin({ left: 12 })
    // 点歌名/歌手区域也进播放页（主流迷你播放条都是「点哪都能进详情」）
    .accessibilityText(t('a11y_open_player'))
    .onClick(() => {
      this.navigateToPlayDetailSafely();
    })

  }

  /** 上一首 / 播放暂停 / 下一首 */
  @Builder
  private MiniControls() {
    Row({ space: 10 }) {
      Stack() {
        Circle({ width: DesignTokens.ctrlSm(), height: DesignTokens.ctrlSm() })
          .fill(DesignTokens.mutedFill(this.theme))
        Image($r('app.media.ic_pd_prev'))
          .width(DesignTokens.iconSm())
          .height(DesignTokens.iconSm())
          .fillColor(DesignTokens.labelPrimary(this.theme))
      }
      .scale({ x: 0.95, y: 0.95 })
      .responseRegion({ x: -7, y: -7, width: 44, height: 44 })
      .stateStyles({ pressed: this.pressDim })
      .accessibilityText(t('a11y_previous'))
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
            .fillColor(DesignTokens.onAccent())
        } else {
          Image($r('app.media.ic_pd_play'))
            .width(13)
            .height(13)
            .fillColor(DesignTokens.onAccent())
            .margin({ left: 1 })
        }
      }
      .scale({ x: 0.9, y: 0.9 })
      .responseRegion({ x: -4, y: -4, width: 44, height: 44 })
      .stateStyles({ pressed: this.pressDim })
      .accessibilityText(t('a11y_play'))
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
      .scale({ x: 0.95, y: 0.95 })
      .responseRegion({ x: -7, y: -7, width: 44, height: 44 })
      .stateStyles({ pressed: this.pressDim })
      .accessibilityText(t('a11y_next'))
      .onClick(() => {
        void this.playNext();
      })
    }
  }

  /**
   * 底部细进度线（主流音乐 App 迷你播放条的做法）：
   * 有歌曲且有进度时显示，给"在播"一个不抢眼的视觉反馈。
   */
  @Builder
  private ProgressLine() {
    if (this.progress > 0 && this.progress < 1) {
      Row() {
        Row()
          .width(`${Math.max(2, Math.round(this.progress * 100))}%`)
          .height(2)
          .backgroundColor(DesignTokens.accent())
          .borderRadius(1)
      }
      .width('100%')
      .height(2)
      .backgroundColor(DesignTokens.mutedFill(this.theme))
      .borderRadius(1)
      .margin({ left: DesignTokens.spaceGutter(), right: DesignTokens.spaceGutter() })
    }
  }

  build() {
    if (this.immersiveBottom) {
      Column() {
        this.BarCore()
        this.ProgressLine()
        Blank()
          .width('100%')
          .height(10)
      }
      .width('100%')
      .backgroundColor(DesignTokens.tabBarBg(this.theme))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    } else {
      Column() {
        this.BarCore()
        this.ProgressLine()
      }
      .width('100%')
    }
  }
}
