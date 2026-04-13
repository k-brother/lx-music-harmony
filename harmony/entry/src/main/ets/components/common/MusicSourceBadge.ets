/**
 * 音乐源标签组件
 */

@Component
export struct MusicSourceBadge {
  @Prop source: string;
  @Prop fontSize: number = 11;

  private getSourceName(sourceId: string): string {
    if (sourceId === 'kw') return '酷我';
    if (sourceId === 'tx') return 'QQ';
    if (sourceId === 'wy') return '网易';
    if (sourceId === 'kg') return '酷狗';
    if (sourceId === 'mg') return '咪咕';
    return sourceId;
  }

  build() {
    Text(this.getSourceName(this.source))
      .fontSize(this.fontSize)
      .fontColor('#E63946')
      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      .backgroundColor('rgba(230, 57, 70, 0.1)')
      .borderRadius(4)
  }
}
