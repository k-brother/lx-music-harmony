/**
 * 播放页底部控制条
 *
 * 从 PlayDetailPage 的 @Builder PlayerControls 抽成组件：
 * 进度（拖动中显示手指位置，松手才 seek）+ 上一首/播放暂停/下一首 + 三个常用入口。
 * 组件只认「显示值 + 回调」，seek 判定（是否允许拖动、松手才跳转）仍在页面，
 * 因为那部分要跟播放器交互。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { appLog as hilog } from '../../core/log/AppLogger';

@Component
export struct PlayerControls {
  @StorageProp('theme') theme: string = 'light';
  @Prop isPlaying: boolean = false;
  @Prop currentTime: string = '00:00';
  @Prop totalTime: string = '00:00';
  /** 播放进度（0-1） */
  @Prop progress: number = 0;
  /** 拖动中：用 previewProgress 预览目标位置 */
  @Prop isSeeking: boolean = false;
  @Prop previewProgress: number = 0;
  @Prop previewTime: string = '00:00';
  /** 播放模式文案（顺序播放 / 单曲循环…） */
  @Prop playModeText: string = '';
  /** 列表入口文案（添加到歌单） */
  @Prop addToListText: string = '';
  /** 评论入口文案 */
  @Prop commentText: string = '';

  onSeekChange?: (value: number, mode: SliderChangeMode) => void;
  onPrev?: () => void;
  onTogglePlay?: () => void;
  onNext?: () => void;
  onAddToList?: () => void;
  onToggleMode?: () => void;
  onComment?: () => void;

  /** 入口文案：在 Builder 内部按 kind 取，避免把动态文案当参数传 */
  private labelFor(kind: string): string {
    if (kind === 'add') {
      return this.addToListText;
    }
    if (kind === 'mode') {
      return this.playModeText;
    }
    return this.commentText;
  }

  /** 传送键图标：播放/暂停随播放状态变化 */
  private iconFor(kind: string): Resource {
    if (kind === 'prev') {
      return $r('app.media.ic_pd_prev');
    }
    if (kind === 'next') {
      return $r('app.media.ic_pd_next');
    }
    return this.isPlaying ? $r('app.media.ic_pd_pause') : $r('app.media.ic_pd_play');
  }

  /** 动作分发：集中一处，避免回调穿过多层 @Builder */
  private dispatch(kind: string): void {
    hilog.info(0x0001, 'PlayerControls', 'tap %{public}s', kind);
    if (kind === 'prev' && this.onPrev) {
      this.onPrev();
    } else if (kind === 'play' && this.onTogglePlay) {
      this.onTogglePlay();
    } else if (kind === 'next' && this.onNext) {
      this.onNext();
    } else if (kind === 'add' && this.onAddToList) {
      this.onAddToList();
    } else if (kind === 'mode' && this.onToggleMode) {
      this.onToggleMode();
    } else if (kind === 'comment' && this.onComment) {
      this.onComment();
    }
  }

  /**
   * 入口按钮（添加到歌单 / 播放模式 / 评论）。
   *
   * 规则（真机对照实验结论）：**@Builder 的参数不会随状态刷新**——
   * 把播放模式文案这种动态值当参数传进来，点了之后状态已变、界面还是旧文案。
   * 所以这里只传静态参数（图标 + 动作标识），会变的内容一律在 Builder 内部读 this.*。
   */
  @Builder
  MenuEntry(icon: Resource, kind: string) {
    Column({ space: 5 }) {
      Stack() {
        Circle({ width: 30, height: 30 })
          .fill(DesignTokens.mutedFill(this.theme))
        Image(icon)
          .width(DesignTokens.iconSm())
          .height(DesignTokens.iconSm())
          .fillColor(DesignTokens.labelSecondary(this.theme))
      }
      Text(this.labelFor(kind))
        .fontSize(DesignTokens.fontMicro())
        .fontColor(DesignTokens.labelSecondary(this.theme))
        .maxLines(1)
        .textAlign(TextAlign.Center)
    }
    .width(68)
    .height(60)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.dispatch(kind);
    })
  }

  /** 传送键的无障碍文案：播放键随状态在「播放 / 暂停」之间切换 */
  private transportLabel(kind: string): string {
    if (kind === 'prev') {
      return t('a11y_previous');
    }
    if (kind === 'next') {
      return t('a11y_next');
    }
    return this.isPlaying ? t('a11y_pause') : t('a11y_play');
  }

  /** 传送键（上一首 / 播放暂停 / 下一首）：图标随播放状态变化，同样在 Builder 内读状态 */
  @Builder
  TransportKey(kind: string, filled: boolean) {
    Stack() {
      Circle({ width: filled ? DesignTokens.ctrlLg() : DesignTokens.ctrlMd(), height: filled ? DesignTokens.ctrlLg() : DesignTokens.ctrlMd() })
        .fill(filled ? DesignTokens.accent() : DesignTokens.mutedFill(this.theme))
      Image(this.iconFor(kind))
        .width(filled ? 20 : DesignTokens.iconLg())
        .height(filled ? 20 : DesignTokens.iconLg())
        .fillColor(filled ? DesignTokens.onAccent() : DesignTokens.labelPrimary(this.theme))
        .margin(kind === 'play' && !this.isPlaying ? { left: 1 } : {})
    }
    // 无障碍：图标按钮必须能被朗读出来，且随播放状态切换「播放/暂停」
    .accessibilityText(this.transportLabel(kind))
    .onClick(() => {
      this.dispatch(kind);
    })
  }

  build() {
    Column() {
      Row() {
        Text(this.currentTime)
          .fontSize(DesignTokens.fontMicro())
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .width(44)
          .textAlign(TextAlign.Center)
        Slider({
          // 拖动中显示手指位置（previewProgress），松手才真正 seek
          value: (this.isSeeking ? this.previewProgress : this.progress) * 100,
          min: 0,
          max: 100,
          style: SliderStyle.OutSet,
        })
          .width('calc(100% - 88vp)')
          .height(24)
          .blockColor(DesignTokens.accent())
          .trackColor(DesignTokens.mutedFill(this.theme))
          .selectedColor(DesignTokens.accent())
          .onChange((value: number, mode: SliderChangeMode) => {
            if (this.onSeekChange) {
              this.onSeekChange(value, mode);
            }
          })
        // 右侧是总时长；拖动中显示预览位置，方便对齐歌词/试听
        Text(this.isSeeking ? this.previewTime : this.totalTime)
          .fontSize(DesignTokens.fontMicro())
          .fontColor(this.isSeeking ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme))
          .width(44)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .padding({ left: 14, right: 14 })

      Row({ space: 26 }) {
        this.TransportKey('prev', false)
        this.TransportKey('play', true)
        this.TransportKey('next', false)
      }
      .width('100%')
      .height(92)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Row() {
        this.MenuEntry($r('app.media.ic_pd_playlist'), 'add')
        this.MenuEntry($r('app.media.ic_pd_loop'), 'mode')
        this.MenuEntry($r('app.media.ic_pd_comment'), 'comment')
      }
      .width('100%')
      .height(78)
      .justifyContent(FlexAlign.SpaceAround)
      .alignItems(VerticalAlign.Center)
      .padding({ left: 10, right: 10 })

      Blank()
        .width('100%')
        .height(12)
    }
    .width('100%')
    .padding({ bottom: 8 })
    .backgroundColor(DesignTokens.pageBg(this.theme))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
