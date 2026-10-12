/**
 * 设置 → 备份与恢复 → WebDAV 设置面板
 *
 * 形态与 InputSheet 一致：底部面板（bindSheet）+ 共享标题行（左标题 + 右上角 ×），
 * 高度按内容自适应。**不要**自己画「居中卡片 + 全屏遮罩」——挂在设置页的 Scroll 里
 * 会被裁剪，观感也和其它面板两样（这条踩过）。
 *
 * 输入草稿由面板持有，页面只给初值、收回「保存」的新值；
 * 校验在页面的保存回调里做（格式错误时面板保持打开并提示，不静默关闭）。
 * 「清除配置」是面板里的次要危险动作，收在标题行右侧。
 * 地址与账号存进设置存储，口令走系统资产存储（service/CredentialStore），都不进备份数据。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { t } from '../../../service/LocalizationService';
import { BottomSheet, dismissSheet } from '../../../components/ui/BottomSheet';
import { requestFocusSafe } from '../../../utils/FocusTools';
import { SheetHeader } from '../../../components/ui/SheetHeader';

/** 地址输入框的焦点键 */
const WEBDAV_URL_KEY: string = 'webdavUrl';

@Component
export struct WebDavSheet {
  @StorageProp('theme') theme: string = 'light';
  /** 由页面控制显隐（关闭时页面会连同组件一起卸载） */
  @Link visible: boolean;
  /** 初值：当前已保存的配置 */
  @Prop url: string = '';
  @Prop user: string = '';
  @Prop password: string = '';
  /** 已配置时显示「清除配置」 */
  @Prop configured: boolean = false;
  /** 取消（点遮罩或右上角 ×） */
  onCancel?: () => void;
  /** 保存（三个字段的新值，是否落库由页面决定） */
  onSave?: (url: string, user: string, password: string) => void;
  /** 清除已保存的配置 */
  onClear?: () => void;

  @State draftUrl: string = '';
  @State draftUser: string = '';
  @State draftPassword: string = '';

  aboutToAppear(): void {
    this.draftUrl = this.url;
    this.draftUser = this.user;
    this.draftPassword = this.password;
  }

  private cancel(): void {
    this.visible = dismissSheet(this.onCancel);
  }

  build() {
    BottomSheet({
      visible: $visible,
      // 标题自绘（左标题 + 右上角关闭），不用 BottomSheet 的居中标题栏
      title: '',
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
    Column({ space: 12 }) {
      SheetHeader({
        title: t('webdav_sheet_title'),
        // 已配置时才有「清除」：没配过就没有可清的东西
        trailing: (): void => {
          this.ClearAction();
        },
        onClose: (): void => {
          this.cancel();
        },
      })

      this.Fields()
      this.Actions()
    }
    .width('100%')
  }

  /** 标题行右侧的次要危险动作（未配置时不渲染，保持标题行的对称留白） */
  @Builder
  ClearAction() {
    if (this.configured) {
      Text(t('webdav_clear'))
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(DesignTokens.danger())
        .maxLines(1)
        .padding({ left: 8, right: 8 })
        .onClick(() => {
          this.visible = dismissSheet();
          if (this.onClear) {
            this.onClear();
          }
        })
    }
  }

  @Builder
  Fields() {
    WebDavField({
      label: t('webdav_url'),
      value: this.draftUrl,
      placeholder: t('webdav_url_placeholder'),
      focusKey: WEBDAV_URL_KEY,
      onValueChange: (text: string): void => {
        this.draftUrl = text;
      },
    })
    WebDavField({
      label: t('webdav_user'),
      value: this.draftUser,
      onValueChange: (text: string): void => {
        this.draftUser = text;
      },
    })
    WebDavField({
      label: t('webdav_password'),
      value: this.draftPassword,
      isPassword: true,
      onValueChange: (text: string): void => {
        this.draftPassword = text;
      },
    })
  }

  /** 保存（取消收进标题行右上角的 ×） */
  @Builder
  Actions() {
    Row() {
      Button(t('confirm'))
        .type(ButtonType.Capsule)
        .layoutWeight(1)
        .height(DesignTokens.touchTarget())
        .fontSize(DesignTokens.fontTitle())
        .fontColor(DesignTokens.onAccent())
        .backgroundColor(DesignTokens.accent())
        .onClick(() => {
          if (this.onSave) {
            this.onSave(this.draftUrl.trim(), this.draftUser.trim(), this.draftPassword);
          }
        })
    }
    .width('100%')
    .margin({ top: 4 })
  }
}

/**
 * 单行输入（标题 + 输入框）。
 *
 * 独立成组件而不是 @Builder：value 会随输入变化，@Builder 参数在本工程里出现过
 * 「状态变了输入框不刷新」的问题，@Prop 才可靠。
 */
@Component
struct WebDavField {
  @StorageProp('theme') theme: string = 'light';
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop placeholder: string = '';
  @Prop isPassword: boolean = false;
  /** 非空时面板出现即聚焦该输入框 */
  @Prop focusKey: string = '';
  onValueChange?: (text: string) => void;

  build() {
    Column() {
      Text(this.label)
        .fontSize(DesignTokens.fontCaption())
        .fontColor(DesignTokens.labelTertiary(this.theme))
        .width('100%')
        .textAlign(TextAlign.Start)
      TextInput({ text: this.value, placeholder: this.placeholder })
        .id(this.focusKey)
        .type(this.isPassword ? InputType.Password : InputType.Normal)
        .onAppear(() => {
          if (this.focusKey.length > 0) {
            requestFocusSafe(this.getUIContext(), this.focusKey);
          }
        })
        .width('100%')
        .height(DesignTokens.touchTarget())
        .fontSize(DesignTokens.fontBody())
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .placeholderColor(DesignTokens.labelTertiary(this.theme))
        .backgroundColor(DesignTokens.mutedFill(this.theme))
        .borderRadius(12)
        .padding({ left: 14, right: 14 })
        .margin({ top: 6 })
        .onChange((text: string) => {
          if (this.onValueChange) {
            this.onValueChange(text);
          }
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
