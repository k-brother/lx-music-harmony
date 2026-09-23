/**
 * 播放页底部控制条
 *
 * 从 PlayDetailPage 的 @Builder PlayerControls 抽成组件：
 * 进度（拖动中显示手指位置，松手才 seek）+ 上一首/播放暂停/下一首 + 三个常用入口。
 * 组件只认「显示值 + 回调」，seek 判定（是否允许拖动、松手才跳转）仍在页面，
 * 因为那部分要跟播放器交互。
 */
import { DesignTokens } from '../../theme/DesignTokens';

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

  /** 动作分发：集中一处，避免回调穿过多层 @Builder */
  private dispatch(kind: string): void {
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
        // 上一首
        Stack() {
          Circle({ width: DesignTokens.ctrlMd(), height: DesignTokens.ctrlMd() })
            .fill(DesignTokens.mutedFill(this.theme))
          Image($r('app.media.ic_pd_prev'))
            .width(DesignTokens.iconLg())
            .height(DesignTokens.iconLg())
            .fillColor(DesignTokens.labelPrimary(this.theme))
        }
        .onClick(() => {
          this.dispatch('prev');
        })
        // 播放 / 暂停（图标随播放状态变化，必须内联：@Builder 参数不会随状态刷新）
        Stack() {
          Circle({ width: DesignTokens.ctrlLg(), height: DesignTokens.ctrlLg() })
            .fill(DesignTokens.accent())
          if (this.isPlaying) {
            Image($r('app.media.ic_pd_pause'))
              .width(20)
              .height(20)
              .fillColor(DesignTokens.onAccent())
          } else {
            Image($r('app.media.ic_pd_play'))
              .width(20)
              .height(20)
              .fillColor(DesignTokens.onAccent())
              .margin({ left: 1 })
          }
        }
        .onClick(() => {
          this.dispatch('play');
        })
        // 下一首
        Stack() {
          Circle({ width: DesignTokens.ctrlMd(), height: DesignTokens.ctrlMd() })
            .fill(DesignTokens.mutedFill(this.theme))
          Image($r('app.media.ic_pd_next'))
            .width(DesignTokens.iconLg())
            .height(DesignTokens.iconLg())
            .fillColor(DesignTokens.labelPrimary(this.theme))
        }
        .onClick(() => {
          this.dispatch('next');
        })
      }
      .width('100%')
      .height(92)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Row() {
        // 三个入口全部内联：文案是动态的（播放模式会变），不能经过 @Builder 参数
        Column({ space: 5 }) {
          Stack() {
            Circle({ width: 30, height: 30 })
              .fill(DesignTokens.mutedFill(this.theme))
            Image($r('app.media.ic_pd_playlist'))
              .width(DesignTokens.iconSm())
              .height(DesignTokens.iconSm())
              .fillColor(DesignTokens.labelSecondary(this.theme))
          }
          Text(this.addToListText)
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
          this.dispatch('add');
        })

        Column({ space: 5 }) {
          Stack() {
            Circle({ width: 30, height: 30 })
              .fill(DesignTokens.mutedFill(this.theme))
            Image($r('app.media.ic_pd_loop'))
              .width(DesignTokens.iconSm())
              .height(DesignTokens.iconSm())
              .fillColor(DesignTokens.labelSecondary(this.theme))
          }
          Text(this.playModeText)
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
          this.dispatch('mode');
        })

        Column({ space: 5 }) {
          Stack() {
            Circle({ width: 30, height: 30 })
              .fill(DesignTokens.mutedFill(this.theme))
            Image($r('app.media.ic_pd_comment'))
              .width(DesignTokens.iconSm())
              .height(DesignTokens.iconSm())
              .fillColor(DesignTokens.labelSecondary(this.theme))
          }
          Text(this.commentText)
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
          this.dispatch('comment');
        })
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
  }
}
