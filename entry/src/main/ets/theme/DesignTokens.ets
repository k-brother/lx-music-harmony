/**
 * 应用级视觉 token：浅/深统一出口，便于各 Tab 与播放器一致迭代。
 * 取向：Apple HIG / Human Interface — 系统分组底、清晰层次、克制描边与 8pt 网格。
 */
export class DesignTokens {
  /** 内容区左右安全边距（与系统「边到边内容」约 16pt 对齐） */
  static spaceGutter(): number {
    return 16;
  }

  static spaceUnit(): number {
    return 8;
  }

  static pageBg(theme: string): string {
    return theme === 'dark' ? '#0C0C0E' : '#F2F2F7';
  }

  static chromeBar(theme: string): string {
    return theme === 'dark' ? '#141416' : '#FFFFFF';
  }

  static card(theme: string): string {
    return theme === 'dark' ? '#1C1D21' : '#FFFFFF';
  }

  static cardBorder(theme: string): string {
    return theme === 'dark' ? '#2A2B30' : 'rgba(60,60,67,0.12)';
  }

  static mutedFill(theme: string): string {
    return theme === 'dark' ? '#25262B' : '#E5E5EA';
  }

  /** 搜索框 / 输入底上的极轻描边（浅模式接近 iOS systemGray5 边界感） */
  static searchFieldBorder(theme: string): string {
    return theme === 'dark' ? 'rgba(255,255,255,0.10)' : 'rgba(60,60,67,0.18)';
  }

  /** 顶栏、列表顶部分隔线 */
  static hairlineSeparator(theme: string): string {
    return theme === 'dark' ? 'rgba(255,255,255,0.12)' : 'rgba(60,60,67,0.29)';
  }

  /** 深色模式下的卡片悬停态 */
  static cardHover(theme: string): string {
    return theme === 'dark' ? '#25262B' : '#F8F8F8';
  }

  /** 分段控件轨道（UISegmentedControl 式灰底） */
  static segmentedTrack(theme: string): string {
    return theme === 'dark' ? '#2C2C2E' : '#E5E5EA';
  }

  /** 分段选中滑块（浅：白块浮在轨道上；深：略提亮） */
  static segmentedThumb(theme: string): string {
    return theme === 'dark' ? '#3A3A3C' : '#FFFFFF';
  }

  static labelPrimary(theme: string): string {
    return theme === 'dark' ? '#F5F5F7' : '#1D1D1F';
  }

  static labelSecondary(theme: string): string {
    return theme === 'dark' ? '#AEAEB2' : '#636366';
  }

  static labelTertiary(theme: string): string {
    return theme === 'dark' ? '#8E8E93' : '#8E8E93';
  }

  static accent(): string {
    return '#E63946';
  }

  static accentSoft(theme: string): string {
    return theme === 'dark' ? 'rgba(230,57,70,0.22)' : 'rgba(230,57,70,0.10)';
  }

  /** 危险/删除动作（iOS systemRed） */
  static danger(): string {
    return '#FF3B30';
  }

  /** 进行中/成功（下载完成、已启用等「正常推进」状态） */
  static success(): string {
    return '#34C759';
  }

  /** 等待中/暂停（需要用户注意但不报错，iOS systemOrange） */
  static warning(): string {
    return '#FF9500';
  }

  /** 面板/弹窗背后的遮罩（系统 bindSheet 的 maskColor 也用它，保证观感一致） */
  static maskColor(): string {
    return 'rgba(0, 0, 0, 0.42)';
  }

  /**
   * 压在封面等图片上的小标签底色（播放量角标等）。
   * 与全屏遮罩区分开：这里的目的是「让白字在任意封面上可读」，不能太黑。
   */
  static scrim(): string {
    return 'rgba(0, 0, 0, 0.40)';
  }

  /**
   * 全屏图片预览上的半透明按钮底（评论大图预览的「关闭」胶囊）。
   * 图片内容不可控，用中性半透明白保证按钮边界可见。
   */
  static translucentOnImage(): string {
    return 'rgba(255, 255, 255, 0.20)';
  }

  /** 桌面歌词子窗口的透明底（窗口级 API 需要 #AARRGGBB 形态） */
  static transparent(): string {
    return '#00000000';
  }

  /** 中性信息（已完成的历史条目） */
  static info(): string {
    return '#0A84FF';
  }

  /** 强调色底上的文字色 */
  static onAccent(): string {
    return '#FFFFFF';
  }

