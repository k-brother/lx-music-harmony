/**
 * 搜索结果列表（单曲 / 歌单）
 *
 * 单曲行统一用 `ListRow`（序号 + 标题 + 副标题 + 右侧音源徽章），
 * 歌单行用「封面 + 名称 + 作者/播放量 + 箭头」的卡片式行；
 * 空态统一 `StateView`。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { t, sourceLabel } from '../../../service/LocalizationService';
import { ListRow } from '../../../components/ui/ListRow';
import { StateView } from '../../../components/ui/StateView';

/** 单曲搜索结果行 */
export interface SearchMusicRow {
  id: string;
  name: string;
  singer: string;
  album: string;
  source: string;
}

/** 歌单搜索结果行 */
export interface SearchSonglistRow {
  id: string;
  source: string;
  name: string;
  author: string;
  pic: string;
  playCount: number;
}

@Component
export struct SearchMusicResultList {
  @StorageProp('theme') theme: string = 'light';
  @Prop results: SearchMusicRow[] = [];
  onPlay?: (index: number) => void;

  build() {
    if (this.results.length === 0) {
      StateView({ state: 'empty', iconRes: $r('sys.symbol.magnifyingglass'), message: t('search_no_result') })
        .width('100%')
        .layoutWeight(1)
    } else {
      List() {
        ForEach(this.results, (item: SearchMusicRow, index: number) => {
          ListItem() {
            ListRow({
              index: index + 1,
              title: item.name,
              subtitle: item.album.length > 0 ? `${item.singer} · ${item.album}` : item.singer,
              divider: index < this.results.length - 1,
              onTap: (): void => {
                if (this.onPlay) {
                  this.onPlay(index);
                }
              },
              trailing: (): void => {
                this.SourceBadge(item.source);
              },
            })
          }
          .padding({ left: DesignTokens.spaceGutter() - 8, right: DesignTokens.spaceGutter() })
        }, (item: SearchMusicRow, index: number) => `${item.source}_${item.id}_${index}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
  }

  /** 音源徽章（别名/原名随设置） */
  @Builder
  SourceBadge(source: string) {
    Text(sourceLabel(source))
      .fontSize(DesignTokens.fontMicro())
      .fontWeight(FontWeight.Medium)
      .fontColor(DesignTokens.accent())
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .backgroundColor(DesignTokens.accentSoft(this.theme))
      .borderRadius(DesignTokens.radiusSearch())
  }
}

@Component
export struct SearchSonglistResultList {
  @StorageProp('theme') theme: string = 'light';
  @Prop results: SearchSonglistRow[] = [];
  onOpen?: (index: number) => void;

  /** 播放量：亿/万分级（与首页其它位置口径一致） */
  private formatPlayCount(count: number): string {
    if (count >= 100000000) {
      return `${(count / 100000000).toFixed(1)}${t('billion_unit')}`;
    }
    if (count >= 10000) {
      return `${(count / 10000).toFixed(1)}${t('ten_thousand_unit')}`;
    }
    return count.toString();
  }

  build() {
    if (this.results.length === 0) {
      StateView({ state: 'empty', iconRes: $r('sys.symbol.magnifyingglass'), message: t('search_no_result') })
        .width('100%')
        .layoutWeight(1)
    } else {
      List() {
        ForEach(this.results, (item: SearchSonglistRow, index: number) => {
          ListItem() {
            Row() {
              if (item.pic.length > 0) {
                Image(item.pic)
                  .width(56)
                  .height(56)
                  .borderRadius(DesignTokens.radiusCover())
                  .objectFit(ImageFit.Cover)
                  .backgroundColor(DesignTokens.mutedFill(this.theme))
              } else {
                Column() {
                  Image($r('sys.symbol.music_note_list'))
                    .width(22)
                    .height(22)
                    .fillColor(DesignTokens.labelTertiary(this.theme))
                }
                .width(56)
                .height(56)
                .borderRadius(DesignTokens.radiusCover())
                .backgroundColor(DesignTokens.mutedFill(this.theme))
                .justifyContent(FlexAlign.Center)
              }

              Column({ space: 4 }) {
                Text(item.name)
                  .fontSize(15)
                  .fontColor(DesignTokens.labelPrimary(this.theme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                Text(item.playCount > 0
                  ? `${item.author} · ${this.formatPlayCount(item.playCount)}`
                  : item.author)
                  .fontSize(DesignTokens.fontCaption())
                  .fontColor(DesignTokens.labelTertiary(this.theme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .margin({ left: 12 })

              Image($r('sys.symbol.chevron_right'))
                .width(14)
                .height(14)
                .fillColor(DesignTokens.labelTertiary(this.theme))
            }
            .width('100%')
            .padding({ left: DesignTokens.spaceGutter(), right: DesignTokens.spaceGutter(), top: 10, bottom: 10 })
            .onClick(() => {
              if (this.onOpen) {
                this.onOpen(index);
              }
            })
          }
        }, (item: SearchSonglistRow, index: number) => `${item.source}_${item.id}_${index}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
  }
}
