/**
 * 分段控件（Segment Control）
 *
 * 之前「轨道式分段」在歌单排序、运行日志筛选、播放页封面/歌词切换里各写了一遍，
 * 下载页的等宽胶囊筛选又是第四套，选中态/圆角/间距彼此不一致。这里统一成一个组件：
 *  - track：iOS 式轨道 + 浮起滑块（表头切换、筛选用），选中项用 labelPrimary 强调；
 *  - chip：等宽胶囊（下载页状态筛选），选中项用 accentSoft 底 + accent 文字。
 *
 * 调用方只关心「选项 + 当前值 + 回调」，不再关心选中态怎么画。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { isConfirmKey } from '../../utils/KeyboardTools';

export interface SegmentOption {
  id: string;
  label: string;
}

@Component
export struct SegmentedBar {
  @StorageProp('theme') theme: string = 'light';
  @Prop options: SegmentOption[] = [];
  @Prop activeId: string = '';
  /** track（默认）/ chip */
  @Prop variant: string = 'track';
  /** 等分宽度：track 变体下用于「封面/歌词」这类两段式切换 */
  @Prop equalWidth: boolean = false;
  /** 是否撑满父容器（放在行内与其它元素并排时置 false） */
  @Prop fillWidth: boolean = true;
  @Prop fontSize: number = 13;
  onSelect?: (id: string) => void;

  @Styles
  pressed() {
    .opacity(DesignTokens.pressedOpacity())
  }

  private isChip(): boolean {
    return this.variant === 'chip';
  }

  private select(id: string): void {
    if (id === this.activeId) {
      return;
    }
    if (this.onSelect) {
      this.onSelect(id);
    }
  }

  build() {
    Row({ space: this.isChip() ? 8 : 2 }) {
      ForEach(this.options, (option: SegmentOption) => {
        Text(option.label)
          .fontSize(this.fontSize)
          .fontWeight(this.activeId === option.id ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(this.isChip()
            ? (this.activeId === option.id ? DesignTokens.accent() : DesignTokens.labelSecondary(this.theme))
            : (this.activeId === option.id ? DesignTokens.labelPrimary(this.theme) : DesignTokens.labelSecondary(this.theme)))
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .layoutWeight(this.equalWidth || this.isChip() ? 1 : 0)
          .constraintSize({ minHeight: this.isChip() ? 36 : 0 })
          .padding({ left: this.isChip() ? 0 : 14, right: this.isChip() ? 0 : 14, top: 5, bottom: 5 })
          .backgroundColor(this.isChip()
            ? (this.activeId === option.id ? DesignTokens.accentSoft(this.theme) : Color.Transparent)
            : (this.activeId === option.id ? DesignTokens.segmentedThumb(this.theme) : Color.Transparent))
          .borderRadius(this.isChip() ? 10 : DesignTokens.radiusSearch())
          .border(this.isChip()
            ? {
                width: 0.5,
                color: this.activeId === option.id ? DesignTokens.accentSoft(this.theme) : DesignTokens.cardBorder(this.theme),
              }
            : { width: 0 })
          .stateStyles({ pressed: this.pressed })
          // 2in1：分段/胶囊选项要能用键盘切换（PC 上没有触屏按压缩放）
          .focusable(true)
          .onKeyEvent((event: KeyEvent): void => {
            if (isConfirmKey(event)) {
              this.select(option.id);
            }
          })
          .onClick(() => {
            this.select(option.id);
          })
      }, (option: SegmentOption) => option.id)
    }
    .width(this.fillWidth ? '100%' : 'auto')
    .padding(this.isChip() ? 0 : 2)
    .backgroundColor(this.isChip() ? Color.Transparent : DesignTokens.segmentedTrack(this.theme))
    .borderRadius(DesignTokens.radiusSearch())
    .alignItems(VerticalAlign.Center)
  }
}
