/**
 * 榜单卡片（封面 / 播放量 / 试听预览 / 展开收起 / 进完整榜单）
 *
 * 从 LeaderboardView 的 @Builder 抽成组件。原实现为了绕开「@Builder 参数不刷新」，
 * 卡片内容全部按 index 读页面状态；这里改为 @Prop 传显示数据 + 回调：
 * 页面按 index 读状态并映射成 props（@Prop 会随父组件重渲染更新），两边职责更清楚。
 */
import { DesignTokens } from '../../../theme/DesignTokens';
import { composeRowDurationText, composeRowSubtitle } from '../../../core/list/RowTexts';
import { CoverPalette } from '../../../theme/CoverPalette';
import { t, tf, playCountUnits } from '../../../service/LocalizationService';
import { formatPlayCount } from '../../../utils/FormatTools';
import type { BoardMusicItem } from '../../../store/leaderboard/LeaderboardStoreState';

/** 卡片内统一的行内边距：封面、序号、底部「展开试听」都从这里开始 */
const PREVIEW_ROW_PADDING: number = 12;
/** 预览行的序号列宽 */
const PREVIEW_RANK_WIDTH: number = 32;
/** 歌名与分割线的起点 = 行内边距 + 序号列宽 */
const PREVIEW_TITLE_INSET: number = PREVIEW_ROW_PADDING + PREVIEW_RANK_WIDTH;

@Component
export struct ChartCard {
  @StorageProp('theme') theme: string = 'light';
  @Prop cardId: string = '';
  @Prop title: string = '';
  /** 播放量；< 0 表示该榜单没有播放量数据 */
  @Prop playCount: number = -1;
  @Prop coverUrl: string = '';
  /** 无榜单图时的渐变占位色（由页面按榜单 id 生成，保证各榜可区分） */
  @Prop placeholderColors: string[] = CoverPalette.defaultPair();
  @Prop songs: BoardMusicItem[] = [];
  /** idle / loading / ready / err */
  @Prop loadState: string = 'idle';
  @Prop expanded: boolean = false;
  /** 设置 → 列表（与其它列表页同一套开关） */
  @StorageProp('showListAlbum') showListAlbum: boolean = true;
  @StorageProp('showListSource') showListSource: boolean = true;
  @StorageProp('showListDuration') showListDuration: boolean = true;
  onToggleExpand?: () => void;
  onOpenBoard?: () => void;
  onPlaySong?: (song: BoardMusicItem) => void;
  onRetry?: () => void;

  /** 前三名给强调色/奖牌色，其余用次级色 */
  private rankColor(rank: number): string {
    if (rank === 1) {
      return DesignTokens.accent();
    }
    if (rank === 2) {
      return DesignTokens.warning();
    }
    if (rank === 3) {
      return DesignTokens.info();
    }
    return DesignTokens.labelTertiary(this.theme);
  }

  /** 副标题：与歌单/榜单详情同一出口（歌手 · 专辑 · 音源，受「设置 → 列表」控制） */
  private subtitleOf(song: BoardMusicItem): string {
    return composeRowSubtitle(song.singer, song.album, song.source, this.showListAlbum, this.showListSource);
  }

  /** 行尾时长文本（关闭「显示时长」返回空串） */
  private durationOf(song: BoardMusicItem): string {
    return composeRowDurationText(song.duration, this.showListDuration);
  }

  /** 按压反馈：可点的行/卡片变淡（与列表页同一套） */
  @Styles
  pressed() {
    .opacity(DesignTokens.pressedOpacity())
  }

  private playCountText(): string {
    const count: number = this.playCount < 0 ? 0 : this.playCount;
    return tf('count_plays', [formatPlayCount(count, playCountUnits())]);
  }

  private placeholderGradientOptions(): LinearGradientOptions {
    const colors: string[] = this.placeholderColors.length >= 2
      ? this.placeholderColors
      : CoverPalette.defaultPair();
    return { angle: 135, colors: [[colors[0], 0.0], [colors[1], 1.0]] };
  }

