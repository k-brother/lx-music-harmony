/**
 * 桌面歌词 - 系统级子窗口悬浮歌词
 *
 * 使用 WindowStage.createSubWindow 创建独立子窗口，
 * 在应用内所有页面之上悬浮显示当前播放歌词。
 * 锁定屏幕/控制中心歌词信息由 AVSession 元数据提供。
 */

import hilog from '@ohos.hilog';
import window from '@ohos.window';
import { display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { playerService, ProgressInfo, MusicInfo, PlayStatus } from '../../service/PlayerService';
import { parseLrc, getCurrentLyricIndex, LyricLine } from '../../core/music/MusicParsingUtils';
import type { DesktopLyricPosition } from '../../service/SettingsService';

const DOMAIN: number = 0x0002;
const TAG: string = 'DesktopLyric';
const SUB_WINDOW_NAME: string = 'desktopLyric';

// 是否保留显示状态，切歌时不清除
let keepShowing: boolean = false;

// ============ 歌词控制器（单例） ============

class DesktopLyricController {
  private static instance: DesktopLyricController;
  private progressUnsub: (() => void) | null = null;
  private musicUnsub: (() => void) | null = null;
  private stateUnsub: (() => void) | null = null;
  private lyricLines: LyricLine[] = [];
  private currentIndex: number = -1;
  private playing: boolean = false;
  private currentSongName: string = '';

  static getInstance(): DesktopLyricController {
    if (!DesktopLyricController.instance) {
      DesktopLyricController.instance = new DesktopLyricController();
    }
    return DesktopLyricController.instance;
  }

  start(): void {
    if (this.progressUnsub) return;

    this.progressUnsub = playerService.onProgressInfoChange((prog: ProgressInfo) => {
      if (this.lyricLines.length === 0) return;
      const idx = getCurrentLyricIndex(this.lyricLines, prog.nowPlayTime);
      if (idx >= 0 && idx !== this.currentIndex) {
        this.currentIndex = idx;
        const text = this.lyricLines[idx].text ||
          this.lyricLines[this.lyricLines.length - 1]?.text || '';
        AppStorage.setOrCreate('desktopLyricText', text);
      }
      if (!this.playing) this.playing = true;
    });

    this.musicUnsub = playerService.onMusicInfoChange((info: MusicInfo) => {
      this.currentSongName = info.name || '';
      this.lyricLines = [];
      this.currentIndex = -1;
      if (keepShowing && this.currentSongName) {
        AppStorage.setOrCreate('desktopLyricText', this.currentSongName);
      }
    });

    this.stateUnsub = playerService.onStatusChange((status: PlayStatus) => {
      if (status === 'playing') {
        this.playing = true;
        if (keepShowing && this.lyricLines.length > 0) {
          DesktopLyricWindow.show();
        }
      } else if (status === 'paused' || status === 'idle') {
        this.playing = false;
      } else if (status === 'stopped') {
        this.playing = false;
        DesktopLyricWindow.hide();
      }
    });
  }

  stop(): void {
    this.progressUnsub?.();
    this.musicUnsub?.();
    this.stateUnsub?.();
    this.progressUnsub = null;
    this.musicUnsub = null;
    this.stateUnsub = null;
  }

  setLyricData(lyricText: string): void {
    if (!lyricText) {
      this.lyricLines = [];
      return;
    }
    this.lyricLines = parseLrc(lyricText);
    this.currentIndex = -1;
  }

  getLyricLines(): LyricLine[] {
    return this.lyricLines;
  }

  isPlaying(): boolean {
    return this.playing;
  }
}

export const desktopLyricController = DesktopLyricController.getInstance();

// ============ 子窗口管理器 ============

class DesktopLyricWindow {
  private static subWindow: window.Window | null = null;
  private static isCreated: boolean = false;
  private static position: string = 'top';

  /** 根据位置计算窗口 Y 坐标 */
  private static calcWindowY(position: string, winHeight: number, displayHeight: number, density: number): number {
    if (position === 'middle') {
      return Math.floor((displayHeight - winHeight) / 2);
    }
    if (position === 'bottom') {
      return displayHeight - winHeight - 80 * density;
    }
    return 0;
  }

  /**
   * 创建并显示子窗口
   */
  static async create(): Promise<void> {
    if (DesktopLyricWindow.isCreated) return;

    const windowStage = AppStorage.get('windowStage') as window.WindowStage | undefined;
    if (!windowStage) {
      hilog.error(DOMAIN, TAG, 'windowStage not found in AppStorage');
      return;
    }

    try {
      const win = await windowStage.createSubWindow(SUB_WINDOW_NAME);
      DesktopLyricWindow.subWindow = win;

      // 获取屏幕宽度和密度，设置窗口位置和大小
      const displayInfo = display.getDefaultDisplaySync();
      const winWidth = displayInfo.width;
      const winHeight = 56 * displayInfo.densityPixels;

      // 根据设置决定窗口位置
      DesktopLyricWindow.position = AppStorage.get('desktopLyricPosition') as string || 'top';
      const winY = DesktopLyricWindow.calcWindowY(
        DesktopLyricWindow.position, winHeight, displayInfo.height, displayInfo.densityPixels);

      await win.moveWindowTo(0, winY);
      await win.resize(winWidth, winHeight);

      // 加载子窗口页面
      await win.setUIContent('pages/DesktopLyricPage');
      await win.setWindowBackgroundColor('#00000000');
      await win.setWindowTouchable(true);
      await win.setWindowFocusable(false); // 不抢主窗口焦点

      await win.showWindow();
      DesktopLyricWindow.isCreated = true;
      hilog.info(DOMAIN, TAG, 'DesktopLyric sub-window created and shown');
    } catch (err) {
      const e = err as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to create desktop lyric sub-window: code=%{public}d, msg=%{public}s',
        e.code, e.message || '');
    }
  }

  /**
   * 显示子窗口（重新 show，用于从隐藏状态恢复）
   */
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

  /**
   * 隐藏子窗口（最小化）
   */
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

  /**
   * 销毁子窗口
   */
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

  /** 位置变化时实时移动子窗口 */
  static async applyPosition(position: string): Promise<void> {
    DesktopLyricWindow.position = position;
    if (!DesktopLyricWindow.isCreated || !DesktopLyricWindow.subWindow) {
      return;
    }
    try {
      const displayInfo = display.getDefaultDisplaySync();
      const winHeight = 56 * displayInfo.densityPixels;
      const winY = DesktopLyricWindow.calcWindowY(position, winHeight, displayInfo.height, displayInfo.densityPixels);
      await DesktopLyricWindow.subWindow.moveWindowTo(0, winY);
      hilog.info(DOMAIN, TAG, 'Desktop lyric position updated: %{public}s', position);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Failed to move desktop lyric window');
    }
  }

  static isShowing(): boolean {
    return DesktopLyricWindow.isCreated;
  }

  /**
   * 更新是否保活状态
   */
  static setKeepShowing(keep: boolean): void {
    keepShowing = keep;
  }
}

// ============ 公开 API（供 PlayDetailPage 使用） ============

export class DesktopLyricManager {
  /**
   * 启用/禁用桌面歌词
   */
  static setEnabled(enabled: boolean): void {
    keepShowing = enabled;
    DesktopLyricWindow.setKeepShowing(enabled);

    if (enabled) {
      desktopLyricController.start();
      void DesktopLyricWindow.create();
    } else {
      desktopLyricController.stop();
      void DesktopLyricWindow.destroy();
    }
  }

  /**
   * 收到歌词数据后同步到子窗口
   */
  static onLyricLoaded(lyricText: string): void {
    desktopLyricController.setLyricData(lyricText);
    if (keepShowing && desktopLyricController.isPlaying()) {
      void DesktopLyricWindow.show();
    }
  }

  /** 桌面歌词位置变化（设置页） */
  static applyPosition(position: DesktopLyricPosition): void {
    void DesktopLyricWindow.applyPosition(position);
  }

  /** 当前是否已开启桌面歌词 */
  static isEnabled(): boolean {
    return keepShowing;
  }
}
