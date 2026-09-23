/**
 * 本地音乐 - 编辑元数据弹窗
 *
 * 从 LocalMusicPage 的 @Builder 抽成组件（原先 120 行内联在页面里）：
 * 输入草稿由面板自己持有，页面只给初值、收回「保存」时的新值，
 * 因此页面不必再为三个输入框各维护一份 @State。
 * 遮罩用 DesignTokens.maskColor()，与其他浮层同一套观感。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { dismissSheet } from '../../components/ui/BottomSheet';
import { requestFocusSafe } from '../../utils/FocusTools';

/** 第一个输入框的焦点键 */
const METADATA_NAME_KEY: string = 'editMetadataName';

@Component
export struct EditMetadataSheet {
  @StorageProp('theme') theme: string = 'light';
  /** 由页面控制显隐（关闭时页面会连同组件一起卸载） */
  @Link visible: boolean;
  /** 初始值：当前曲目的元数据 */
  @Prop name: string = '';
  @Prop singer: string = '';
  @Prop album: string = '';
  /** 取消（点遮罩或取消按钮） */
  onCancel?: () => void;
  /** 保存（返回三个字段的新值，是否落库由页面决定） */
  onSave?: (name: string, singer: string, album: string) => void;

  @State draftName: string = '';
  @State draftSinger: string = '';
  @State draftAlbum: string = '';

  aboutToAppear(): void {
    this.draftName = this.name;
    this.draftSinger = this.singer;
    this.draftAlbum = this.album;
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
        Text(t('edit_metadata'))
          .fontSize(DesignTokens.fontHeadline())
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .width('100%')
          .textAlign(TextAlign.Start)

        this.Fields()
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

  /** 三个可编辑字段（歌名 / 歌手 / 专辑） */
  @Builder
  Fields() {
    MetadataField({
      label: t('metadata_name'),
      value: this.draftName,
      focusKey: METADATA_NAME_KEY,
      onValueChange: (text: string): void => {
        this.draftName = text;
      },
    })
    MetadataField({
      label: t('metadata_singer'),
      value: this.draftSinger,
      onValueChange: (text: string): void => {
        this.draftSinger = text;
      },
    })
    MetadataField({
      label: t('metadata_album'),
      value: this.draftAlbum,
      onValueChange: (text: string): void => {
        this.draftAlbum = text;
      },
    })
  }

  /** 取消 / 保存 */
  @Builder
  Actions() {
    Row({ space: 10 }) {
      Button(t('cancel'))
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(DesignTokens.labelPrimary(this.theme))
        .backgroundColor(DesignTokens.mutedFill(this.theme))
        .borderRadius(18)
        .layoutWeight(1)
        .onClick(() => {
          this.cancel();
        })
      Button(t('confirm'))
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(DesignTokens.onAccent())
        .backgroundColor(DesignTokens.accent())
        .borderRadius(18)
        .layoutWeight(1)
        .onClick(() => {
          if (this.onSave) {
            this.onSave(this.draftName, this.draftSinger, this.draftAlbum);
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
struct MetadataField {
  @StorageProp('theme') theme: string = 'light';
  @Prop label: string = '';
  @Prop value: string = '';
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
      TextInput({ text: this.value })
        .key(this.focusKey)
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