  /** 封面：有图用图，没有则用按榜单取色的渐变块 + 榜单图标（不再是「第一首歌的封面」） */
  @Builder
  Cover() {
    Stack() {
      if (this.coverUrl.length > 0) {
        Image(this.coverUrl)
          .width(72)
          .height(72)
          .borderRadius(14)
          .objectFit(ImageFit.Cover)
      } else {
        Column() {
          SymbolGlyph($r('sys.symbol.list_number'))
            .fontSize(DesignTokens.fontCoverIcon())
            .fontColor([DesignTokens.onAccent()])
        }
        .width(72)
        .height(72)
        .borderRadius(14)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .linearGradient(this.placeholderGradientOptions())
      }
    }
    .width(72)
    .height(72)
    .accessibilityText(t('a11y_open_board'))
    .onClick(() => {
      if (this.onOpenBoard) {
        this.onOpenBoard();
      }
    })
  }

  /** 骨架行：预览加载中 */
  @Builder
  LoadingRows() {
    Column({ space: 8 }) {
      ForEach([0, 1, 2], (_: number, si: number) => {
        Row() {
          Column()
            .width(28)
            .height(12)
            .borderRadius(6)
            .backgroundColor(DesignTokens.mutedFill(this.theme))
          Column()
            .layoutWeight(1)
            .height(12)
            .borderRadius(6)
            .backgroundColor(DesignTokens.mutedFill(this.theme))
            .margin({ left: 12, right: 24 })
        }
        .width('100%')
        .padding({ left: PREVIEW_ROW_PADDING, right: 12, top: 12, bottom: 12 })
        .backgroundColor(DesignTokens.mutedFill(this.theme))
        .borderRadius(10)
      })
    }
    .width('100%')
    .padding({ left: PREVIEW_ROW_PADDING, right: PREVIEW_ROW_PADDING, bottom: 12 })
  }

