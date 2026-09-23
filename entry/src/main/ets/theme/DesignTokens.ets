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

  static accentSecondary(): string {
    return '#F1FAEE';
  }

  static accentTertiary(): string {
    return '#A8DADC';
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

  /** 中性信息（已完成的历史条目） */
  static info(): string {
    return '#0A84FF';
  }

  /** 强调色底上的文字色 */
  static onAccent(): string {
    return '#FFFFFF';
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

  static tabBarBorder(theme: string): string {
    return theme === 'dark' ? '#2C2D32' : 'rgba(0,0,0,0.08)';
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
    return 56;
  }

  /** 底部面板圆角（商业化 App 常见的 20-24） */
  static radiusSheet(): number {
    return 22;
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
