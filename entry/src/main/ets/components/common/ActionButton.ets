/**
 * 操作按钮组件 - 统一样式的图标按钮
 */

@Component
export struct ActionButton {
  @StorageProp('theme') theme: string = 'light';
  @Prop icon: Resource = $r('sys.symbol.ellipsis_circle');
  @Prop label: string = '';
  @Prop iconColor: string = '';
  @Prop size: number = 24;
  @Prop buttonSize: number = 48;
  @Prop activeColor: string = '#E63946';

  private isActive: boolean = false;
  private onClick: () => void = () => {};

  setActive(active: boolean): void {
    this.isActive = active;
  }

  setOnClickListener(callback: () => void): void {
    this.onClick = callback;
  }

  build() {
    Column() {
      Image(this.icon)
        .width(this.size)
        .height(this.size)
        .fillColor(this.getIconColor())
        .onClick(() => {
          this.onClick();
        })

      if (this.label) {
        Text(this.label)
          .fontSize(10)
          .fontColor(this.getLabelColor())
          .margin({ top: 4 })
      }
    }
    .width(this.buttonSize)
    .height(this.buttonSize + (this.label ? 20 : 0))
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private getIconColor(): string {
    if (this.iconColor) return this.iconColor;
    if (this.isActive) return this.activeColor;
    return this.theme === 'dark' ? '#FFFFFF' : '#333333';
  }

  private getLabelColor(): string {
    if (this.isActive) return this.activeColor;
    return this.theme === 'dark' ? '#AAAAAA' : '#666666';
  }
}

/**
 * 主要操作按钮 - 如播放按钮
 */
@Component
export struct PrimaryActionButton {
  @Prop icon: Resource = $r('sys.symbol.play');
  @Prop size: number = 64;
  @Prop color: string = '#E63946';
  @Prop backgroundColor: string = 'transparent';

  private onClick: () => void = () => {};

  setOnClickListener(callback: () => void): void {
    this.onClick = callback;
  }

  build() {
    Image(this.icon)
      .width(this.size)
      .height(this.size)
      .fillColor(this.color)
      .backgroundColor(this.backgroundColor)
      .borderRadius(this.size / 2)
      .onClick(() => {
        this.onClick();
      })
  }
}