  @Builder
  ErrorRow() {
    Row() {
      Text(t('load_failed'))
        .fontSize(DesignTokens.fontCallout())
        .fontColor(DesignTokens.labelTertiary(this.theme))
        .layoutWeight(1)
      Text(t('retry'))
        .fontSize(DesignTokens.fontCallout())
        .fontWeight(FontWeight.Medium)
        .fontColor(DesignTokens.accent())
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .onClick(() => {
          if (this.onRetry) {
            this.onRetry();
          }
        })
    }
    .width('100%')
    .padding({ left: PREVIEW_ROW_PADDING, right: PREVIEW_ROW_PADDING, bottom: 12 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  PreviewList() {
    Column() {
      ForEach(this.songs, (song: BoardMusicItem, si: number) => {
        Column() {
          Row() {
            Text((si + 1).toString())
              .fontSize(DesignTokens.fontBody())
              .fontWeight(FontWeight.Medium)
              .fontColor(this.rankColor(si + 1))
              .width(PREVIEW_RANK_WIDTH)
              .textAlign(TextAlign.Center)
            Column({ space: 3 }) {
              Text(song.name.length > 0 ? song.name : '—')
                .fontSize(DesignTokens.fontSubhead())
                .fontColor(DesignTokens.labelPrimary(this.theme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              // 副标题与歌单详情同一套口径：歌手 · 专辑 · 音源（受「设置 → 列表」控制）
              if (this.subtitleOf(song).length > 0) {
                Text(this.subtitleOf(song))
                  .fontSize(DesignTokens.fontCaption())
                  .fontColor(DesignTokens.labelSecondary(this.theme))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            // 时长：与歌单详情一致（关闭「显示时长」时不占位）
            if (this.durationOf(song).length > 0) {
              Text(this.durationOf(song))
                .fontSize(DesignTokens.fontCaption())
                .fontColor(DesignTokens.labelTertiary(this.theme))
                .margin({ left: 8 })
            }
          }
          .width('100%')
          .padding({ left: PREVIEW_ROW_PADDING, right: 12, top: 12, bottom: 12 })
          .stateStyles({ pressed: this.pressed })
          .onClick(() => {
            if (this.onPlaySong) {
              this.onPlaySong(song);
            }
          })

          if (si < this.songs.length - 1) {
            Divider()
              .strokeWidth(0.5)
              .color(DesignTokens.cardBorder(this.theme))
              .margin({ left: PREVIEW_TITLE_INSET, right: 0 })
          }
        }
        .width('100%')
      }, (song: BoardMusicItem, si: number) => `${this.cardId}_song_${si}_${song.id}`)
    }
    .width('100%')
    .padding({ bottom: 8 })
  }

  build() {
    Column() {
      this.CardHeader()

      this.PreviewContent()

      this.CardFooter()
    }
    .width('100%')
    .backgroundColor(DesignTokens.card(this.theme))
    .borderRadius(DesignTokens.radiusCard())
    .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
    .margin({ top: 12 })
  }

  /**
   * 卡片头部：封面 + 榜单名/播放量 + 展开与进入按钮。
   * 左侧内边距与歌曲行一致 —— 封面左边界与下面列表的**序号**对齐
   * （真机反馈：先是贴着卡片左边缘，改成和歌名对齐后又太靠右，最终与序号对齐）。
   */
  @Builder
  CardHeader() {
    Row() {
      this.Cover()

      Column() {
        Text(this.title.length > 0 ? this.title : t('board_item'))
          .fontSize(DesignTokens.fontHeadline())
          .fontWeight(FontWeight.Medium)
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(22)
        if (this.playCount >= 0) {
          Text(this.playCountText())
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .margin({ top: 8 })
        } else {
          Text(t('leaderboard_official'))
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .margin({ top: 8 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 14 })
      .onClick(() => {
        if (this.onOpenBoard) {
          this.onOpenBoard();
        }
      })

      Row() {
        SymbolGlyph(this.expanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(DesignTokens.fontDisplay())
          .fontColor([DesignTokens.labelSecondary(this.theme)])
          .padding(8)
          .responseRegion(DesignTokens.touchRegion(30))
          // 展开/收起是同一个按钮，朗读文案跟着状态走
          .accessibilityText(this.expanded ? t('a11y_collapse') : t('a11y_expand'))
          .onClick(() => {
            if (this.onToggleExpand) {
              this.onToggleExpand();
            }
          })
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(DesignTokens.fontLarge())
          .fontColor([DesignTokens.accent()])
          .padding({ left: 4, right: 4, top: 8, bottom: 8 })
          .responseRegion(DesignTokens.touchRegion(30))
          .accessibilityText(t('a11y_open_board'))
          .onClick(() => {
            if (this.onOpenBoard) {
              this.onOpenBoard();
            }
          })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: PREVIEW_ROW_PADDING, right: PREVIEW_ROW_PADDING, top: 4, bottom: 12 })
  }

  /** 试听列表区（加载中骨架 / 失败重试 / 空 / 列表） */
  @Builder
  PreviewContent() {
    if (this.loadState === 'loading') {
      this.LoadingRows()
    } else if (this.loadState === 'err') {
      this.ErrorRow()
    } else if (this.songs.length === 0) {
      Text(t('no_data'))
        .fontSize(DesignTokens.fontCallout())
        .fontColor(DesignTokens.labelTertiary(this.theme))
        .padding({ left: PREVIEW_ROW_PADDING, right: PREVIEW_ROW_PADDING, bottom: 12 })
    } else {
      this.PreviewList()
    }
  }

  /** 底部：展开收起 + 查看完整榜单 */
  @Builder
  CardFooter() {
    Row() {
      // 展开/收起：图标 + 文案，带触控热区（此前只有一行灰字，看着像失效文本）
      Row({ space: 2 }) {
        Text(this.expanded ? t('collapse_preview') : t('expand_preview'))
          .fontSize(DesignTokens.fontCaption())
          .fontColor(DesignTokens.labelSecondary(this.theme))
        SymbolGlyph(this.expanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(DesignTokens.fontCaption())
          .fontColor([DesignTokens.labelSecondary(this.theme)])
      }
      .height(DesignTokens.touchTarget())
      .alignItems(VerticalAlign.Center)
      .accessibilityText(this.expanded ? t('collapse_preview') : t('expand_preview'))
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        if (this.onToggleExpand) {
          this.onToggleExpand();
        }
      })

      Blank()

      // 查看完整榜单：整块可点（此前只画了两段文本/图标，没有点击事件，点了没反应）
      Row({ space: 4 }) {
        Text(t('view_full_chart'))
          .fontSize(DesignTokens.fontBody())
          .fontColor(DesignTokens.accent())
          .fontWeight(FontWeight.Medium)
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(DesignTokens.fontHeadline())
          .fontColor([DesignTokens.accent()])
      }
      .height(DesignTokens.touchTarget())
      .alignItems(VerticalAlign.Center)
      .accessibilityText(t('view_full_chart'))
      .hoverEffect(HoverEffect.Highlight)
      .onClick(() => {
        if (this.onOpenBoard) {
          this.onOpenBoard();
        }
      })
    }
    .width('100%')
    .padding({ left: PREVIEW_ROW_PADDING, right: PREVIEW_ROW_PADDING, top: 4, bottom: 6 })
    .alignItems(VerticalAlign.Center)
  }


}
