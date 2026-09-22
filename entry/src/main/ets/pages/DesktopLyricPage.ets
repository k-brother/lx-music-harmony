/**
 * 桌面歌词子窗口页面
 *
 * 由 DesktopLyricWindow 通过 createSubWindow + setUIContent 加载。
 * 视觉上是"歌词浮在屏幕上"，不是一条黑底横幅：
 * - 默认背景全透明，靠文字描边 + 阴影保证任何壁纸下都能看清；
 * - 背景不透明度、字号、颜色、单双行都来自设置，实时生效；
 * - 未锁定时可拖动（拖动结束把坐标回写为自定义位置），锁定后点击穿透。
 */

import hilog from '@ohos.hilog';
import { t } from '../service/LocalizationService';
import { DesktopLyricManager } from '../components/common/DesktopLyric';

const DOMAIN: number = 0x0002;
const TAG: string = 'DesktopLyricPage';
/** 拖动过程中的节流（毫秒）：拖动时实时跟随，但不至于每帧都调窗口 API */
const DRAG_COMMIT_INTERVAL_MS: number = 60;

@Entry
@Component
struct DesktopLyricPage {
  @StorageLink('desktopLyricText') lyricText: string = '';
  @StorageLink('desktopLyricNextText') nextText: string = '';
  @StorageLink('desktopLyricNext2Text') next2Text: string = '';
  /** 未播放行颜色（安卓版 desktopLyric.style.lyricUnplayColor） */
  @StorageLink('desktopLyricColor') lyricColor: string = '#FFFFFF';
  /** 当前行颜色（安卓版 desktopLyric.style.lyricPlayedColor） */
  @StorageLink('desktopLyricPlayedColor') playedColor: string = '#07C556';
  @StorageLink('desktopLyricBgAlpha') lyricBgAlpha: number = 0;
  @StorageLink('desktopLyricFontSize') lyricFontSize: number = 18;
  @StorageLink('desktopLyricLocked') locked: boolean = false;
  @StorageLink('desktopLyricMaxLines') maxLines: number = 2;
  @StorageLink('desktopLyricSingleLine') singleLine: boolean = false;
  @StorageLink('desktopLyricTextPositionX') textPosX: string = 'left';
  @StorageLink('desktopLyricTextPositionY') textPosY: string = 'top';
  /** 歌词文字不透明度 0-100（安卓版 desktopLyric.style.opacity） */
  @StorageLink('desktopLyricTextOpacity') textOpacity: number = 100;
  @StorageLink('desktopLyricAnim') animEnabled: boolean = true;
  @StorageLink('desktopLyricShadowColor') shadowColor: string = '#99000000';

  private windowX: number = 0;
  private windowY: number = 0;
  private dragBaseX: number = 0;
  private dragBaseY: number = 0;
  private dragAccumX: number = 0;
  private dragAccumY: number = 0;
  private lastCommitAt: number = 0;

  aboutToAppear(): void {
    const pos: number[] = DesktopLyricManager.getPosition();
    this.windowX = pos[0];
    this.windowY = pos[1];
    hilog.info(DOMAIN, TAG, 'DesktopLyricPage appear, window=(%{public}d,%{public}d), locked=%{public}s',
      this.windowX, this.windowY, this.locked.toString());
  }

  private backgroundHex(): string {
    const alpha: number = Math.max(0, Math.min(100, this.lyricBgAlpha));
    if (alpha <= 0) {
      return '#00000000';
    }
    const hex: string = Math.round(alpha * 255 / 100).toString(16).padStart(2, '0').toUpperCase();
    return `#${hex}000000`;
  }

  /** 开始拖动：记录起点，后续位移都相对这个起点累计 */
  private beginDrag(): void {
    this.dragBaseX = this.windowX;
    this.dragBaseY = this.windowY;
    this.dragAccumX = 0;
    this.dragAccumY = 0;
    this.lastCommitAt = 0;
  }

  /** 拖动中：节流地移动真实窗口（窗口只有一两行高，靠内容偏移会超出边界被裁剪） */
  private onDragUpdate(deltaX: number, deltaY: number): void {
    this.dragAccumX += deltaX;
    this.dragAccumY += deltaY;
    const now: number = Date.now();
    if (now - this.lastCommitAt < DRAG_COMMIT_INTERVAL_MS) {
      return;
    }
    this.lastCommitAt = now;
    this.windowX = this.dragBaseX + this.dragAccumX;
    this.windowY = this.dragBaseY + this.dragAccumY;
    DesktopLyricManager.dragTo(this.windowX, this.windowY);
  }

