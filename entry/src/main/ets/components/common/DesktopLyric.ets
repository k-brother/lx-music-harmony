/**
 * 桌面歌词 - 悬浮歌词子窗口
 *
 * 职责边界：
 * - 歌词内容与时间轴由 PlayerService 统一维护（同一份数据同时喂给系统播控、
 *   桌面歌词和播放页），这里只负责"把当前句渲染到系统子窗口里"。
 * - 窗口本身默认完全透明，靠文字描边/阴影保证可读性，不再是"一条黑条"。
 * - 支持拖动改位置、锁定穿透、字号/颜色/背景不透明度/单双行等外观设置。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { DesignTokens } from '../../theme/DesignTokens';
import { window } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { avSession } from '@kit.AVSessionKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { playerService, type LyricLineState, type PlayStatus } from '../../service/PlayerService';
import { settingsService, type AppSettings, type DesktopLyricPosition } from '../../service/SettingsService';
import { backgroundRunningManager } from '../../service/BackgroundRunningManager';

const DOMAIN: number = 0x0002;
const TAG: string = 'DesktopLyric';
const SUB_WINDOW_NAME: string = 'desktopLyric';
/** 单行文字占用的垂直空间系数（相对字号） */
const LINE_HEIGHT_RATIO: number = 1.6;
/** 窗口上下留白（vp） */
const VERTICAL_PADDING_VP: number = 6;

/**
 * 把播放器的歌词状态同步到 AppStorage，供子窗口页面（@StorageLink）消费。
 * 子窗口与主窗口同进程共享模块单例，因此这里写入即可被页面读到。
 */
class DesktopLyricController {
  private static instance: DesktopLyricController | null = null;
  private lyricUnsub: (() => void) | null = null;
  private statusUnsub: (() => void) | null = null;

  static getInstance(): DesktopLyricController {
    if (!DesktopLyricController.instance) {
      DesktopLyricController.instance = new DesktopLyricController();
    }
    return DesktopLyricController.instance;
  }

  start(): void {
    if (this.lyricUnsub) {
      return;
    }
    this.lyricUnsub = playerService.onLyricLineChange((state: LyricLineState) => {
      DesktopLyricController.applyLyricState(state);
    });
    this.statusUnsub = playerService.onStatusChange((status: PlayStatus) => {
      if (status === 'stopped' || status === 'idle') {
        AppStorage.setOrCreate('desktopLyricText', '');
        AppStorage.setOrCreate('desktopLyricNextText', '');
      }
    });
  }

  stop(): void {
    if (this.lyricUnsub) {
      this.lyricUnsub();
      this.lyricUnsub = null;
    }
    if (this.statusUnsub) {
      this.statusUnsub();
      this.statusUnsub = null;
    }
  }

  /** 歌词行 -> AppStorage（子窗口页面直接绑定） */
  static applyLyricState(state: LyricLineState): void {
    if (!state.hasLyric) {
      AppStorage.setOrCreate('desktopLyricText', '');
      AppStorage.setOrCreate('desktopLyricNextText', '');
      AppStorage.setOrCreate('desktopLyricNext2Text', '');
      return;
    }
    if (state.current.length > 0) {
      AppStorage.setOrCreate('desktopLyricText', state.current);
    }
    AppStorage.setOrCreate('desktopLyricNextText', state.next);
    AppStorage.setOrCreate('desktopLyricNext2Text', state.next2);
  }
}

/**
 * 子窗口管理：尺寸随字号/行数自适应，位置支持预设档位与拖动自定义。
 */
class DesktopLyricWindow {
  private static subWindow: window.Window | null = null;
  private static isCreated: boolean = false;
  private static currentX: number = 0;
  private static currentY: number = 0;

  /** 依据当前外观设置计算窗口高度（px） */
  private static calcWindowHeight(settings: AppSettings, density: number): number {
    // 单行模式只展示当前句，窗口高度按 1 行算（安卓版 desktopLyric.isSingleLine）
    const lineCount: number = settings.desktopLyricSingleLine
      ? 1
      : Math.max(1, settings.desktopLyricMaxLines);
    const contentVp: number = settings.desktopLyricFontSize * LINE_HEIGHT_RATIO * lineCount
      + VERTICAL_PADDING_VP * 2;
    return Math.ceil(contentVp * density);
  }

