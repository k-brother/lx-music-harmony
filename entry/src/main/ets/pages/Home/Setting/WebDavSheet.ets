/**
 * 设置 → 备份与恢复 → WebDAV 设置面板
 *
 * 结构对齐 EditMetadataSheet：输入草稿由面板持有，页面只给初值、收回「保存」的新值。
 * 校验在页面的保存回调里做（格式错误时面板保持打开并提示，不静默关闭）。
 * 密码用密码输入框；配置明文存本机 preferences（与备份口令同一处，不进备份数据）。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { t } from '../../../service/LocalizationService';
import { dismissSheet } from '../../../components/ui/BottomSheet';
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
    Stack() {
      // 遮罩：点空白处取消
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(DesignTokens.maskColor())
        .onClick(() => {
          this.cancel();
        })

      Column({ space: 10 }) {
        SheetHeader({
          title: t('webdav_sheet_title'),
          onClose: (): void => {
            this.cancel();
          },
        })

        this.Fields()

        if (this.configured) {
          Text(t('webdav_clear'))
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.danger())
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding(4)
            .onClick(() => {
              this.visible = dismissSheet();
              if (this.onClear) {
                this.onClear();
              }
            })
        }

        this.Actions()
      }
      .width('86%')
      .padding(18)
      .backgroundColor(DesignTokens.card(this.theme))
      .borderRadius(20)
      .border({ width: 0.33, color: DesignTokens.cardBorder(this.theme) })
      // 吃掉点击，避免点面板本体也触发遮罩的取消
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
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
    Row({ space: 10 }) {
      Button(t('confirm'))
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(DesignTokens.onAccent())
        .backgroundColor(DesignTokens.accent())
        .borderRadius(18)
        .layoutWeight(1)
        .onClick(() => {
          if (this.onSave) {
            this.onSave(this.draftUrl.trim(), this.draftUser.trim(), this.draftPassword);
          }
        })
    }
    .width('100%')
    .margin({ top: 6 })
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
        .key(this.focusKey)
        .type(this.isPassword ? InputType.Password : InputType.Normal)
        .onAppear(() => {
          if (this.focusKey.length > 0) {
            requestFocusSafe(this.getUIContext(), this.focusKey);
          }
        })
        .width('100%')
        .height(40)
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .backgroundColor(DesignTokens.mutedFill(this.theme))
        .borderRadius(10)
        .padding({ left: 12, right: 12 })
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
