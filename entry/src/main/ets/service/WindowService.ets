/**
 * 窗口服务 - 管理窗口属性和主题应用
 * 负责更新状态栏、导航栏和窗口背景色
 */

import hilog from '@ohos.hilog';
import window from '@ohos.window';
import { BusinessError } from '@kit.BasicServicesKit';
import { onThemeChange, getActiveTheme, getAppBackground } from './ThemeService';

const TAG = 'WindowService';
const DOMAIN = 0x0005;

function businessErrCode(err: Error | object): number {
  const b = err as BusinessError;
  return typeof b.code === 'number' ? b.code : -1;
}

async function delayMs(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, ms);
  });
}

function normalizeWindowColor(color: string): string {
  const raw = (color ?? '').trim();
  if (!raw) {
    return '#FFFFFF';
  }
  const compact = raw.replace(/\s+/g, '');
  if (compact.startsWith('#')) {
    return compact;
  }

  const rgbMatch = compact.match(/^rgb\((\d{1,3}),(\d{1,3}),(\d{1,3})\)$/i);
  if (rgbMatch) {
    const r = clampColorInt(Number(rgbMatch[1]));
    const g = clampColorInt(Number(rgbMatch[2]));
    const b = clampColorInt(Number(rgbMatch[3]));
    return `#${toHex2(r)}${toHex2(g)}${toHex2(b)}`;
  }

  const rgbaMatch = compact.match(/^rgba\((\d{1,3}),(\d{1,3}),(\d{1,3}),([0-9]*\.?[0-9]+)\)$/i);
  if (rgbaMatch) {
    const r = clampColorInt(Number(rgbaMatch[1]));
    const g = clampColorInt(Number(rgbaMatch[2]));
    const b = clampColorInt(Number(rgbaMatch[3]));
    const alpha = clampAlpha01(Number(rgbaMatch[4]));
    // Window 接口对 rgba(...) 兼容性差，统一转 #AARRGGBB 避免 invalid color string。
    const a = Math.round(alpha * 255);
    return `#${toHex2(a)}${toHex2(r)}${toHex2(g)}${toHex2(b)}`;
  }

  return raw;
}

function clampColorInt(value: number): number {
  if (!Number.isFinite(value)) {
    return 0;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 255) {
    return 255;
  }
  return Math.round(value);
}

function clampAlpha01(value: number): number {
  if (!Number.isFinite(value)) {
    return 1;
  }
  if (value < 0) {
    return 0;
  }
  if (value > 1) {
    return 1;
  }
  return value;
}

function toHex2(value: number): string {
  return value.toString(16).padStart(2, '0').toUpperCase();
}

// 窗口实例
let mainWindow: window.Window | null = null;

/** 上次已成功下发到窗口的背景色；与本次相同时跳过 setWindowBackgroundColor，避免 initTheme 二次 notify 触发 401 */
let lastSuccessfulWindowBg: string = '';

/**
 * 初始化窗口服务
 */
export async function initWindowService(windowStage: window.WindowStage): Promise<void> {
  try {
    mainWindow = await windowStage.getMainWindow();
    hilog.info(DOMAIN, TAG, 'WindowService initialized');

    // 与 EntryAbility.initApp 中的 initAllServices（含 initTheme）并发：首帧前改系统栏易返回 401，略延迟再应用
    await delayMs(80);
    // 初始应用主题到窗口
    await applyThemeToWindow();
    
    // initTheme 完成会立刻 notify，与首次 apply 连击时 setWindowBackgroundColor 易 401，略延迟再应用
    onThemeChange(async () => {
      await delayMs(48);
      await applyThemeToWindow();
    });
    
    // 保存取消订阅函数以便清理
    // 注意：在HarmonyOS中，我们通常不需要手动清理，因为应用生命周期会处理
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to init WindowService: %{public}s', JSON.stringify(err));
  }
}

/**
 * 将当前主题应用到窗口
 */