  private static calcWindowY(
    settings: AppSettings, winHeight: number, displayHeight: number, density: number
  ): number {
    if (settings.desktopLyricPosition === 'custom' && settings.desktopLyricY >= 0) {
      return settings.desktopLyricY;
    }
    if (settings.desktopLyricPosition === 'middle') {
      return Math.floor((displayHeight - winHeight) / 2);
    }
    if (settings.desktopLyricPosition === 'bottom') {
      return displayHeight - winHeight - Math.round(80 * density);
    }
    return Math.round(48 * density);
  }

  private static calcWindowX(settings: AppSettings): number {
    if (settings.desktopLyricPosition === 'custom' && settings.desktopLyricX >= 0) {
      return settings.desktopLyricX;
    }
    return 0;
  }

  /** 创建并显示子窗口（已存在则只刷新外观） */
  static async create(): Promise<void> {
    if (DesktopLyricWindow.isCreated) {
      await DesktopLyricWindow.applyAppearance();
      return;
    }

    const windowStage = AppStorage.get('windowStage') as window.WindowStage | undefined;
    if (!windowStage) {
      hilog.error(DOMAIN, TAG, 'windowStage not found in AppStorage');
      return;
    }

    try {
      const settings = settingsService.get();
      const win = await windowStage.createSubWindow(SUB_WINDOW_NAME);
      DesktopLyricWindow.subWindow = win;

      const displayInfo = display.getDefaultDisplaySync();
      const density: number = displayInfo.densityPixels;
      const winWidth: number = Math.round(displayInfo.width * settings.desktopLyricWidth / 100);
      const winHeight: number = DesktopLyricWindow.calcWindowHeight(settings, density);
      const winX: number = settings.desktopLyricPosition === 'custom' && settings.desktopLyricX >= 0
        ? settings.desktopLyricX
        : Math.round((displayInfo.width - winWidth) / 2);
      const winY: number = DesktopLyricWindow.calcWindowY(settings, winHeight, displayInfo.height, density);

      await win.moveWindowTo(winX, winY);
      await win.resize(winWidth, winHeight);
      await win.setUIContent('pages/DesktopLyricPage');
      await win.setWindowBackgroundColor(DesignTokens.transparent());
      await win.setWindowFocusable(false); // 不抢主窗口焦点
      await DesktopLyricWindow.applyTouchable(settings.desktopLyricLocked);
      await win.showWindow();

      DesktopLyricWindow.currentX = winX;
      DesktopLyricWindow.currentY = winY;
      DesktopLyricWindow.isCreated = true;
      hilog.info(DOMAIN, TAG, 'Desktop lyric window created: y=%{public}d, height=%{public}d, locked=%{public}s',
        winY, winHeight, settings.desktopLyricLocked.toString());
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to create desktop lyric sub-window: code=%{public}d, msg=%{public}s',
        e.code, e.message || '');
    }
  }

  /** 外观（字号/行数/背景/锁定）变化时重新计算窗口尺寸 */
  static async applyAppearance(): Promise<void> {
    const win = DesktopLyricWindow.subWindow;
    if (!DesktopLyricWindow.isCreated || !win) {
      return;
    }
    try {
      const settings = settingsService.get();
      const displayInfo = display.getDefaultDisplaySync();
      const density: number = displayInfo.densityPixels;
      const winHeight: number = DesktopLyricWindow.calcWindowHeight(settings, density);
      const winY: number = settings.desktopLyricPosition === 'custom'
        ? DesktopLyricWindow.currentY
        : DesktopLyricWindow.calcWindowY(settings, winHeight, displayInfo.height, density);
      const winX: number = settings.desktopLyricPosition === 'custom'
        ? DesktopLyricWindow.currentX
        : DesktopLyricWindow.calcWindowX(settings);
      await win.resize(Math.round(displayInfo.width * settings.desktopLyricWidth / 100), winHeight);
      await win.moveWindowTo(winX, winY);
      DesktopLyricWindow.currentX = winX;
      DesktopLyricWindow.currentY = winY;
      await DesktopLyricWindow.applyTouchable(settings.desktopLyricLocked);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'applyAppearance failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 锁定 = 窗口不接收触摸（点击穿透，避免看视频/操作时误拖歌词） */
  private static async applyTouchable(locked: boolean): Promise<void> {
    const win = DesktopLyricWindow.subWindow;
    if (!win) {
      return;
    }
    try {
      await win.setWindowTouchable(!locked);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'setWindowTouchable failed: %{public}s', JSON.stringify(err));
    }
  }

  static setLocked(locked: boolean): void {
    void DesktopLyricWindow.applyTouchable(locked);
  }

  /** 位置档位切换 */
  static async applyPosition(): Promise<void> {
    if (!DesktopLyricWindow.isCreated || !DesktopLyricWindow.subWindow) {
      return;
    }
    const settings = settingsService.get();
    // getDefaultDisplaySync 会抛异常：取不到屏幕信息时干脆不动窗口尺寸，
    // 免得拿着 0 密度去算出一个离谱的高度
    let displayInfo: display.Display;
    try {
      displayInfo = display.getDefaultDisplaySync();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'getDefaultDisplaySync failed: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      return;
    }
    const density: number = displayInfo.densityPixels;
    const winHeight: number = DesktopLyricWindow.calcWindowHeight(settings, density);
    const winX: number = settings.desktopLyricPosition === 'custom'
      ? DesktopLyricWindow.currentX
      : DesktopLyricWindow.calcWindowX(settings);
    const winY: number = settings.desktopLyricPosition === 'custom'
      ? DesktopLyricWindow.currentY
      : DesktopLyricWindow.calcWindowY(settings, winHeight, displayInfo.height, density);
    await DesktopLyricWindow.moveTo(winX, winY, false);
  }

  /**
   * 移动窗口
   * @param persistAsCustom 拖动结束时调用，把当前位置记为自定义位置
   */
  static async moveTo(x: number, y: number, persistAsCustom: boolean = true): Promise<void> {
    const win = DesktopLyricWindow.subWindow;
    if (!DesktopLyricWindow.isCreated || !win) {
      return;
    }
    try {
      const displayInfo = display.getDefaultDisplaySync();
      const density: number = displayInfo.densityPixels;
      const settings = settingsService.get();
      const winHeight: number = DesktopLyricWindow.calcWindowHeight(settings, density);
      const maxX: number = Math.max(0, displayInfo.width - 120 * density);
      const maxY: number = Math.max(0, displayInfo.height - winHeight);
      const nextX: number = Math.min(Math.max(0, Math.round(x)), maxX);
      const nextY: number = Math.min(Math.max(0, Math.round(y)), maxY);

      await win.moveWindowTo(nextX, nextY);
      DesktopLyricWindow.currentX = nextX;
      DesktopLyricWindow.currentY = nextY;

      if (persistAsCustom) {
        await settingsService.update({
          desktopLyricPosition: 'custom',
          desktopLyricX: nextX,
          desktopLyricY: nextY,
        });
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'moveTo failed: %{public}s', JSON.stringify(err));
    }
  }

  static getPosition(): number[] {
    return [DesktopLyricWindow.currentX, DesktopLyricWindow.currentY];
  }

  static async show(): Promise<void> {
    if (!DesktopLyricWindow.isCreated) {
      await DesktopLyricWindow.create();
      return;
    }
    try {
      const win = DesktopLyricWindow.subWindow;
      if (win) {
        await win.showWindow();
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to show desktop lyric window');
    }
  }

  static async hide(): Promise<void> {
    try {
      const win = DesktopLyricWindow.subWindow;
      if (win) {
        await win.minimize();
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to hide desktop lyric window');
    }
  }

  static async destroy(): Promise<void> {
    try {
      const win = DesktopLyricWindow.subWindow;
      if (win) {
        await win.destroyWindow();
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to destroy desktop lyric window');
    }
    DesktopLyricWindow.subWindow = null;
    DesktopLyricWindow.isCreated = false;
  }

  static isShowing(): boolean {
    return DesktopLyricWindow.isCreated;
  }
}

// ============ 公开 API（供设置页 / 播放页 / 桌面歌词页调用） ============

export class DesktopLyricManager {
  /** 当前是否在使用系统原生桌面歌词（否则为内置悬浮窗） */
  private static usingSystemLyric: boolean = false;
  /** 会话就绪回调只绑定一次 */
  private static sessionHookBound: boolean = false;
  /** 系统歌词状态订阅只绑定一次 */
  private static observersBound: boolean = false;
  /**
   * 本应用期望的系统歌词可见性。
   * 与系统回调不一致时说明是「用户在系统侧操作」，需要回写应用设置，避免来回打架。
   */
  private static expectedVisible: boolean | null = null;

  /**
   * 订阅系统歌词的可见性/锁定状态。
   * 系统歌词是系统自己渲染的窗口，用户在系统侧锁定或关闭只有这两条回调能感知；
   * 不订阅就会出现「应用里显示已开启、屏幕上看不到歌词」的错位。
   */
  private static bindSystemLyricObservers(): void {
    if (DesktopLyricManager.observersBound) {
      return;
    }
    DesktopLyricManager.observersBound = true;
    backgroundRunningManager.observeSystemDesktopLyric(
      (visible: boolean): void => {
        DesktopLyricManager.onSystemVisibilityChanged(visible);
      },
      (state: avSession.DesktopLyricState): void => {
        DesktopLyricManager.onSystemLockChanged(state.isLocked);
      });
  }

  /** 用户在系统侧显示/关闭了歌词 */
  private static onSystemVisibilityChanged(visible: boolean): void {
    if (DesktopLyricManager.expectedVisible === visible) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'System desktop lyric visibility changed externally: %{public}s',
      visible.toString());
    if (visible) {
      return;
    }
    // 系统侧已关闭：应用里的开关一起收回来，否则再点一次「开启」没有任何反应
    DesktopLyricManager.usingSystemLyric = false;
    backgroundRunningManager.setSystemDesktopLyricActive(false);
    DesktopLyricController.getInstance().stop();
    backgroundRunningManager.unobserveSystemDesktopLyric();
    DesktopLyricManager.observersBound = false;
    settingsService.update({ showDesktopLyric: false }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'sync desktop lyric off failed: %{public}s', err.message);
    });
  }

  /** 用户在系统歌词上切换了锁定 */
  private static onSystemLockChanged(locked: boolean): void {
    if (locked === settingsService.get().desktopLyricLocked) {
      return;
    }
    hilog.info(DOMAIN, TAG, 'System desktop lyric lock changed externally: %{public}s', locked.toString());
    settingsService.update({ desktopLyricLocked: locked }).catch((err: Error) => {
      hilog.warn(DOMAIN, TAG, 'sync desktop lyric lock failed: %{public}s', err.message);
    });
  }

  /**
   * 绑定「AVSession 就绪」回调。
   *
   * 启动恢复桌面歌词时播控会话还没建立（要等首次播放），系统歌词挂不上，
   * 只能先给内置浮窗；等会话就绪后这里自动升级到系统原生歌词，
   * 用户端就不会一直看到那个黑色浮条了。
   */
  static bindSessionReadyHook(): void {
    if (DesktopLyricManager.sessionHookBound) {
      return;
    }
    DesktopLyricManager.sessionHookBound = true;
    backgroundRunningManager.onSessionReady((): void => {
      if (DesktopLyricManager.usingSystemLyric || !settingsService.get().showDesktopLyric) {
        return;
      }
      void DesktopLyricManager.upgradeToSystemLyric();
    });
  }

  /** 从内置浮窗切换到系统原生歌词（失败则保持浮窗） */
  private static async upgradeToSystemLyric(): Promise<void> {
    const settings = settingsService.get();
    const supported = await backgroundRunningManager.isSystemDesktopLyricSupported();
    if (!supported) {
      return;
    }
    const enabledOnSystem = await backgroundRunningManager.enableSystemDesktopLyric(true);
    if (!enabledOnSystem) {
      return;
    }

    DesktopLyricManager.usingSystemLyric = true;
    DesktopLyricController.getInstance().start();
    DesktopLyricController.applyLyricState(playerService.getLyricState());
    await backgroundRunningManager.setSystemDesktopLyricLocked(settings.desktopLyricLocked);
    DesktopLyricManager.expectedVisible = true;
    DesktopLyricManager.bindSystemLyricObservers();
    // 释放内置浮窗，避免系统歌词与浮窗同时显示
    await DesktopLyricWindow.destroy();
    hilog.info(DOMAIN, TAG, 'Upgraded to system desktop lyric after session ready');
  }

  /**
   * 开关桌面歌词。
   * 优先使用 HarmonyOS 原生桌面歌词（与华为音乐同款观感，跟随系统设置），
   * 设备/系统不支持时自动降级为内置悬浮窗。
   */
  static async setEnabled(enabled: boolean): Promise<void> {
    DesktopLyricManager.bindSessionReadyHook();
    const controller = DesktopLyricController.getInstance();
    if (!enabled) {
      if (DesktopLyricManager.usingSystemLyric) {
        DesktopLyricManager.expectedVisible = false;
        await backgroundRunningManager.setSystemDesktopLyricVisible(false);
        await backgroundRunningManager.enableSystemDesktopLyric(false);
        backgroundRunningManager.unobserveSystemDesktopLyric();
        DesktopLyricManager.observersBound = false;
      }
      backgroundRunningManager.setSystemDesktopLyricActive(false);
      controller.stop();
      await DesktopLyricWindow.destroy();
      DesktopLyricManager.usingSystemLyric = false;
      return;
    }

    const settings = settingsService.get();
    // 1) 系统原生桌面歌词
    const systemSupported = await backgroundRunningManager.isSystemDesktopLyricSupported();
    if (systemSupported) {
      DesktopLyricManager.expectedVisible = true;
      const enabledOnSystem = await backgroundRunningManager.enableSystemDesktopLyric(true);
      if (enabledOnSystem) {
        controller.start();
        DesktopLyricController.applyLyricState(playerService.getLyricState());
        await backgroundRunningManager.setSystemDesktopLyricLocked(settings.desktopLyricLocked);
        DesktopLyricManager.bindSystemLyricObservers();
        DesktopLyricManager.usingSystemLyric = true;
        hilog.info(DOMAIN, TAG, 'Using system desktop lyric');
        return;
      }
    }

    // 2) 降级：内置悬浮歌词子窗口
    DesktopLyricManager.usingSystemLyric = false;
    DesktopLyricManager.expectedVisible = null;
    controller.start();
    DesktopLyricController.applyLyricState(playerService.getLyricState());
    await DesktopLyricWindow.create();
    hilog.info(DOMAIN, TAG, 'Using built-in floating lyric window');
  }

  static isEnabled(): boolean {
    return DesktopLyricManager.usingSystemLyric || DesktopLyricWindow.isShowing();
  }

  /** 当前是否走的系统歌词（设置页据此给出提示文案） */
  static isUsingSystemLyric(): boolean {
    return DesktopLyricManager.usingSystemLyric;
  }

  /** 位置档位变化 */
  static applyPosition(_position: DesktopLyricPosition): void {
    if (DesktopLyricManager.usingSystemLyric) {
      // 系统歌词的位置由系统负责，这里不做干预
      return;
    }
    void DesktopLyricWindow.applyPosition();
  }

  /** 字号/行数/背景不透明度/锁定变化 */
  static applyAppearance(): void {
    if (DesktopLyricManager.usingSystemLyric) {
      return;
    }
    void DesktopLyricWindow.applyAppearance();
  }

  static setLocked(locked: boolean): void {
    if (DesktopLyricManager.usingSystemLyric) {
      void backgroundRunningManager.setSystemDesktopLyricLocked(locked);
      return;
    }
    DesktopLyricWindow.setLocked(locked);
  }

  /** 由歌词页拖动结束调用：提交新的绝对坐标并记住 */
  static moveTo(x: number, y: number): void {
    void DesktopLyricWindow.moveTo(x, y, true);
  }

  /** 拖动过程中调用：只移动窗口，不写存储（避免拖动时反复落盘） */
  static dragTo(x: number, y: number): void {
    void DesktopLyricWindow.moveTo(x, y, false);
  }

  static getPosition(): number[] {
    return DesktopLyricWindow.getPosition();
  }

  static hide(): void {
    void DesktopLyricWindow.hide();
  }
}
