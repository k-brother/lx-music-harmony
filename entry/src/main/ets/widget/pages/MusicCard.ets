/**
 * 桌面音乐卡片（ArkUI V1，服务卡片页）
 *
 * 数据流：UI 进程 CardFormService 与卡片进程 CardFormAbility 经 updateForm 推送
 * CardPushPayload（见 utils/CardFormPayload），键名与本页 @LocalStorageProp 一一对应。
 *
 * 视觉取舍（对齐华为音乐 / Apple Music 的系统音乐卡片）：
 * - 2*2：封面铺满 → 底部**渐变**压暗（不是一条硬边黑带）→ 左下标题/副标题 + 右下播放键；
 *   没有封面时给"上浅下深"的底板 + 淡音符，看着是有意的空态而不是没渲染出来。
 * - 2*4：左侧方形封面（带极细描边，亮封面也有边界）+ 右侧标题/副标题/控制条，
 *   标题与控制条共用同一条左对齐基线；播放键用白底深色图标（不挑封面配色，最醒目）。
 * - 底板一律走「上浅下深」微渐变 + 发丝描边，避免纯色块在壁纸上显得扁平。
 *
 * 约束：卡片由系统在独立进程渲染，拿不到应用主题状态，所以配色只从
 * theme/MediaOverlayTokens（媒体层调色板）取、字号走 DesignTokens 字阶；
 * 全部图形用 ArkUI 绘制 + SymbolGlyph，不引 rawfile 资源（引贴图会让换肤/深色失效）。
 * `sys.symbol.*` 的名字必须是真实存在的：SDK 里没有 `forward_fill`，
 * 上一首/下一首用 `backward_end_fill` / `forward_end_fill` 这一对，视觉才对称。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import {
  onMediaTextSecondary, onMediaLyricIdle,
  onMediaFillWeak, onMediaSurface, onMediaSurfaceDeep, onMediaScrim,
} from '../../theme/MediaOverlayTokens';

/** 卡片圆角（系统卡片的圆角由容器给，这里再兜一层，避免某些机型方角） */
const CARD_RADIUS: number = 16;
/** 封面缩略图圆角：比卡片小一档，看上去是"内嵌"而不是和卡片同形 */
const COVER_RADIUS: number = 10;
/** 2*2 播放键直径与图标字号（小卡片，克制一点） */
const SQUARE_PLAY_SIZE: number = 30;
const SQUARE_PLAY_GLYPH: number = 15;
/** 2*4 播放键直径与图标字号；上/下一首的触控区固定 40×40，保证手感 */
const WIDE_PLAY_SIZE: number = 34;
const WIDE_PLAY_GLYPH: number = 16;
const STEP_TOUCH_SIZE: number = 40;

@Entry
@Component
struct MusicCard {
  @LocalStorageProp('title') title: string = '';
  @LocalStorageProp('singer') singer: string = '';
  @LocalStorageProp('imgName') imgName: string = '';
  @LocalStorageProp('playing') playing: boolean = false;
  @LocalStorageProp('lyric') lyric: string = '';
  @LocalStorageProp('dimension') dimension: number = 3;
  @LocalStorageProp('formId') formId: string = '';

  private isSquareCard(): boolean {
    return this.dimension <= 2;
  }

  private hasCover(): boolean {
    return this.imgName.length > 0;
  }

  private displayTitle(): string {
    return this.title.length > 0 ? this.title : 'LX Music';
  }

  /** 副标题：优先当前歌词句，其次歌手；都没有时给空格，避免行高抖动 */
  private subTitle(): string {
    if (this.lyric.length > 0) {
      return this.lyric;
    }
    return this.singer.length > 0 ? this.singer : ' ';
  }

  private postAction(action: string): void {
    postCardAction(this, {
      action: 'call',
      abilityName: 'EntryAbility',
      params: {
        method: 'cardAction',
        actionType: action,
        formId: this.formId
      }
    });
  }

  /** 卡片底板：上浅下深微渐变（无封面时当背景，有封面时被封面盖住） */
  @Builder
  private Surface() {
    Column()
      .width('100%')
      .height('100%')
      .linearGradient({
        direction: GradientDirection.RightBottom,
        colors: [[onMediaSurface, 0.0], [onMediaSurfaceDeep, 1.0]],
      })
  }

