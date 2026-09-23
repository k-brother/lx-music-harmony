/**
 * 播放页歌词面板（歌词 + 可选的可拖动进度线）
 *
 * 从 PlayDetailPage 抽成组件：歌词渲染交给 LyricView，
 * 这里补上「设置 → 歌词页显示播放进度」开启时的进度线与时间行。
 * 拖动中只预览（isSeeking/previewProgress），松手由页面决定何时 seek。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { LyricView } from '../../components/common/LyricView';

@Component
export struct LyricPane {
  @StorageProp('theme') theme: string = 'light';
  @Prop lyricLines: string[] = [];
  @Prop secondaryLyricLines: string[] = [];
  @Prop romaLines: string[] = [];
  @Prop currentLyricIndex: number = -1;
  /** 设置 → 歌词页显示播放进度 */
  @Prop showLyricProgress: boolean = false;
  @Prop progress: number = 0;
  @Prop isSeeking: boolean = false;
  @Prop previewProgress: number = 0;
  @Prop currentTime: string = '00:00';
  @Prop previewTime: string = '00:00';
  @Prop totalTime: string = '00:00';
  onSeekChange?: (value: number, mode: SliderChangeMode) => void;
  /** 点击某一行歌词 → 跳到该句（0 基下标） */
  onLineTap?: (index: number) => void;

  build() {
    Column() {
      LyricView({
        lyricLines: this.lyricLines,
        secondaryLyricLines: this.secondaryLyricLines,
        romaLines: this.romaLines,
        currentLyricIndex: this.currentLyricIndex,
        onLineTap: (index: number): void => {
          if (this.onLineTap) {
            this.onLineTap(index);
          }
        },
      })

      if (this.showLyricProgress) {
        Column({ space: 4 }) {
          Slider({
            value: (this.isSeeking ? this.previewProgress : this.progress) * 100,
            min: 0,
            max: 100,
            style: SliderStyle.OutSet,
          })
            .width('100%')
            .height(22)
            .blockColor(DesignTokens.accent())
            .trackColor(DesignTokens.mutedFill(this.theme))
            .selectedColor(DesignTokens.accent())
            .onChange((value: number, mode: SliderChangeMode) => {
              if (this.onSeekChange) {
                this.onSeekChange(value, mode);
              }
            })

          Row({ space: 4 }) {
            Text(this.isSeeking ? this.previewTime : this.currentTime)
              .fontSize(DesignTokens.fontMicro())
              .fontColor(this.isSeeking ? DesignTokens.accent() : DesignTokens.labelSecondary(this.theme))
            Text('/')
              .fontSize(DesignTokens.fontMicro())
              .fontColor(DesignTokens.labelTertiary(this.theme))
            Text(this.totalTime)
              .fontSize(DesignTokens.fontMicro())
              .fontColor(DesignTokens.labelTertiary(this.theme))
          }
          .width('100%')
          .justifyContent(FlexAlign.Start)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })
      }
    }
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .height('100%')
  }
}
