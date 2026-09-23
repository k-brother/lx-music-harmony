/**
 * 歌词视图组件 - 支持高亮同步滚动
 */

import { t } from '../../service/LocalizationService';
import { DesignTokens } from '../../theme/DesignTokens';
import type { LyricWord, WordLyricLine } from '../../core/lyric/WordLyric';
import { isConfirmKey } from '../../utils/KeyboardTools';

/** 动态背景/封面背景下的文字阴影（半径小、偏移 0，等效"描边感"） */

@Component
export struct LyricView {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('showAnimation') showAnimation: boolean = true;
  @StorageProp('showLyricTranslation') showLyricTranslation: boolean = true;
  @StorageProp('showLyricRoma') showLyricRoma: boolean = true;
  @StorageProp('lyricFontSize') lyricFontSize: number = 16;
  @StorageProp('lyricAlign') lyricAlign: string = 'center';
  /** 字体阴影（设置 → 外观）：动态背景上提升可读性 */
  @StorageProp('fontShadow') fontShadow: boolean = false;
  @Prop lyricLines: string[] = [];
  @Prop secondaryLyricLines: string[] = [];
  /** 罗马音（拼音）行，与 lyricLines 一一对应 */
  @Prop romaLines: string[] = [];
  /** 逐字歌词（与 lyricLines 一一对应） */
  @Prop wordLyricLines: WordLyricLine[] = [];
  /** 当前行已唱到第几个字（-1 = 当前行没有逐字数据，走普通渲染） */
  @Prop playedWordCount: number = -1;
  /** 设置 → 播放 → 逐字歌词 */
  @StorageProp('wordLyric') wordLyric: boolean = true;
  @Prop @Watch('onCurrentLyricIndexChanged') currentLyricIndex: number = -1;
  /** 点击某一行歌词（主流播放器：点哪句就跳到那句） */
  onLineTap?: (index: number) => void;
  /** 长按某一行歌词（复制这一句） */
  onLineLongPress?: (index: number) => void;
  private lyricScroller: Scroller = new Scroller();
  private lineHeight: number = 62;
  private pendingScrollTimer: number = -1;
  private alive: boolean = false;
  /**
   * 用户手动滑动过歌词（此时停止自动跟随，并显示「回到当前」）。
   * 主流播放器都这么做：用户往上翻看歌词时，不应该被下一句强行拽回来。
   */
  @State userScrolled: boolean = false;
  /** 程序化滚动的「保护期」：这段时间内的滚动事件不算用户操作 */
  private selfScrollUntil: number = 0;

  aboutToAppear(): void {
    this.alive = true;
  }

  aboutToDisappear(): void {
    this.alive = false;
    if (this.pendingScrollTimer !== -1) {
      clearTimeout(this.pendingScrollTimer);
      this.pendingScrollTimer = -1;
    }
  }

  private onCurrentLyricIndexChanged(): void {
    if (this.currentLyricIndex < 0 || this.lyricLines.length === 0) {
      // 换歌/清空：回到「跟随」状态
      this.userScrolled = false;
      return;
    }
    // 用户正在自己翻歌词：让位给用户，只更新高亮不强制滚动
    if (this.userScrolled) {
      return;
    }
    if (this.pendingScrollTimer !== -1) {
      clearTimeout(this.pendingScrollTimer);
      this.pendingScrollTimer = -1;
    }
    this.pendingScrollTimer = setTimeout(() => {
      if (!this.alive || this.currentLyricIndex < 0 || this.currentLyricIndex >= this.lyricLines.length) {
        this.pendingScrollTimer = -1;
        return;
      }
      this.scrollToCurrentLine(true);
      this.pendingScrollTimer = -1;
    }, 60);
  }

  /** 滚动到当前句（动画可选）。程序化滚动会被打上时间戳，避免被误判成用户操作 */
  private scrollToCurrentLine(animation: boolean): void {
    if (this.currentLyricIndex < 0 || this.currentLyricIndex >= this.lyricLines.length) {
      return;
    }
    const targetOffset = Math.max(0, this.currentLyricIndex * this.lineHeight - this.lineHeight * 3);
    this.selfScrollUntil = Date.now() + 400;
    try {
      this.lyricScroller.scrollTo({ xOffset: 0, yOffset: targetOffset, animation });
    } catch (_err) {
      // Ignore single scroll failure to avoid UI crash loops.
    }
  }

  /** 手动滚动 → 退出跟随；程序化滚动期间的事件忽略 */
  private onUserScroll(): void {
    if (Date.now() < this.selfScrollUntil) {
      return;
    }
    if (!this.userScrolled) {
      this.userScrolled = true;
    }
  }

  /** 回到当前句：恢复跟随并滚回去 */
  private resumeFollow(): void {
    this.userScrolled = false;
    this.scrollToCurrentLine(true);
  }