  // ==================== 歌词文字层次（播放页 / 桌面歌词共用） ====================
  // 之前这些灰阶写死在 LyricView 内部，深浅色各一套；收成 token 后歌词样式可统一调整。

  /** 非当前歌词行（深色主题） */
  static lyricDimDark(): string {
    return '#8A8A93';
  }

  /** 非当前歌词行（浅色主题） */
  static lyricDimLight(): string {
    return '#8E8E93';
  }

  /** 歌词空状态文案色（深 / 浅） */
  static lyricPlaceholderDark(): string {
    return '#8A8A93';
  }

  static lyricPlaceholderLight(): string {
    return '#9A9AA0';
  }

  /** 当前行的罗马音（深 / 浅） */
  static lyricRomaActiveDark(): string {
    return '#9E9EA6';
  }

  static lyricRomaActiveLight(): string {
    return '#8E8E93';
  }

  /** 非当前行罗马音（深 / 浅） */
  static lyricRomaDimDark(): string {
    return '#6E6E78';
  }

  static lyricRomaDimLight(): string {
    return '#B0B0B6';
  }

  /** 当前行翻译（深 / 浅） */
  static lyricTransActiveDark(): string {
    return '#D0A0A5';
  }

  static lyricTransActiveLight(): string {
    return '#B75A62';
  }

  /** 非当前行翻译（深 / 浅） */
  static lyricTransDimDark(): string {
    return '#6E6E78';
  }

  static lyricTransDimLight(): string {
    return '#A0A0AA';
  }

  /** 禁用态填充/文字 */
  static disabled(theme: string): string {
    return theme === 'dark' ? '#3A3A3C' : '#C7C7CC';
  }

  static radiusCard(): number {
    return 14;
  }

  /** 搜索条、小输入容器（接近 iOS 10pt 连续圆角） */
  static radiusSearch(): number {
    return 10;
  }

  /** 封面、缩略图方图 */
  static radiusCover(): number {
    return 10;
  }

  static radiusPill(): number {
    return 20;
  }

  /** 搜索条建议高度（约 36pt，介于 compact 与默认之间） */
  static heightSearchField(): number {
    return 36;
  }

  static tabBarBg(theme: string): string {
    return theme === 'dark' ? '#121214' : '#FBFBFD';
  }

  /**
   * 玻璃材质底色（底部导航 / 迷你播放条这类"浮在内容之上"的底舱）。
   *
   * 为什么是半透明：要和 `.backgroundBlurStyle(COMPONENT_THICK)` 配合 —— 模糊负责
   * "透出下面滚动的内容"，这层底色负责在没有模糊能力时文字依然可读（不等于全透明）。
   */
  static glassFill(theme: string): string {
    return theme === 'dark' ? 'rgba(28,29,33,0.70)' : 'rgba(255,255,255,0.70)';
  }

  /** 玻璃材质描边：比卡片描边亮一档，浮在内容上时有"一片玻璃"的厚度感 */
  static glassStroke(theme: string): string {
    return theme === 'dark' ? 'rgba(255,255,255,0.16)' : 'rgba(255,255,255,0.72)';
  }

  /**
   * 底部玻璃底舱的占位高度（迷你播放条 + Tab 栏 + 间距，不含底部安全区）。
   * Tab 里的滚动内容按这个值留出底部空间，内容才能滚到玻璃底舱"下面"（玻璃才有东西可透）。
   */
  static bottomDockHeight(): number {
    // 迷你播放条 50 + 两行间隙 4 + Tab 栏 50 = 104，取 108 留 4 余量
    //（迷你条与 Tab 栏高度见下面各自的 token，改一处即可整组跟随）
    return 108;
  }

  /**
   * 底舱两行（迷你播放条 / Tab 栏）之间的间隙。
   * 两行是**两个独立的圆角容器**（对照华为音乐的底舱）：这段缝就是天然的分界，
   * 不需要再画分隔线；贴在一起会糊成一片、看不出是两行。
   */
  static dockRowGap(): number {
    return 4;
  }

  /**
   * 玻璃底舱距**屏幕底部**的间距。
   *
   * 这里刻意不用 `safeBottomVp`：窗口内容区本来就已经避开底部安全区了，
   * 再按安全区高度给底舱留白，会把它往上顶约两倍安全区的高度（真机上就是一条
   * 几十 vp 的空带，看着像"底部一大块浪费"）。底舱贴着屏幕底部放，
   * 只留系统手势条那条小横条的生存空间即可。
   */
  static dockBottomGap(): number {
    // 14：底舱下沿贴着系统手势条的上沿"往上挪一点点"——不挨着那条小横条，也不留出明显空带。
    // 注意这个值是**真实**的下边界距离：HomeBottomDock 已按 safeBottomVp 把底舱压回屏幕底部
    //（此前没压时，这个数再改都看不出效果）。
    return 14;
  }

