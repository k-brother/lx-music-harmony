/**
 * 本地音乐 - 编辑元数据弹窗
 *
 * 从 LocalMusicPage 的 @Builder 抽成组件（原先 120 行内联在页面里）：
 * 输入草稿由面板自己持有，页面只给初值、收回「保存」时的新值，
 * 因此页面不必再为三个输入框各维护一份 @State。
 *
 * 形态与 InputSheet 一致：底部面板（bindSheet）+ 共享标题行（左标题 + 右上角 ×），
 * 高度按内容自适应。**不要**自己画「居中卡片 + 全屏遮罩」——挂在页面里会被容器裁剪，
 * 观感也和其它面板两样（这条踩过）。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { BottomSheet, dismissSheet } from '../../components/ui/BottomSheet';
import { requestFocusSafe } from '../../utils/FocusTools';
import { SheetHeader } from '../../components/ui/SheetHeader';

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
        title: t('edit_metadata'),
        onClose: (): void => {
          this.cancel();
        },
      })

      this.Fields()
      this.Actions()
    }
    .width('100%')
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
            this.onSave(this.draftName, this.draftSinger, this.draftAlbum);
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
        .id(this.focusKey)
        .onAppear(() => {
          if (this.focusKey.length > 0) {
            requestFocusSafe(this.getUIContext(), this.focusKey);
          }
        })
        .width('100%')
        .height(DesignTokens.touchTarget())
        .fontSize(DesignTokens.fontBody())
        .fontColor(DesignTokens.labelPrimary(this.theme))
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
