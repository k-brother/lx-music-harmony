import { t } from '../../service/LocalizationService';
/**
 * 音乐源标签组件
 */

@Component
export struct MusicSourceBadge {
  @Prop source: string;
  @Prop fontSize: number = 11;

  private getSourceName(sourceId: string): string {
    if (sourceId === 'kw') return t('source_kw_short');
    if (sourceId === 'tx') return 'QQ';
    if (sourceId === 'wy') return t('source_wy_short');
    if (sourceId === 'kg') return t('source_kg_short');
    if (sourceId === 'mg') return t('source_mg_short');
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
