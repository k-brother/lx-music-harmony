/**
 * 实况窗锁屏沉浸页（ArkUI V1，独立子进程页面）
 *
 * 数据流：LiveViewAbility 在 onSessionCreate 时把初始负载塞进 LocalStorage
 * （LS_INIT_DATA_KEY），这里读出；之后的歌词句更新由 UIAbility 进程
 * LiveViewService 经 common event 广播（LIVE_VIEW_LYRIC_EVENT）。
 *
 * 与对方项目的差异（规范化适配）：
 * - 本进程没有 LocalizationService，「正在播放 / 已暂停 / 暂无歌词」等文案
 *   全部由发布方 t() 翻译后随负载下发，页面不写死任何字符串；
 * - 空下一句不渲染占位（对方固定渲染空 Text，会白占一行间距）；
 * - 播放状态做成标题区右侧的状态胶囊（对方放底部、靠 SpaceBetween 撑开，
 *   在矮屏上歌词会被挤变形）。
 *
 * 样式说明：锁屏页由系统渲染、拿不到应用主题状态，配色统一从
 * theme/MediaOverlayTokens（媒体层调色板）取，字号走 DesignTokens 字阶；
 * 与 widget/pages 同一套约定（check_design_tokens 已覆盖 liveview/ 与 widget/）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import {
  LS_INIT_DATA_KEY,
  LIVE_VIEW_LYRIC_EVENT,
  type LiveViewLyricPayload,
} from '../../utils/LiveViewKeys';
import { DesignTokens } from '../../theme/DesignTokens';
import {
  onMediaTextPrimary, onMediaTextTertiary, onMediaTextFaint,
  onMediaFillWeak, lockScreenScrim, liveViewAccent,
} from '../../theme/MediaOverlayTokens';

const TAG = 'LockScreenPage';
const DOMAIN = 0x0003;

@Entry({ useSharedStorage: true })
@Component
struct LockScreenPage {
  @State title: string = '';
  @State artist: string = '';
  @State curLine: string = '';
  @State nextLine: string = '';
  @State isPlaying: boolean = true;
  @State playingLabel: string = '';
  @State pausedLabel: string = '';
  @State noLyricLabel: string = '';
  /** 歌词事件订阅者，页面销毁时退订 */
  private subscriber: commonEventManager.CommonEventSubscriber | null = null;

  aboutToAppear(): void {
    this.loadInitialData();
    this.subscribeLyricEvent();
  }

  aboutToDisappear(): void {
    this.unsubscribeLyricEvent();
  }

  /** 从 Ability 注入的 LocalStorage 读初始负载 */
  private loadInitialData(): void {
    try {
      const storage: LocalStorage | undefined = this.getUIContext().getSharedLocalStorage();
      if (storage === undefined) {
        return;
      }
      const raw: string | undefined = storage.get<string>(LS_INIT_DATA_KEY);
      if (raw !== undefined && raw.length > 0) {
        this.applyPayload(JSON.parse(raw) as LiveViewLyricPayload);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'loadInitialData failed: %{public}s', JSON.stringify(err));
    }
  }

  private applyPayload(payload: LiveViewLyricPayload): void {
    this.title = payload.title;
    this.artist = payload.artist;
    this.curLine = payload.curLine;
    this.nextLine = payload.nextLine;
    this.isPlaying = payload.isPlaying;
    this.playingLabel = payload.playingLabel;
    this.pausedLabel = payload.pausedLabel;
    this.noLyricLabel = payload.noLyricLabel;
  }

  private subscribeLyricEvent(): void {
    try {
      const info: commonEventManager.CommonEventSubscribeInfo = {
        events: [LIVE_VIEW_LYRIC_EVENT],
      };
      commonEventManager.createSubscriber(info).then(
        (sub: commonEventManager.CommonEventSubscriber): void => {
          this.subscriber = sub;
          // 注意：subscribe 的第二个参数是 AsyncCallback<CommonEventData, void> 接口，
          // ArkTS 的严格函数类型检查要求回调参数列表与接口签名逐一对应（不能只写 data），
          // 否则 tsCheck 会报 "Types of parameters 'event' and 'err' are incompatible"。
          commonEventManager.subscribe(sub,
            (err: BusinessError, event: commonEventManager.CommonEventData): void => {
              if (err) {
                hilog.warn(DOMAIN, TAG, 'lyric event error: %{public}s', JSON.stringify(err));
                return;
              }
              const data: string | undefined = event.data;
              if (data !== undefined && data.length > 0) {
                try {
                  this.applyPayload(JSON.parse(data) as LiveViewLyricPayload);
                } catch (parseErr) {
                  hilog.warn(DOMAIN, TAG, 'parse payload failed: %{public}s', JSON.stringify(parseErr));
                }
              }
            });
        }).catch((err: BusinessError): void => {
        hilog.warn(DOMAIN, TAG, 'createSubscriber failed: %{public}s', JSON.stringify(err));
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'subscribeLyricEvent error: %{public}s', JSON.stringify(err));
    }
  }

  private unsubscribeLyricEvent(): void {
    const sub: commonEventManager.CommonEventSubscriber | null = this.subscriber;
    this.subscriber = null;
    if (sub === null) {
      return;
    }
    try {
      commonEventManager.unsubscribe(sub);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'unsubscribe failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 标题 + 歌手 + 右侧播放状态胶囊 */
  @Builder
  private HeaderBlock() {
    Row({ space: 12 }) {
      Column({ space: 6 }) {
        Text(this.title)
          .fontSize(DesignTokens.fontBanner())
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(this.artist)
          .fontSize(DesignTokens.fontTitle())
          .fontColor(onMediaTextTertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 6 }) {
        Circle()
          .width(6)
          .height(6)
          .fill(this.isPlaying ? liveViewAccent : onMediaTextFaint)
        Text(this.isPlaying ? this.playingLabel : this.pausedLabel)
          .fontSize(DesignTokens.fontCallout())
          .fontColor(onMediaTextPrimary)
          .maxLines(1)
      }
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .borderRadius(12)
      .backgroundColor(onMediaFillWeak)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /** 当前句（无歌词回退文案）+ 可选下一句，整体居中 */
  @Builder
  private LyricBlock() {
    Column({ space: 16 }) {
      Text(this.curLine.length > 0 ? this.curLine : this.noLyricLabel)
        .fontSize(DesignTokens.fontHero())
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('100%')
      if (this.nextLine.length > 0) {
        Text(this.nextLine)
          .fontSize(DesignTokens.fontLarge())
          .fontColor(onMediaTextFaint)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width('100%')
      }
    }
    .width('100%')
  }

  build() {
    Column() {
      this.HeaderBlock()
      Blank()
      this.LyricBlock()
      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 32, right: 32, top: 48, bottom: 48 })
    .backgroundColor(lockScreenScrim)
  }
}
