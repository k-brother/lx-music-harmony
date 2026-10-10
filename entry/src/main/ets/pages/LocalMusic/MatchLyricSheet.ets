/**
 * 本地音乐 - 手动匹配歌词/封面面板
 *
 * 本地歌没有平台身份，自动匹配（core/music/local/LyricMatch）是宁缺勿错的：
 * 配不准就不显示。用户觉得该有词的时候，在这里搜一次、自己挑正确的那条，
 * 选中后落盘（local.music.matches）并立即对正在播放的同一首重新取词。
 *
 * 形态与其它面板一致：底部面板（bindSheet，内容多所以用 large 档）+ 共享标题行
 * （左标题 + 右上角 ×）。**不要**自己画「居中卡片 + 全屏遮罩」——挂在页面里会被裁剪，
 * 观感也和其它面板两样（这条踩过）。「清除匹配」收在标题行右侧。
 *
 * 页面给初值 + 收回调，面板自己持有搜索状态；
 * 平台顺序取「设置 → 音源管理」里启用源的当前排序。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DesignTokens } from '../../theme/DesignTokens';
import { t, tf, sourceLabel } from '../../service/LocalizationService';
import { BottomSheet, dismissSheet } from '../../components/ui/BottomSheet';
import { SheetHeader } from '../../components/ui/SheetHeader';
import { localMusicService } from '../../service/LocalMusicService';
import { settingsService } from '../../service/SettingsService';
import { orderedEnabledSources } from '../../core/music/SourcePolicy';
import {
  scoreCandidate,
  searchCandidates,
  type MatchSongInfo
} from '../../core/music/local/LyricMatch';

const DOMAIN: number = 0x0001;
const TAG: string = 'MatchLyricSheet';

/** 一条搜索结果（带来源平台与相似度分） */
interface Candidate {
  source: string;
  info: MatchSongInfo;
  score: number;
}

@Component
export struct MatchLyricSheet {
  @StorageProp('theme') theme: string = 'light';
  /** 由页面控制显隐（关闭时页面会连同组件一起卸载） */
  @Link visible: boolean;
  /** 本地歌的 key（选中结果后落盘到它上面） */
  @Prop songKey: string = '';
  /** 关键词的初始值 */
  @Prop songName: string = '';
  @Prop singer: string = '';
  /** 本地歌时长（毫秒，0 = 未知），参与打分排序 */
  @Prop durationMs: number = 0;
  /** 选中一条后通知页面（info 为 null 表示清除了匹配；刷新列表 / 正在播的重新取词） */
  onPicked?: (info: MatchSongInfo | null, source: string) => void;
  onCancel?: () => void;

  @State keyword: string = '';
  @State searching: boolean = false;
  /** 已经搜过一轮（区分「还没搜」和「搜了但没有」） */
  @State searched: boolean = false;
  @State candidates: Candidate[] = [];
  /** 这首歌是否已有保存的匹配（决定要不要给「清除」入口） */
  @State hasSavedMatch: boolean = false;

  aboutToAppear(): void {
    this.keyword = this.singer.length > 0 ? `${this.songName} ${this.singer}` : this.songName;
    this.hasSavedMatch = localMusicService.matchOf(this.songKey) !== null;
    void this.search();
  }

  private cancel(): void {
    this.visible = dismissSheet(this.onCancel);
  }

  /** 按用户启用的平台顺序逐个搜，边搜边并结果（一个平台搜不到不影响别的） */
  private async search(): Promise<void> {
    const keyword: string = this.keyword.trim();
    if (keyword.length === 0 || this.searching) {
      return;
    }
    const settings = settingsService.get();
    const platforms = orderedEnabledSources(settings.sourceOrder, settings.disabledSources);
    if (platforms.length === 0) {
      hilog.warn(DOMAIN, TAG, 'search: no enabled platforms');
      return;
    }
    this.searching = true;
    this.searched = true;
    this.candidates = [];
    try {
      for (let i = 0; i < platforms.length; i++) {
        const platform: string = platforms[i];
        let results: MatchSongInfo[] = [];
        try {
          results = await searchCandidates(keyword, platform);
        } catch (err) {
          hilog.info(DOMAIN, TAG, 'search on %{public}s failed: %{public}s',
            platform, err instanceof Error ? err.message : JSON.stringify(err));
          continue;
        }
        const fresh: Candidate[] = [];
        for (let j = 0; j < results.length; j++) {
          const scored = scoreCandidate(results[j], this.songName, this.singer, this.durationMs);
          // 歌名完全不像的（归一化后毫无交集）不列出来，免得一屏全是无关的歌
          if (scored.score <= 0) {
            continue;
          }
          fresh.push({ source: platform, info: results[j], score: scored.score });
        }
        this.candidates = this.merge(this.candidates, fresh);
      }
    } finally {
      this.searching = false;
    }
  }

  /** 并入新结果：按相似度排序，同名同歌手的只留第一条 */
  private merge(current: Candidate[], fresh: Candidate[]): Candidate[] {
    const out: Candidate[] = current.slice();
    for (let i = 0; i < fresh.length; i++) {
      let exists: boolean = false;
      for (let j = 0; j < out.length; j++) {
        if (out[j].info.name === fresh[i].info.name && out[j].info.singer === fresh[i].info.singer) {
          exists = true;
          break;
        }
      }
      if (!exists) {
        out.push(fresh[i]);
      }
    }
    out.sort((a: Candidate, b: Candidate) => b.score - a.score);
    return out.slice(0, 40);
  }

