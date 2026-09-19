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
}
