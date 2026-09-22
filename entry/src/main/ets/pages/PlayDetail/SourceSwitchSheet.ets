/**
 * 手动换源面板
 *
 * 列出同一首歌在其它音源的匹配结果（候选由 core/ResolvePlayback 提供），
 * 选中后由页面切源重新取链播放。
 */
import { DesignTokens } from '../../theme/DesignTokens';
import { t, sourceLabel } from '../../service/LocalizationService';
import { BottomSheet } from '../../components/ui/BottomSheet';
import type { MusicInfo } from '../../types/MusicTypes';

@Component
export struct SourceSwitchSheet {
  @StorageProp('theme') theme: string = 'light';
  @Link visible: boolean;
  @Prop candidates: MusicInfo[] = [];
  @Prop loading: boolean = false;
  onPick?: (target: MusicInfo) => void;

  @Builder
  Row(candidate: MusicInfo) {
    Row() {
      Text(sourceLabel(candidate.source ?? ''))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.accent())
        .width(76)

      Column({ space: 2 }) {
        Text(candidate.name ?? '')
          .fontSize(14)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(candidate.singer ?? '')
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelTertiary(this.theme))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('sys.symbol.chevron_right'))
        .width(14)
        .height(14)
        .fillColor(DesignTokens.labelTertiary(this.theme))
    }
    .width('100%')
    .height(DesignTokens.rowHeightTwoLine())
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.visible = false;
      if (this.onPick) {
        this.onPick(candidate);
      }
    })
  }

  @Builder
  Content() {
    if (this.loading) {
      Column() {
        LoadingProgress()
          .width(28)
          .height(28)
          .color(DesignTokens.accent())
        Text(t('loading'))
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelSecondary(this.theme))
          .margin({ top: 10 })
      }
      .width('100%')
      .padding({ top: 24, bottom: 24 })
    } else if (this.candidates.length === 0) {
      Text(t('switch_source_empty'))
        .fontSize(14)
        .fontColor(DesignTokens.labelSecondary(this.theme))
        .padding({ top: 20, bottom: 20 })
    } else {
      List() {
        ForEach(this.candidates, (candidate: MusicInfo) => {
          ListItem() {
            this.Row(candidate)
          }
        }, (candidate: MusicInfo) => `${candidate.source}_${candidate.songmid ?? candidate.id}`)
      }
      .width('100%')
      .constraintSize({ maxHeight: 360 })
      .scrollBar(BarState.Off)
    }
  }

  build() {
    BottomSheet({
      visible: $visible,
      title: t('switch_source'),
      maxHeightPercent: '70%',
      content: (): void => {
        this.Content();
      },
    })
  }
}