  /** 选中一条：落盘 + 补封面（服务内异步做），再通知页面刷新 */
  private pick(item: Candidate): void {
    void localMusicService.applyPickedMatch(this.songKey, item.source, item.info);
    this.visible = dismissSheet();
    if (this.onPicked) {
      this.onPicked(item.info, item.source);
    }
  }

  /** 清除已保存的匹配（自动匹配不会因此重试；正在播的这首会重新取词） */
  private clearSaved(): void {
    void localMusicService.clearMatch(this.songKey);
    this.visible = dismissSheet();
    if (this.onPicked) {
      this.onPicked(null, '');
    }
  }

  build() {
    BottomSheet({
      visible: $visible,
      // 标题自绘（左标题 + 右上角关闭），不用 BottomSheet 的居中标题栏
      title: '',
      // 结果列表要滚动，用大面板档（高度接近全屏），与小面板的自适应高度区分开
      sheetSize: 'large',
      onDismiss: (): void => {
        this.cancel();
      },
      content: (): void => {
        this.Content();
      },
    })
  }

  @Builder
  Content() {
    Column({ space: 10 }) {
      SheetHeader({
        title: t('match_lyric_sheet_title'),
        // 有已保存的匹配时才有「清除」
        trailing: (): void => {
          this.ClearAction();
        },
        onClose: (): void => {
          this.cancel();
        },
      })

      Text(t('match_lyric_hint'))
        .fontSize(DesignTokens.fontCaption())
        .fontColor(DesignTokens.labelTertiary(this.theme))
        .width('100%')
        .textAlign(TextAlign.Start)

      this.SearchBar()
      this.StatusLine()
      this.ResultList()
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  /** 标题行右侧的次要危险动作（没有已保存的匹配时不渲染） */
  @Builder
  ClearAction() {
    if (this.hasSavedMatch) {
      Text(t('match_lyric_clear'))
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(DesignTokens.danger())
        .maxLines(1)
        .padding({ left: 8, right: 8 })
        .onClick(() => {
          this.clearSaved();
        })
    }
  }

  @Builder
  SearchBar() {
    Row({ space: 8 }) {
      TextInput({ text: this.keyword, placeholder: t('match_lyric_placeholder') })
        .placeholderColor(DesignTokens.labelTertiary(this.theme))
        .fontSize(DesignTokens.fontSubhead())
        .height(DesignTokens.touchTarget())
        .layoutWeight(1)
        .backgroundColor(DesignTokens.mutedFill(this.theme))
        .borderRadius(10)
        .onChange((value: string) => {
          this.keyword = value;
        })
        .onSubmit(() => {
          void this.search();
        })
      Button(t('match_lyric_search'))
        .fontSize(DesignTokens.fontSubhead())
        .fontColor(DesignTokens.onAccent())
        .height(DesignTokens.touchTarget())
        .backgroundColor(DesignTokens.accent())
        .borderRadius(10)
        .enabled(this.keyword.trim().length > 0 && !this.searching)
        .onClick(() => {
          void this.search();
        })
    }
    .width('100%')
  }

  @Builder
  StatusLine() {
    if (this.searching) {
      Text(this.candidates.length > 0
        ? tf('match_lyric_partial', [this.candidates.length.toString()])
        : t('match_lyric_searching'))
        .fontSize(DesignTokens.fontCaption())
        .fontColor(DesignTokens.labelSecondary(this.theme))
        .width('100%')
        .textAlign(TextAlign.Start)
    } else if (this.searched && this.candidates.length === 0) {
      Text(t('match_lyric_empty'))
        .fontSize(DesignTokens.fontCaption())
        .fontColor(DesignTokens.labelTertiary(this.theme))
        .width('100%')
        .textAlign(TextAlign.Start)
    }
  }

  @Builder
  ResultList() {
    List() {
      ForEach(this.candidates, (item: Candidate) => {
        ListItem() {
          Column({ space: 3 }) {
            Text(item.info.name)
              .fontSize(DesignTokens.fontBody())
              .fontColor(DesignTokens.labelPrimary(this.theme))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .textAlign(TextAlign.Start)
            Row({ space: 8 }) {
              Text(item.info.singer)
                .fontSize(DesignTokens.fontCaption())
                .fontColor(DesignTokens.labelTertiary(this.theme))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .textAlign(TextAlign.Start)
              if (item.info.interval.length > 0) {
                Text(item.info.interval)
                  .fontSize(DesignTokens.fontCaption())
                  .fontColor(DesignTokens.labelTertiary(this.theme))
              }
              Text(sourceLabel(item.source))
                .fontSize(DesignTokens.fontCaption())
                .fontColor(DesignTokens.labelSecondary(this.theme))
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .borderRadius(6)
                .backgroundColor(DesignTokens.mutedFill(this.theme))
            }
            .width('100%')
          }
          .width('100%')
          .padding({ top: 9, bottom: 9 })
          .onClick(() => {
            this.pick(item);
          })
        }
      }, (item: Candidate) => `${item.source}_${item.info.songId}_${item.info.name}`)
    }
    .scrollBar(BarState.Off)
    .layoutWeight(1)
    .width('100%')
    .divider({ strokeWidth: 0.6, color: DesignTokens.cardBorder(this.theme) })
  }
}