export async function applyThemeToWindow(): Promise<void> {
  if (!mainWindow) {
    hilog.warn(DOMAIN, TAG, 'No main window available');
    return;
  }
  
  try {
    const activeTheme = getActiveTheme();
    
    let backgroundColor = '#FFFFFF';
    let systemBarColor = '#FFFFFF';
    let statusBarContentColor = '#000000';
    let navigationBarContentColor = '#000000';
    
    if (activeTheme) {
      // 使用主题的主背景色
      backgroundColor = normalizeWindowColor(getAppBackground());
      
      // 判断是否为深色主题
      const isDark = activeTheme.get('c-000') === 'rgb(0,0,0)' || 
                    activeTheme.get('c-000') === 'rgba(0,0,0,1)';
      
      if (isDark) {
        // 深色主题：使用深色背景，浅色文字
        systemBarColor = normalizeWindowColor(activeTheme.get('c-050') || '#141414');
        statusBarContentColor = '#FFFFFF';
        navigationBarContentColor = '#FFFFFF';
      } else {
        // 浅色主题：使用浅色背景，深色文字
        systemBarColor = normalizeWindowColor(activeTheme.get('c-000') || '#FFFFFF');
        statusBarContentColor = '#000000';
        navigationBarContentColor = '#000000';
      }
    } else {
      // 回退到简单主题检测
      const currentTheme = AppStorage.get('theme') || 'light';
      backgroundColor = currentTheme === 'dark' ? '#121212' : '#FFFFFF';
      systemBarColor = currentTheme === 'dark' ? '#1C1C1C' : '#FFFFFF';
      statusBarContentColor = currentTheme === 'dark' ? '#FFFFFF' : '#000000';
      navigationBarContentColor = currentTheme === 'dark' ? '#FFFFFF' : '#000000';
    }
    backgroundColor = normalizeWindowColor(backgroundColor);
    systemBarColor = normalizeWindowColor(systemBarColor);
    
    // 窗口背景与系统栏分开设置；initTheme 会触发第二次 apply，背景字符串与上次相同则不再调系统 API
    let backgroundApplied = false;
    const skipDuplicateBg: boolean =
      lastSuccessfulWindowBg.length > 0 && backgroundColor === lastSuccessfulWindowBg;
    if (skipDuplicateBg) {
      backgroundApplied = true;
    } else {
      for (let bgAttempt = 0; bgAttempt < 2; bgAttempt++) {
        if (bgAttempt > 0) {
          await delayMs(120);
        }
        try {
          await mainWindow.setWindowBackgroundColor(backgroundColor);
          backgroundApplied = true;
          lastSuccessfulWindowBg = backgroundColor;
          break;
        } catch (bgErr) {
          const bc = businessErrCode(bgErr as object);
          if (bc === 401 && bgAttempt === 0) {
            hilog.warn(DOMAIN, TAG, 'setWindowBackgroundColor returned 401, retrying once');
            continue;
          }
          if (bc === 401) {
            hilog.warn(
              DOMAIN,
              TAG,
              'setWindowBackgroundColor 401 after retry (often duplicate apply); continuing with system bar'
            );
            break;
          }
          hilog.error(DOMAIN, TAG, 'setWindowBackgroundColor failed: %{public}s', JSON.stringify(bgErr));
          return;
        }
      }
    }

    const systemBarProperties: window.SystemBarProperties = {
      statusBarColor: systemBarColor,
      statusBarContentColor: statusBarContentColor,
      navigationBarColor: systemBarColor,
      navigationBarContentColor: navigationBarContentColor,
    };

    const applySystemBarsOnce = async (): Promise<void> => {
      try {
        await mainWindow!.setWindowSystemBarEnable(['status', 'navigation']);
      } catch (enErr) {
        hilog.info(DOMAIN, TAG, 'setWindowSystemBarEnable: %{public}s', JSON.stringify(enErr));
      }
      await mainWindow!.setWindowSystemBarProperties(systemBarProperties);
    };

    let lastBarErr: Error | object | null = null;
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        if (attempt > 0) {
          await delayMs(160);
        }
        await applySystemBarsOnce();
        hilog.info(
          DOMAIN,
          TAG,
          'Theme applied to window: bg=%{public}s, systemBar=%{public}s',
          backgroundColor,
          systemBarColor
        );
        return;
      } catch (barErr) {
        lastBarErr = barErr as object;
        const c = businessErrCode(barErr as object);
        if (c === 401 && attempt === 0) {
          hilog.warn(DOMAIN, TAG, 'setWindowSystemBarProperties returned 401, retrying once');
          continue;
        }
        if (c === 401) {
          hilog.warn(
            DOMAIN,
            TAG,
            'System bar theme not supported or window not ready (401); bgApplied=%{public}s',
            backgroundApplied ? 'true' : 'false'
          );
          return;
        }
        break;
      }
    }
    hilog.error(DOMAIN, TAG, 'setWindowSystemBarProperties failed: %{public}s', JSON.stringify(lastBarErr));
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to apply theme to window: %{public}s', JSON.stringify(err));
  }
}

/**
 * 获取主窗口实例
 */
export function getMainWindow(): window.Window | null {
  return mainWindow;
}

/**
 * 设置窗口沉浸式模式
 */
export async function setImmersiveMode(immersive: boolean): Promise<void> {
  if (!mainWindow) return;
  
  try {
    if (immersive) {
      // 沉浸式：传入空数组表示不启用状态栏/导航栏区域显示
      await mainWindow.setWindowSystemBarEnable([]);
    } else {
      // 正常模式：同时启用状态栏与导航栏
      await mainWindow.setWindowSystemBarEnable(['status', 'navigation']);
      // 重新应用主题
      await applyThemeToWindow();
    }
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'Failed to set immersive mode: %{public}s', JSON.stringify(err));
  }
}

// 窗口服务接口
export interface WindowServiceInterface {
  initWindowService: (windowStage: window.WindowStage) => Promise<void>;
  applyThemeToWindow: () => Promise<void>;
  getMainWindow: () => window.Window | null;
  setImmersiveMode: (immersive: boolean) => Promise<void>;
}

const windowService: WindowServiceInterface = {
  initWindowService,
  applyThemeToWindow,
  getMainWindow,
  setImmersiveMode,
};

export default windowService;