  /** 设置里的对齐方式 → ArkUI 对齐枚举 */
  private alignMode(): TextAlign {
    if (this.lyricAlign === 'left') {
      return TextAlign.Start;
    }
    if (this.lyricAlign === 'right') {
      return TextAlign.End;
    }
    return TextAlign.Center;
  }

  /** 当前行取主题强调色，保证跟随主题/深浅色 */
  private accentColor(): string {
    return DesignTokens.accent();
  }

  /**
   * 当前行是否具备逐字数据（三条件：设置开启、确实是当前行、这一行有逐字标记）。
   * 不满足时当前行退回整句高亮的普通渲染。
   */
  private canRenderKaraoke(index: number): boolean {
    return this.wordLyric
      && index === this.currentLyricIndex
      && this.playedWordCount >= 0
      && index < this.wordLyricLines.length
      && this.wordLyricLines[index].words.length > 0;
  }

  /** 逐字渲染里「还没唱到」的字用的颜色：与其它行同色，保证整行仍读得清 */
  private pendingWordColor(): string {
    return this.theme === 'dark' ? DesignTokens.lyricDimDark() : DesignTokens.lyricDimLight();
  }

  /** 设置里的对齐方式 → Flex 主轴对齐 */
  private flexAlign(): FlexAlign {
    if (this.lyricAlign === 'left') {
      return FlexAlign.Start;
    }
    if (this.lyricAlign === 'right') {
      return FlexAlign.End;
    }
    return FlexAlign.Center;
  }

