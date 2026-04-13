/**
 * 筛选标签组件 - 用于排序/标签筛选
 */

@Component
export struct FilterChip {
  @StorageProp('theme') theme: string = 'light';
  @Prop label: string = '';
  @Prop isSelected: boolean = false;
  @Prop fontSize: number = 12;

  private onClick: () => void = () => {};

  setOnClickListener(callback: () => void): void {
    this.onClick = callback;
  }

  build() {
    Text(this.label)
      .fontSize(this.fontSize)
      .padding({ left: 14, right: 14, top: 8, bottom: 8 })
      .backgroundColor(this.isSelected ? '#E63946' : (this.theme === 'dark' ? '#2C2C2C' : '#F0F0F0'))
      .fontColor(this.isSelected ? '#FFFFFF' : (this.theme === 'dark' ? '#CCCCCC' : '#666666'))
      .fontWeight(this.isSelected ? FontWeight.Bold : FontWeight.Normal)
      .borderRadius(18)
      .onClick(() => {
        this.onClick();
      })
  }
}
