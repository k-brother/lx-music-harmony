/**
 * 输入面板（单行文本）
 *
 * 取代设置页里手写的「居中弹窗 + TextInput + 两个按钮 + 回调透传」。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { BottomSheet, dismissSheet } from './BottomSheet';
import { requestFocusSafe } from '../../utils/FocusTools';

/** 输入框焦点键：面板出现即聚焦，省掉用户多点一次 */
const INPUT_SHEET_KEY: string = 'sheetTextInput';

@Component
export struct InputSheet {
  @StorageProp('theme') theme: string = 'light';
  @Link visible: boolean;
  @Prop title: string = '';
  @Prop placeholder: string = '';
  /** 初始值（面板打开时由调用方写入） */
  @Prop value: string = '';
  /** 键盘类型：普通文本 / 数字（下载并发数等） */
  @Prop numberOnly: boolean = false;
  onSubmit?: (value: string) => void;
  /** 关闭（点遮罩/取消） */
  onCancel?: () => void;

  private cancel(): void {
    this.visible = dismissSheet(this.onCancel);
  }

  @State draft: string = '';

  aboutToAppear() {
    this.draft = this.value;
  }

  build() {
    BottomSheet({
      visible: $visible,
      title: this.title,
      onDismiss: (): void => {
        this.cancel();
      },
      content: (): void => {
        this.Form();
      },
    })
  }

  @Builder
  Form() {
    Column() {
      TextInput({ placeholder: this.placeholder, text: this.draft })
        .type(this.numberOnly ? InputType.Number : InputType.Normal)
        .key(INPUT_SHEET_KEY)
        // 面板打开时自动聚焦并弹键盘（主流输入面板的手感）
        .onAppear(() => {
          requestFocusSafe(this.getUIContext(), INPUT_SHEET_KEY);
        })
        .height(DesignTokens.touchTarget())
        .width('100%')
        .backgroundColor(DesignTokens.mutedFill(this.theme))
        .borderRadius(12)
        .padding({ left: 14, right: 14 })
        .fontSize(DesignTokens.fontTitle())
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .placeholderColor(DesignTokens.labelTertiary(this.theme))
        .onChange((value: string) => {
          this.draft = value;
        })

      Row({ space: 12 }) {
        Button(t('cancel'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(DesignTokens.touchTarget())
          .fontSize(DesignTokens.fontTitle())
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .backgroundColor(DesignTokens.mutedFill(this.theme))
          .onClick(() => {
            this.cancel();
          })
        Button(t('confirm'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .height(DesignTokens.touchTarget())
          .fontSize(DesignTokens.fontTitle())
          .fontColor(DesignTokens.onAccent())
          .backgroundColor(DesignTokens.accent())
          .onClick(() => {
            // 必须先回调再关闭：bindSheet 关闭会触发 onDismiss（按「取消」处理），
            // 反过来会先用空值结束请求，用户输入就被吞掉了。
            if (this.onSubmit) {
              this.onSubmit(this.draft);
            }
            this.visible = false;
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
  }
}