  /**
   * 逐字（卡拉OK）歌词：已唱到的字用主题强调色，没唱到的保持暗色。
   * 逐字数据的时间粒度就是「一个字」，因此不需要再做渐变遮罩就有连续推进的观感。
   */
  @Builder
  KaraokeLine(index: number) {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: this.flexAlign(), alignItems: ItemAlign.Center }) {
      ForEach(this.wordLyricLines[index].words, (word: LyricWord, wordIndex: number) => {
        Text(word.text)
          .fontSize(this.lyricFontSize + 4)
          .fontWeight(FontWeight.Bold)
          .fontColor(wordIndex < this.playedWordCount ? this.accentColor() : this.pendingWordColor())
          .textShadow(this.fontShadow ? DesignTokens.textShadowOnArtwork() : undefined)
      }, (word: LyricWord, wordIndex: number) => `w_${wordIndex}_${word.text}`)
    }
    .width('100%')
  }

  /**
   * 非当前行按与当前行的距离递减透明度：离得越远越淡，
   * 让视线自然聚焦在当前句上（主流歌词动效的基本做法）。
   */
  private lineOpacity(index: number): number {
    if (this.currentLyricIndex < 0 || index === this.currentLyricIndex) {
      return 1;
    }
    const distance: number = Math.abs(index - this.currentLyricIndex);
    if (distance === 1) {
      return 0.72;
    }
    if (distance === 2) {
      return 0.5;
    }
    return 0.32;
  }

  build() {
    if (this.lyricLines.length === 0) {
      this.EmptyPlaceholder()
    } else {
      // Stack 承载「回到当前」浮层：歌词区自身是滚动容器，按钮要浮在上面
      Stack({ alignContent: Alignment.BottomEnd }) {
        Scroll(this.lyricScroller) {
          Column() {
            ForEach(this.lyricLines, (line: string, index: number) => {
              this.LineRow(line, index)
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 120, bottom: 120 })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        // 用户手动滚动 → 退出自动跟随（程序化滚动期间的事件由时间戳过滤）
        .onDidScroll(() => {
          this.onUserScroll();
        })

        if (this.userScrolled) {
          this.ResumeFollowButton()
        }
      }
      .width('100%')
      .height('100%')
    }
  }

  /** 「回到当前句」：用户翻看歌词后一键回到正在唱的那句（主流播放器的通用入口） */
  @Builder
  ResumeFollowButton() {
    Row({ space: 4 }) {
      SymbolGlyph($r('sys.symbol.arrow_down_to_line'))
        .fontSize(DesignTokens.fontSubhead())
        .fontColor([DesignTokens.accent()])
      Text(t('lyric_resume_follow'))
        .fontSize(DesignTokens.fontCaption())
        .fontColor(DesignTokens.accent())
    }
    .padding({ left: 12, right: 12, top: 7, bottom: 7 })
    .backgroundColor(DesignTokens.chromeBar(this.theme))
    .borderRadius(DesignTokens.radiusSearch())
    .border({ width: 0.5, color: DesignTokens.cardBorder(this.theme) })
    .shadow(DesignTokens.floatingShadow())
    .margin({ right: 16, bottom: 24 })
    .accessibilityText(t('lyric_resume_follow'))
    .onClick(() => {
      this.resumeFollow();
    })
  }

  /** 无歌词占位 */
  @Builder
  EmptyPlaceholder() {
    Column() {
      Text(t('no_lyric'))
        .fontSize(DesignTokens.fontBody())
        .fontColor(this.theme === 'dark'
          ? DesignTokens.lyricPlaceholderDark() : DesignTokens.lyricPlaceholderLight())
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  /** 一行歌词：主句（可逐字）/ 罗马音 / 译文 + 点击、长按、键盘三种交互 */
  @Builder
  LineRow(line: string, index: number) {
    Column({ space: 2 }) {
      this.MainLineText(line, index)
      this.RomaLine(index)
      this.TranslationLine(index)
    }
    .width('100%')
    .height(this.lineHeight)
    .padding({ left: 8, right: 8 })
    .justifyContent(FlexAlign.Center)
    // 点哪句跳到哪句（主流音乐播放器的通用交互）；PC 上补悬停反馈
    .hoverEffect(HoverEffect.Highlight)
    .onClick(() => {
      // 点某句 = 想跳到这句听：恢复跟随，随后的索引变化会把视图带过去
      this.userScrolled = false;
      if (this.onLineTap) {
        this.onLineTap(index);
      }
    })
    .gesture(
      LongPressGesture()
        .onAction(() => {
          if (this.onLineLongPress) {
            this.onLineLongPress(index);
          }
        })
    )
    // 2in1（PC 接键盘）：回车/空格 = 点这一句跳转
    .focusable(true)
    .onKeyEvent((event: KeyEvent): void => {
      if (isConfirmKey(event) && this.onLineTap) {
        this.onLineTap(index);
      }
    })
    .animation({
      // 「设置 -> 外观 -> 动画效果」关闭时不做滚动动画
      duration: this.showAnimation ? 300 : 0,
    })
  }

  /** 主句：有逐字数据走逐字高亮，否则整句高亮（当前行放大加粗、其余降对比） */
  @Builder
  MainLineText(line: string, index: number) {
    if (this.canRenderKaraoke(index)) {
      // 有逐字数据的当前行：逐字高亮（已唱/未唱两色）
      this.KaraokeLine(index)
    } else {
      Text(line)
        // 当前行放大加粗、非当前行降对比，是最主流的歌词视觉层次；
        // 基准字号与对齐方式来自「歌词显示」设置
        .fontSize(index === this.currentLyricIndex ? this.lyricFontSize + 4 : this.lyricFontSize)
        .fontColor(index === this.currentLyricIndex
          ? this.accentColor()
          : (this.theme === 'dark' ? DesignTokens.lyricDimDark() : DesignTokens.lyricDimLight()))
        .fontWeight(index === this.currentLyricIndex ? FontWeight.Bold : FontWeight.Normal)
        .opacity(this.lineOpacity(index))
        .textAlign(this.alignMode())
        .width('100%')
        .maxLines(1)
        .textShadow(this.fontShadow ? DesignTokens.textShadowOnArtwork() : undefined)
    }
  }

  /** 罗马音（拼音）行：设置开启且该行有内容时才渲染 */
  @Builder
  RomaLine(index: number) {
    if (this.showLyricRoma && index < this.romaLines.length
      && this.romaLines[index] && this.romaLines[index].length > 0) {
      Text(this.romaLines[index])
        .fontSize(index === this.currentLyricIndex ? 12 : 10)
        .fontColor(index === this.currentLyricIndex
          ? (this.theme === 'dark' ? DesignTokens.lyricRomaActiveDark() : DesignTokens.lyricRomaActiveLight())
          : (this.theme === 'dark' ? DesignTokens.lyricRomaDimDark() : DesignTokens.lyricRomaDimLight()))
        .opacity(this.lineOpacity(index))
        .textAlign(this.alignMode())
        .width('100%')
        .maxLines(1)
    }
  }

  /** 译文行：设置开启且该行有内容时才渲染 */
  @Builder
  TranslationLine(index: number) {
    if (this.showLyricTranslation && index < this.secondaryLyricLines.length
      && this.secondaryLyricLines[index] && this.secondaryLyricLines[index].length > 0) {
      Text(this.secondaryLyricLines[index])
        .fontSize(index === this.currentLyricIndex ? 13 : 11)
        .fontColor(index === this.currentLyricIndex
          ? (this.theme === 'dark' ? DesignTokens.lyricTransActiveDark() : DesignTokens.lyricTransActiveLight())
          : (this.theme === 'dark' ? DesignTokens.lyricTransDimDark() : DesignTokens.lyricTransDimLight()))
        .opacity(this.lineOpacity(index))
        .textAlign(TextAlign.Center)
        .width('100%')
        .maxLines(1)
    }
  }
}
