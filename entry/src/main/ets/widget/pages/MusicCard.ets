/**
 * 桌面音乐卡片（ArkUI V1，服务卡片页）
 *
 * 数据流：UI 进程 CardFormService 与卡片进程 CardFormAbility 经 updateForm 推送
 * CardPushPayload（见 utils/CardFormPayload），键名与本页 @LocalStorageProp 一一对应。
 *
 * 样式说明：卡片不走 components/ui 主题体系（服务卡片由系统渲染、拿不到应用主题状态），
 * 配色统一从 theme/MediaOverlayTokens（媒体层调色板）取，字号走 DesignTokens 字阶。
 * 全部图形用 ArkUI 绘制，不引 rawfile 资源（对方项目 5 张 png 的做法会让换肤/暗色失效）。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import {
  onMediaTextSecondary, onMediaTextFaint, onMediaLyricIdle,
  onMediaFillWeak, onMediaFillStrong, onMediaSurface, onMediaScrim,
} from '../../theme/MediaOverlayTokens';

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

  private displayTitle(): string {
    return this.title.length > 0 ? this.title : 'LX Music';
  }

  /** 副标题：优先当前歌词句，其次歌手；为空时补空格避免布局抖动 */
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

  @Builder
  private CoverArt(radius: number) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.imgName.length > 0) {
        Image('memory://' + this.imgName)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music_note_circle'))
            .fontSize(DesignTokens.fontDisplay())
            .fontColor([onMediaTextFaint])
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(onMediaFillWeak)
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(radius)
    .clip(true)
  }

  @Builder
  private ControlButton(symbol: Resource, action: string, label: Resource, size: number) {
    SymbolGlyph(symbol)
      .fontSize(size)
      .fontColor([Color.White])
      .accessibilityText(label)
      .onClick((): void => {
        this.postAction(action);
      })
  }

  @Builder
  private PlayPauseButton(size: number, label: Resource) {
    Row() {
      SymbolGlyph(this.playing ? $r('sys.symbol.pause_fill') : $r('sys.symbol.play_fill'))
        .fontSize(size)
        .fontColor([Color.White])
        .accessibilityText(label)
    }
    .width(size + 24)
    .height(size + 24)
    .borderRadius((size + 24) / 2)
    .backgroundColor(onMediaFillStrong)
    .justifyContent(FlexAlign.Center)
    .onClick((): void => {
      this.postAction('playPause');
    })
  }

  @Builder
  private ControlRow(size: number, gap: number) {
    Row({ space: gap }) {
      this.ControlButton($r('sys.symbol.backward_fill'), 'previous', $r('app.string.music_card_previous'), size)
      this.PlayPauseButton(size, $r('app.string.music_card_play_pause'))
      this.ControlButton($r('sys.symbol.fast_forward'), 'next', $r('app.string.music_card_next'), size)
    }
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private TitleBlock(textAlign: TextAlign) {
    Text(this.displayTitle())
      .fontSize(DesignTokens.fontSubhead())
      .fontWeight(FontWeight.Bold)
      .fontColor(Color.White)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .textAlign(textAlign)
    Text(this.subTitle())
      .fontSize(DesignTokens.fontMicro())
      .fontColor(onMediaTextSecondary)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .textAlign(textAlign)
      .margin({ top: 3 })
  }

  /** 2*2：封面铺满，底部渐变压暗 + 左文右圆钮 */
  @Builder
  private SquareLayout() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.imgName.length > 0) {
        Image('memory://' + this.imgName)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.music_note_circle'))
            .fontSize(DesignTokens.fontHeroLarge())
            .fontColor([onMediaLyricIdle])
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor(onMediaSurface)
      }

      Row() {
        Column() {
          Text(this.displayTitle())
            .fontSize(DesignTokens.fontCallout())
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.subTitle())
            .fontSize(DesignTokens.fontBadge())
            .fontColor(onMediaTextSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        this.PlayPauseButton(14, $r('app.string.music_card_play_pause'))
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 16, bottom: 10 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(onMediaScrim)
    }
    .width('100%')
    .height('100%')
  }

  /** 2*4：左方形封面 + 右标题/副标题/控制条 */
  @Builder
  private RectangleLayout() {
    Row({ space: 10 }) {
      Column() {
        this.CoverArt(12)
      }
      .height('100%')
      .aspectRatio(1)
      Column() {
        this.TitleBlock(TextAlign.Start)
        Row() {
          this.ControlRow(18, 14)
        }
        .margin({ top: 8 })
      }
      .layoutWeight(1)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .padding(10)
    .backgroundColor(onMediaSurface)
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.isSquareCard()) {
        this.SquareLayout()
      } else {
        this.RectangleLayout()
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(16)
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