  /** 底舱容器圆角：里面装两行内容，比普通卡片圆一档 */
  static dockRadius(): number {
    return 20;
  }

  /**
   * 底舱距屏幕左右边缘的间距。
   * 12：比页面常规留白（16）略小，底舱更"满"一些（用户几次反馈底舱偏窄）；
   * 但也不能贴到屏幕边框上，否则玻璃会糊在边上。
   */
  static dockSideMargin(): number {
    // 16：与页面常规留白一致（用户明确"窄"指的是上下厚度，不是左右宽度）
    return 16;
  }

  /** 玻璃底舱给内容留的底部空间（底舱本体 + 与屏幕底的间距） */
  static dockContentInset(): number {
    return DesignTokens.bottomDockHeight() + DesignTokens.dockBottomGap();
  }

  // ── 迷你播放条（PlayerBar，首页底舱与各二级页共用）─────────────────────────
  // 尺寸集中在这里：平板/PC 要换一套数值（或换成侧栏形态）时只改这一处，
  // 不要去组件里翻写死的数字。间距尽量由 spaceUnit() 推导，避免又散出新常量。
  /** 迷你条高度 */
  static miniBarHeight(): number {
    return 50;
  }

  /** 迷你条封面边长 */
  static miniCoverSize(): number {
    return 44;
  }

  /** 迷你条播放键直径 */
  static miniPlaySize(): number {
    return 30;
  }

  /** 迷你条左右内边距 */
  static miniPaddingH(): number {
    return 12;
  }

  /**
   * 收拢态左侧「房子」圆形按钮的直径。
   * 取行高同值（= miniBarHeight）：房子是**独立的圆形容器**，与播放条同一行，
   * 高度一致才不会把这一行撑高（之前把房子塞进播放条内部，收拢时把行撑高了 6vp）。
   */
  static dockHouseSize(): number {
    return 50;
  }

  // ── 底部 Tab 栏（仅窄屏；宽屏走左侧侧栏导航）─────────────────────────────
  /** Tab 栏高度 */
  static tabBarHeight(): number {
    return 50;
  }

  /** Tab 条目高度（图标 + 文案的可点区，留 40 保证点按手感） */
  static tabItemHeight(): number {
    return 48;
  }

  /** Tab 选中胶囊高度 */
  static tabCapsuleHeight(): number {
    return 30;
  }

  /** Tab 选中胶囊相对条目的左右内缩 */
  static tabCapsuleInset(): number {
    return 6;
  }

  /** Tab 图标字号 */
  static tabIconSize(): number {
    // 底部导航图标比正文图标（iconMd）大一档，与系统底部导航的比例一致
    return DesignTokens.iconMd() + 4;
  }

  // Typography scale (core surfaces: tab bar / player bar / play detail)
  static fontTitle(): number {
    return 16;
  }

  static fontBody(): number {
    return 14;
  }

  static fontCaption(): number {
    return 12;
  }

  static fontMicro(): number {
    return 11;
  }

  // ==================== 完整字阶（对齐 App 里实际使用的 11~26 档） ====================
  // 之前只定义了 11/12/14/16，其余档位在各页面里写裸数字（13/15/17/18/20/24/26），
  // 改字号要全项目搜；这里补齐命名，调用点统一走 token（数值不变）。

  /** 说明文字 / 次级标题（13） */
  static fontCallout(): number {
    return 13;
  }

  /** 列表主文案的次级档（15） */
  static fontSubhead(): number {
    return 15;
  }

  /** 强调标题（17） */
  static fontHeadline(): number {
    return 17;
  }

  /** 面板标题（18） */
  static fontHeading(): number {
    return 18;
  }

  /** 播放控制图标文字 / 大号正文（20） */
  static fontLarge(): number {
    return 20;
  }

  /** 页面大标题（24） */
  static fontDisplay(): number {
    return 24;
  }

  /** 首屏超大标题（26） */
  static fontDisplayLarge(): number {
    return 26;
  }

  /** 角标 / 微标签（10） */
  static fontBadge(): number {
    return 10;
  }

