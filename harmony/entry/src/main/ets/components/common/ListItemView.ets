/**
 * 通用列表项组件
 */

import { MusicSourceBadge } from './MusicSourceBadge';

@Component
export struct ListItemView {
  @StorageProp('theme') theme: string = 'light';

  // 左侧图标/封面
  @Prop leftImage: string = '';
  @Prop leftIcon: Resource = $r('sys.symbol.music_note');
  @Prop leftImageSize: number = 44;
  @Prop leftIconColor: string = '#999999';
  @Prop leftBackgroundColor: string = '';

  // 主标题
  @Prop title: string = '';
  @Prop titleFontSize: number = 15;
  @Prop titleColor: string = '';

  // 副标题
  @Prop subtitle: string = '';
  @Prop subtitleFontSize: number = 12;
  @Prop subtitleColor: string = '#999999';

  // 右侧内容
  @Prop rightText: string = '';
  @Prop rightTextColor: string = '#999999';
  @Prop showSourceBadge: boolean = false;
  @Prop source: string = '';
  @Prop showArrow: boolean = true;
  @Prop isPlaying: boolean = false;

  // 点击回调
  private onItemClick: () => void = () => {};
  private onRightClick: () => void = () => {};

  setOnItemClickListener(callback: () => void): void {
    this.onItemClick = callback;
  }

  setOnRightClickListener(callback: () => void): void {
    this.onRightClick = callback;
  }

  build() {
    Row() {
      // 左侧图标/封面
      this.LeftContent()

      // 中间内容
      this.CenterContent()

      // 右侧内容
      this.RightContent()
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
    .onClick(() => {
      this.onItemClick();
    })
  }

  @Builder
  LeftContent() {
    Stack() {
      if (this.leftImage) {
        Image(this.leftImage)
          .width(this.leftImageSize)
          .height(this.leftImageSize)
          .borderRadius(6)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          Image(this.leftIcon)
            .width(this.leftImageSize * 0.5)
            .height(this.leftImageSize * 0.5)
            .fillColor(this.leftIconColor)
        }
        .width(this.leftImageSize)
        .height(this.leftImageSize)
        .backgroundColor(this.leftBackgroundColor || (this.theme === 'dark' ? '#2C2C2C' : '#E8E8E8'))
        .borderRadius(6)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width(this.leftImageSize)
    .height(this.leftImageSize)
  }

  @Builder
  CenterContent() {
    Column() {
      Row() {
        if (this.isPlaying) {
          Image($r('sys.symbol.play'))
            .width(14)
            .height(14)
            .fillColor('#E63946')
            .margin({ right: 6 })
        }
        Text(this.title)
          .fontSize(this.titleFontSize)
          .fontColor(this.getTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }

      if (this.subtitle) {
        Text(this.subtitle)
          .fontSize(this.subtitleFontSize)
          .fontColor(this.subtitleColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
    .padding({ left: 12 })
  }

  @Builder
  RightContent() {
    Row() {
      if (this.rightText) {
        Text(this.rightText)
          .fontSize(12)
          .fontColor(this.rightTextColor)
          .margin({ right: 8 })
      }

      if (this.showSourceBadge && this.source) {
        MusicSourceBadge({ source: this.source, fontSize: 10 })
          .margin({ right: 8 })
      }

      if (this.showArrow) {
        Image($r('sys.symbol.chevron_right'))
          .width(16)
          .height(16)
          .fillColor(this.theme === 'dark' ? '#666666' : '#CCCCCC')
      }
    }
    .alignItems(VerticalAlign.Center)
  }

  private getTitleColor(): string {
    if (this.titleColor) return this.titleColor;
    if (this.isPlaying) return '#E63946';
    return this.theme === 'dark' ? '#FFFFFF' : '#333333';
  }
}
