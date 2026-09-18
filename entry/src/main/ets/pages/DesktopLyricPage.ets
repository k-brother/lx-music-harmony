/**
 * 桌面歌词子窗口页面 - 支持滚动歌词
 * 由 DesktopLyricWindow 通过 createSubWindow + setUIContent 加载
 */

import hilog from '@ohos.hilog';
import { t } from '../service/LocalizationService';
import { settingsService } from '../service/SettingsService';
import { DesktopLyricManager } from '../components/common/DesktopLyric';

const DOMAIN: number = 0x0002;
const TAG: string = 'DesktopLyricPage';

@Entry
@Component
struct DesktopLyricPage {
  @StorageLink('desktopLyricText') lyricText: string = t('music_playing');
  @StorageLink('desktopLyricColor') lyricColor: string = '#FFFFFF';
  @StorageLink('desktopLyricBgAlpha') lyricBgAlpha: number = 0.75;
  @StorageLink('desktopLyricPosition') lyricPosition: string = 'top'; // top, middle, bottom
  @StorageProp('theme') theme: string = 'light';
  @State private scrollX: number = 0;
  private animationTimer: number = -1;
  private scrollDirection: number = 1;

  aboutToAppear(): void {
    hilog.info(DOMAIN, TAG, 'DesktopLyricPage aboutToAppear, text=%{public}s', this.lyricText);
    this.startScrollAnimation();
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, TAG, 'DesktopLyricPage aboutToDisappear');
    this.stopScrollAnimation();
  }

  startScrollAnimation(): void {
    this.stopScrollAnimation();
    this.animationTimer = setInterval(() => {
      this.scrollX += this.scrollDirection * 2;
      if (this.scrollX > 100) {
        this.scrollDirection = -1;
      } else if (this.scrollX < -100) {
        this.scrollDirection = 1;
      }
    }, 50);
  }

  stopScrollAnimation(): void {
    if (this.animationTimer >= 0) {
      clearInterval(this.animationTimer);
      this.animationTimer = -1;
    }
  }

  build() {
    Stack() {
      Row() {
        // 歌词图标
        Text('♪')
          .fontSize(16)
          .fontColor(this.lyricColor + 'CC')
          .margin({ right: 10 })

        // 滚动歌词文本
        Text(this.lyricText)
          .fontSize(16)
          .fontColor(this.lyricColor)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Clip })
          .offset({ x: this.scrollX, y: 0 })

        Blank()

        // 关闭按钮
        Text('✕')
          .fontSize(14)
          .fontColor(this.lyricColor + '88')
          .padding({ left: 12, right: 4 })
          .onClick(() => {
            // 关闭按钮 = 关掉桌面歌词，并同步设置，避免设置里显示"已开启"但窗口消失
            DesktopLyricManager.setEnabled(false);
            settingsService.update({ showDesktopLyric: false }).catch((err: Error) => {
              hilog.warn(DOMAIN, TAG, 'Failed to persist desktop lyric off: %{public}s', err.message);
            });
          })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 16, right: 12 })
      .backgroundColor(`rgba(0,0,0,${this.lyricBgAlpha})`)
      .clip(true)
    }
    .width('100%')
    .height('100%')
  }
}
