/**
 * 许可协议弹层（对应安卓版 PactModal）
 *
 * - 首次启动（未同意）时全屏覆盖，必须先同意才能使用；
 * - 「设置 → 关于 → 许可协议」进入时为只读模式，底部只有一个「关闭」；
 * - 未同意时「接受」按钮带 20 秒倒计时（与安卓版一致，避免用户没看就点同意）；
 * - 拒绝则退出应用。
 */
import hilog from '@ohos.hilog';
import { common } from '@kit.AbilityKit';
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { settingsService } from '../../service/SettingsService';
import { getPactNotice, getPactSections, PactSection } from '../../core/legal/PactText';

const DOMAIN = 0x0001;
const TAG = 'PactDialog';
/** 未同意时的强制阅读倒计时（秒） */
const ACCEPT_COUNTDOWN_SECONDS = 20;

@Component
export struct PactDialog {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('language') language: string = 'zh-CN';
  @StorageProp('langVersion') langVersion: number = 0;
  /** 只读模式（从设置进入回看）：隐藏拒绝按钮，且不写设置 */
  @Prop readonlyMode: boolean = false;
  /** 关闭回调（只读模式点关闭时由调用方收起弹层） */
  @Prop @Watch('onVisibleChanged') visible: boolean = true;
  onClose?: () => void;

  @State countdown: number = ACCEPT_COUNTDOWN_SECONDS;
  private timerId: number = -1;

  aboutToAppear(): void {
    if (!this.readonlyMode && !settingsService.get().agreedPact) {
      this.startCountdown();
    } else {
      this.countdown = 0;
    }
  }

  aboutToDisappear(): void {
    this.stopCountdown();
  }

  private onVisibleChanged(): void {
    if (!this.visible) {
      this.stopCountdown();
    }
  }

  private startCountdown(): void {
    if (this.timerId >= 0) {
      return;
    }
    this.timerId = setInterval((): void => {
      if (this.countdown <= 1) {
        this.countdown = 0;
        this.stopCountdown();
        return;
      }
      this.countdown -= 1;
    }, 1000);
  }

  private stopCountdown(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  /** 接受：写入同意标记并关闭（只读模式只关闭） */
  private async accept(): Promise<void> {
    if (this.countdown > 0) {
      return;
    }
    if (!this.readonlyMode) {
      await settingsService.update({ agreedPact: true });
    }
    if (this.onClose) {
      this.onClose();
    }
  }

  /** 拒绝：直接退出应用（与安卓版 exitApp 一致） */
  private reject(): void {
    if (this.readonlyMode) {
      if (this.onClose) {
        this.onClose();
      }
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.terminateSelf().catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'terminateSelf failed: %{public}s', err.message);
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'reject failed: %{public}s', JSON.stringify(err));
    }
  }

  private acceptText(): string {
    if (this.countdown > 0) {
      return `${t('pact_accept')} (${this.countdown})`;
    }
    return this.readonlyMode ? t('close') : t('pact_accept');
  }

  @Builder
  Section(section: PactSection) {
    Column() {
      if (section.title.length > 0) {
        Text(section.title)
          .fontSize(DesignTokens.fontSubhead())
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .width('100%')
          .margin({ top: 14, bottom: 4 })
      }
      ForEach(section.paragraphs, (paragraph: string) => {
        Text(paragraph)
          .fontSize(DesignTokens.fontCallout())
          .lineHeight(21)
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .width('100%')
          .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
          .margin({ bottom: 6 })
      }, (paragraph: string, index: number) => `${section.title}_${index}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Text(t('pact_title'))
        .fontSize(DesignTokens.fontHeading())
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .width('100%')
        .margin({ bottom: 8 })

      Scroll() {
        Column() {
          if (!this.readonlyMode && !settingsService.get().agreedPact) {
            Text(getPactNotice(this.language))
              .fontSize(DesignTokens.fontBody())
              .fontWeight(FontWeight.Medium)
              .fontColor(DesignTokens.accent())
              .width('100%')
              .margin({ bottom: 8 })
          }
          ForEach(getPactSections(this.language), (section: PactSection) => {
            this.Section(section)
          }, (section: PactSection) => section.title)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Off)

      Row({ space: 10 }) {
        if (!this.readonlyMode) {
          Button(t('pact_reject'))
            .layoutWeight(1)
            .height(42)
            .fontSize(DesignTokens.fontBody())
            .fontColor(DesignTokens.labelPrimary(this.theme))
            .backgroundColor(DesignTokens.mutedFill(this.theme))
            .onClick(() => {
              this.reject();
            })
        }
        Button(this.acceptText())
          .layoutWeight(1)
          .height(42)
          .fontSize(DesignTokens.fontBody())
          .fontColor(this.countdown > 0 ? DesignTokens.labelTertiary(this.theme) : '#FFFFFF')
          .backgroundColor(this.countdown > 0 ? DesignTokens.mutedFill(this.theme) : DesignTokens.accent())
          .enabled(this.countdown === 0)
          .onClick(() => {
            void this.accept();
          })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('88%')
    .height('76%')
    .padding(18)
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(20)
    .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
  }
}