  /** 无封面时的占位：淡音符（不再是一大块空底色） */
  @Builder
  private CoverPlaceholder() {
    Column() {
      SymbolGlyph($r('sys.symbol.music_note_circle'))
        .fontSize(DesignTokens.fontHero())
        .fontColor([onMediaLyricIdle])
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  /** 播放/暂停：白底深色图标（不挑封面配色，暗底上最醒目） */
  @Builder
  private PlayPauseButton(size: number, glyph: number, label: Resource) {
    Stack({ alignContent: Alignment.Center }) {
      // 同一个字号下三角（播放）看着比双竖线（暂停）小一圈，这里给播放 +2 补偿
      SymbolGlyph(this.playing ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
        .fontSize(this.playing ? glyph : glyph + 2)
        .fontColor([onMediaSurface])
        .accessibilityText(label)
    }
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .backgroundColor(Color.White)
    .onClick((): void => {
      this.postAction('playPause');
    })
  }

  /** 上/下一首：无底色，用 40×40 触控区保证手感 */
  @Builder
  private StepButton(symbol: Resource, action: string, label: Resource) {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph(symbol)
        .fontSize(DesignTokens.fontLarge())
        .fontColor([onMediaTextSecondary])
        .accessibilityText(label)
    }
    .width(STEP_TOUCH_SIZE)
    .height(STEP_TOUCH_SIZE)
    .onClick((): void => {
      this.postAction(action);
    })
  }

  /** 2*2：封面铺满 + 底部渐变压暗 + 左下文案 / 右下播放键 */
  @Builder
  private SquareLayout() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.hasCover()) {
        Image('memory://' + this.imgName)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        this.CoverPlaceholder()
      }

      // 渐变压暗：只在下半部分，从透明过渡到遮罩色。
      // 以前是一整条纯色黑带，卡片上会看到一条明显的横向硬边。
      Column()
        .width('100%')
        .height('52%')
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [[Color.Transparent, 0.0], [onMediaScrim, 1.0]],
        })

      Row({ space: 8 }) {
        Column() {
          Text(this.displayTitle())
            .fontSize(DesignTokens.fontSubhead())
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.subTitle())
            .fontSize(DesignTokens.fontMicro())
            .fontColor(onMediaTextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.PlayPauseButton(SQUARE_PLAY_SIZE, SQUARE_PLAY_GLYPH, $r('app.string.music_card_play_pause'))
      }
      .width('100%')
      .padding({ left: 12, right: 10, bottom: 10 })
      .alignItems(VerticalAlign.Bottom)
    }
    .width('100%')
    .height('100%')
  }

  /** 2*4：左方形封面 + 右标题/副标题/控制条（标题与控制条同一条左基线） */
  @Builder
  private RectangleLayout() {
    Row({ space: 12 }) {
      Column() {
        if (this.hasCover()) {
          Image('memory://' + this.imgName)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          Column() {
            SymbolGlyph($r('sys.symbol.music_note_circle'))
              .fontSize(DesignTokens.fontDisplay())
              .fontColor([onMediaLyricIdle])
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor(onMediaFillWeak)
        }
      }
      .height('100%')
      .aspectRatio(1)
      .borderRadius(COVER_RADIUS)
      .clip(true)
      // 极细描边：浅色封面上也有边界，不会和卡片底板糊在一起
      .border({ width: 0.5, color: onMediaFillWeak })

      Column() {
        Text(this.displayTitle())
          .fontSize(DesignTokens.fontHeadline())
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          // 文案与控制条同一条中轴线：右列比内容宽，全左对齐会显得挤在封面边上
          .textAlign(TextAlign.Center)
        Text(this.subTitle())
          .fontSize(DesignTokens.fontCaption())
          .fontColor(onMediaTextSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 3 })

        Row({ space: 2 }) {
          this.StepButton($r('sys.symbol.backward_end_fill'), 'previous', $r('app.string.music_card_previous'))
          this.PlayPauseButton(WIDE_PLAY_SIZE, WIDE_PLAY_GLYPH, $r('app.string.music_card_play_pause'))
          this.StepButton($r('sys.symbol.forward_end_fill'), 'next', $r('app.string.music_card_next'))
        }
        .width('100%')
        // 控制条在右列里居中：右列本身比三个按钮宽，贴着封面摆会左边挤、右边空
        .justifyContent(FlexAlign.Center)
        .margin({ top: 6 })
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding(12)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 底板在最里层：有封面时被封面盖住，没封面时就是卡片底色
      this.Surface()

      if (this.isSquareCard()) {
        this.SquareLayout()
      } else {
        this.RectangleLayout()
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(CARD_RADIUS)
    .clip(true)
    .onClick((): void => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { fromMusicCard: true }
      });
    })
  }
}