  /** 拖动结束：把绝对坐标提交给窗口管理器（同时记为自定义位置） */
  private endDrag(): void {
    this.windowX = this.dragBaseX + this.dragAccumX;
    this.windowY = this.dragBaseY + this.dragAccumY;
    DesktopLyricManager.moveTo(this.windowX, this.windowY);
    hilog.info(DOMAIN, TAG, 'Desktop lyric moved to (%{public}d,%{public}d)', this.windowX, this.windowY);
  }

  @Builder
  LyricText() {
    Column() {
      Text(this.lyricText.length > 0 ? this.lyricText : t('music_playing'))
        .fontSize(this.lyricFontSize)
        .fontWeight(FontWeight.Medium)
        // 当前句用「已播放颜色」，其余行用「未播放颜色」
        .fontColor(this.playedColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(this.textAlignMode())
        .width('100%')
        .opacity(this.textOpacity / 100)
        // 透明背景下用描边/阴影保证可读性
        .textShadow({ radius: 4, color: this.shadowColor, offsetX: 0, offsetY: 1 })

      if (!this.singleLine && this.maxLines >= 2 && this.nextText.length > 0) {
        Text(this.nextText)
          .fontSize(Math.max(12, this.lyricFontSize * 0.78))
          .fontColor(this.unplayColor('B0'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(this.textAlignMode())
          .width('100%')
          .margin({ top: 2 })
          .opacity(this.textOpacity / 100)
          .textShadow({ radius: 3, color: this.shadowColor, offsetX: 0, offsetY: 1 })
      }

      if (!this.singleLine && this.maxLines >= 3 && this.next2Text.length > 0) {
        Text(this.next2Text)
          .fontSize(Math.max(11, this.lyricFontSize * 0.7))
          .fontColor(this.unplayColor('66'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(this.textAlignMode())
          .width('100%')
          .margin({ top: 2 })
          .opacity(this.textOpacity / 100)
          .textShadow({ radius: 3, color: this.shadowColor, offsetX: 0, offsetY: 1 })
      }
    }
    .width('100%')
    .justifyContent(this.verticalAlignMode())
    .alignItems(this.horizontalAlignMode())
    .animation({ duration: this.animEnabled ? 220 : 0, curve: Curve.EaseOut })
  }

  /** 给 '#RRGGBB' 的未播放颜色加透明度，输出 ArkUI 的 '#AARRGGBB' */
  private unplayColor(alphaHex: string): string {
    const color: string = this.lyricColor;
    if (color.length === 7 && color.charAt(0) === '#') {
      return `#${alphaHex}${color.substring(1)}`;
    }
    return `#${alphaHex}FFFFFF`;
  }

  /** 文字水平位置设置 -> TextAlign（安卓版 desktopLyric.textPosition.x） */
  private textAlignMode(): TextAlign {
    if (this.textPosX === 'left') {
      return TextAlign.Start;
    }
    if (this.textPosX === 'right') {
      return TextAlign.End;
    }
    return TextAlign.Center;
  }

  private horizontalAlignMode(): HorizontalAlign {
    if (this.textPosX === 'left') {
      return HorizontalAlign.Start;
    }
    if (this.textPosX === 'right') {
      return HorizontalAlign.End;
    }
    return HorizontalAlign.Center;
  }

  /** 文字垂直位置设置 -> FlexAlign（安卓版 desktopLyric.textPosition.y） */
  private verticalAlignMode(): FlexAlign {
    if (this.textPosY === 'top') {
      return FlexAlign.Start;
    }
    if (this.textPosY === 'bottom') {
      return FlexAlign.End;
    }
    return FlexAlign.Center;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column() {
        this.LyricText()
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 16, right: 16, top: 4, bottom: 4 })
      .backgroundColor(this.backgroundHex())
      .borderRadius(10)
      .gesture(
        PanGesture({ fingers: 1, distance: 4 })
          .onActionStart(() => {
            if (this.locked) {
              return;
            }
            this.beginDrag();
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.locked) {
              return;
            }
            this.onDragUpdate(event.offsetX, event.offsetY);
          })
          .onActionEnd(() => {
            if (this.locked) {
              return;
            }
            this.endDrag();
          })
      )
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }
}
