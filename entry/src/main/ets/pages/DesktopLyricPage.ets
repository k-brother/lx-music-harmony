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
  @StorageLink('desktopLyricColor') lyricColor: string = '#FFFFFF';
  @StorageLink('desktopLyricBgAlpha') lyricBgAlpha: number = 0;
  @StorageLink('desktopLyricFontSize') lyricFontSize: number = 18;
  @StorageLink('desktopLyricShowNext') showNext: boolean = true;
  @StorageLink('desktopLyricLocked') locked: boolean = false;

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
        .fontColor(this.lyricColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
        // 透明背景下用描边/阴影保证可读性
        .textShadow({ radius: 4, color: '#99000000', offsetX: 0, offsetY: 1 })

      if (this.showNext && this.nextText.length > 0) {
        Text(this.nextText)
          .fontSize(Math.max(12, this.lyricFontSize * 0.78))
          .fontColor(this.nextLyricColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width('100%')
          .margin({ top: 2 })
          .textShadow({ radius: 3, color: '#88000000', offsetX: 0, offsetY: 1 })
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** 给 '#RRGGBB' 颜色加透明度，输出 ArkUI 的 '#AARRGGBB' */
  private withAlpha(alphaHex: string): string {
    const color: string = this.lyricColor;
    if (color.length === 7 && color.charAt(0) === '#') {
      return `#${alphaHex}${color.substring(1)}`;
    }
    return `#${alphaHex}FFFFFF`;
  }

  /** 下一句用当前颜色的半透明版本，形成层次 */
  private nextLyricColor(): string {
    return this.withAlpha('B0');
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
