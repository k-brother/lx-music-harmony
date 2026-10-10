// 迷你播放器栏组件 - 对应 src/components/player/PlayerBar/index.tsx
// 显示在首页底部的迷你播放控制栏

import { hilog } from '@kit.PerformanceAnalysisKit';
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
  /**
   * 玻璃形态：交给首页的底部玻璃底舱（迷你播放条 + Tab 栏合成一片玻璃）。
   * 玻璃形态下左右留白由底舱统一给，条本身不再自己加外边距 —— 否则两处留白会叠成 32vp。
   */
  @Prop glass: boolean = false;
  /**
   * 收拢态：与底部 Tab 栏联动（内容滚离顶部时）。此时左侧让出一个动作位（`leading`），
   * 播放控件整体靠右 —— 对齐华为音乐滚动后的那条"主页 + 播放控件"迷你条。
   */
  @Prop compact: boolean = false;
  /** 收拢态左侧的动作（"回到顶部"这类）；未传时不占位 */
  @BuilderParam leading?: () => void;
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
      this.LeadingSlot()

      this.MiniCover()

      this.MiniTitle()

      this.MiniControls()
    }
    .width('100%')
    // 高度与内边距都走 token：迷你条的尺寸整组由 DesignTokens 定义，便于平板/PC 另算
    .height(DesignTokens.miniBarHeight())
    .padding({
      left: DesignTokens.miniPaddingH(),
      right: DesignTokens.miniPaddingH(),
      top: (DesignTokens.miniBarHeight() - DesignTokens.miniCoverSize()) / 2,
      bottom: (DesignTokens.miniBarHeight() - DesignTokens.miniCoverSize()) / 2,
    })
    .margin({
      left: this.glass ? 0 : DesignTokens.spaceGutter(),
      right: this.glass ? 0 : DesignTokens.spaceGutter(),
      // 玻璃形态下与 Tab 栏的间距由底舱的 Column space 统一给，这里不再自己加
      bottom: this.immersiveBottom || this.glass ? 0 : 4,
    })
    // 玻璃形态下条本身是"裸内容"：材质（底色/模糊/描边/投影/沉浸材质）由底舱容器统一给，
    // 这样底舱是一整片玻璃，而不是两片各自带阴影的药丸（后者视觉上更高更碎）
    .backgroundColor(this.glass ? Color.Transparent : DesignTokens.chromeBar(this.theme))
    .backgroundBlurStyle(BlurStyle.NONE)
    .borderRadius(DesignTokens.radiusCard())
    .border({
      width: this.glass ? 0 : 0.33,
      color: DesignTokens.cardBorder(this.theme),
    })
    .shadow(this.glass ? DesignTokens.noShadow() : DesignTokens.floatingShadow())
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 收拢态左侧的动作位。
   * 宽度从 0 到 40 渐变（不用 if 分支）：滚动回调里触发的状态变化没有 animateTo 上下文，
   * 分支切换会"跳"，而宽度/透明度动画始终是顺的。
   */
  @Builder
  private LeadingSlot() {
    Row() {
      if (this.leading) {
        this.leading()
      }
    }
    .width(this.compact && this.leading ? DesignTokens.miniActionSlot() : 0)
    .height(DesignTokens.miniActionSlot())
    // 收拢后与封面留一点间距；展开态宽度为 0，这里也跟着回到 0，不会多出空档
    .margin({ right: this.compact ? DesignTokens.spaceUnit() / 2 : 0 })
    .opacity(this.compact ? 1 : 0)
    .clip(true)
    .animation({ duration: 220, curve: Curve.EaseOut })
  }

  /** 迷你条封面：点击进入播放页；加载失败回退占位图 */
  @Builder
  private MiniCover() {
    if (this.canRenderMiniCover(this.pic)) {
      Image(this.pic)
        .width(DesignTokens.miniCoverSize())
        .height(DesignTokens.miniCoverSize())
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
        .width(DesignTokens.miniCoverSize())
        .height(DesignTokens.miniCoverSize())
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
    .margin({ left: DesignTokens.miniPaddingH() })
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
        Circle({ width: DesignTokens.miniPlaySize(), height: DesignTokens.miniPlaySize() })
          .fill(DesignTokens.accent())
        if (this.isPlay) {
          Image($r('app.media.ic_pd_pause'))
            .width(12)
            .height(12)
            .fillColor(DesignTokens.onAccent())
        } else {
          Image($r('app.media.ic_pd_play'))
            .width(12)
            .height(12)
            .fillColor(DesignTokens.onAccent())
            .margin({ left: 1 })
        }
      }
      .scale({ x: 0.94, y: 0.94 })
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