  /** 大号图标字号（19，用于行内操作图标） */
  static fontIconLg(): number {
    return 19;
  }

  /** 卡片/锁屏标题与中号图标（22） */
  static fontBanner(): number {
    return 22;
  }

  /** 大图标/大标题（32）：锁屏大标题、卡片无封面时的占位音符 */
  static fontHero(): number {
    return 32;
  }

  /** 特大图标字号（22，用于入口行图标） */
  static fontIconXl(): number {
    return 22;
  }

  /** 首屏大标题（28，下载管理页等） */
  static fontDisplayXl(): number {
    return 28;
  }

  /** 封面占位图标（30）——此前 29/30 两个值混用，统一到一档 */
  static fontCoverIcon(): number {
    return 30;
  }

  /** 封面上的播放图标（36） */
  static fontDisplayHuge(): number {
    return 36;
  }

  // Icon & control scale
  static iconSm(): number {
    return 14;
  }

  static iconMd(): number {
    return 16;
  }

  static iconLg(): number {
    return 20;
  }

  static ctrlSm(): number {
    return 30;
  }

  static ctrlMd(): number {
    return 44;
  }

  static ctrlLg(): number {
    return 64;
  }

  // ==================== 列表行度量（所有列表页统一，避免各页各写一套） ====================

  /** 带封面/序号的行高 */
  static rowHeight(): number {
    return 56;
  }

  /** 双行文案（标题 + 副标题）的行高 */
  static rowHeightTwoLine(): number {
    return 64;
  }

  /** 列表行内缩进（与封面/序号对齐，分割线使用） */
  static rowInset(): number {
    return 60;
  }

  /** 列表行内封面尺寸 */
  static rowCover(): number {
    return 44;
  }

  /** 最小可点区域（HarmonyOS/iOS 人因规范：≥ 44vp） */
  static touchTarget(): number {
    return 44;
  }

  /**
   * 把视觉尺寸小的控件（图标按钮等）响应区域放大到 44vp
   *
   * 系统可用性规范要求可点元素 ≥44×44vp；图标往往只有 20~30vp，
   * 直接放大图标会破坏视觉层次，用 responseRegion 扩大热区即可。
   * 用法：IconButton(...).responseRegion(DesignTokens.touchRegion(22))
   */
  static touchRegion(size: number): Rectangle {
    const target = DesignTokens.touchTarget();
    const pad = Math.max(0, (target - size) / 2);
    const region: Rectangle = {
      x: -pad,
      y: -pad,
      width: Math.max(target, size),
      height: Math.max(target, size),
    };
    return region;
  }

  /** 顶部栏高度 */
  static navBarHeight(): number {
    // 常规顶栏高度：比 56 收一档（真机反馈偏高），仍容纳 44 的返回触控区
    return 48;
  }

  // ==================== 动效（统一时长与曲线，避免每页写 220/260/300 混杂） ====================

  /** 状态切换（按压、选中、明暗） */
  static motionFast(): number {
    return 160;
  }

  /** 常规过渡（页面内容、面板出现） */
  static motionNormal(): number {
    return 240;
  }

  /** 强调过渡（封面缩放、Tab 切换） */
  static motionSlow(): number {
    return 320;
  }

  /** 按压反馈不透明度（全应用统一） */
  static pressedOpacity(): number {
    return 0.65;
  }

  /** 卡片阴影：浅色模式给一点层次，深色模式靠描边 */
  static cardShadow(theme: string): ShadowOptions | undefined {
    if (theme === 'dark') {
      return undefined;
    }
    return { radius: 12, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 2 };
  }

  /** 悬浮元素（播放条、浮层卡片）的通用投影 */
  static softShadow(): ShadowOptions {
    return { radius: 10, color: 'rgba(0,0,0,0.08)', offsetX: 0, offsetY: 3 };
  }

  /** 底部迷你播放条这类「贴边悬浮」元素的投影（比卡片更软、偏移更大） */
  static floatingShadow(): ShadowOptions {
    return { radius: 16, color: 'rgba(0,0,0,0.08)', offsetX: 0, offsetY: 4 };
  }

  /**
   * 图片/动态背景上的文字阴影。
   *
   * 播放页、歌词视图、播放页顶栏原先各自定义了一份完全相同的常量，
   * 收敛到这里，保证「同一张背景图上的文字」观感一致。
   */
  static textShadowOnArtwork(): ShadowOptions {
    return { radius: 8, color: 'rgba(0,0,0,0.55)', offsetX: 0, offsetY: 0 };
  }
}
