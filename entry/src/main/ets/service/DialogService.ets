/**
 * 对话框 / 菜单 / 轻提示统一入口
 *
 * 之前每个页面各写一遍：
 *   - `new Promise(resolve => showDialog({title, message, buttons:[取消,确认]}, cb))`
 *   - `showActionMenu({title, buttons:[...6 元组]}, cb)`（按钮数量受限，超过 6 个要自己拆二级菜单）
 *   - `showToast({message})` + try/catch
 * 现在统一到这里，页面只关心「问一句」或「列一组动作」：
 *   const ok = await appConfirm('删除', '删除后不可恢复');
 *   const index = await appActionMenu('歌曲名', ['播放','下一首播放','收藏','分享','不喜欢'], [4]);
 *   appToast('已添加');
 *
 * ActionMenu 超过 5 项时自动折叠为「前 4 项 + 更多…」，选择后再展开剩余项，
 * 返回值始终是**原始数组下标**，调用方不需要感知折叠。
 */
import hilog from '@ohos.hilog';
import { t } from './LocalizationService';
import { getAppUiContext } from './UiContext';
import { DesignTokens } from '../theme/DesignTokens';
import { promptAction } from '@kit.ArkUI';
import { hapticService } from './HapticService';

const DOMAIN = 0x0005;
const TAG = 'DialogService';
/** ActionMenu 单页最多 6 个按钮，其中 1 个留给"取消" */
const MENU_PAGE_SIZE = 5;
/** 折叠时先展示的项数（其余进"更多"） */
const MENU_VISIBLE_WHEN_OVERFLOW = 4;

/** 确认框选项 */
export interface ConfirmOptions {
  confirmText?: string;
  cancelText?: string;
  /** 危险动作：确认按钮用危险色（删除、清空等） */
  danger?: boolean;
  /** 主题（决定颜色），默认读取 AppStorage 的 theme */
  theme?: string;
}

/** 菜单选项 */
export interface ActionMenuOptions {
  /** 危险项下标（用危险色渲染） */
  dangerIndexes?: number[];
  /** 禁用项下标（仍会显示，但点击返回该下标，由调用方决定忽略） */
  disabledIndexes?: number[];
}

interface PromptActionResult {
  index: number;
}

type MenuButton = promptAction.Button;
/** ActionMenu 的 buttons 是定长元组（1-6 项），动态数组需要显式收窄 */
type MenuButtonTuple = [MenuButton, MenuButton?, MenuButton?, MenuButton?, MenuButton?, MenuButton?];

function currentTheme(): string {
  try {
    return AppStorage.get<string>('theme') ?? 'light';
  } catch (err) {
    return 'light';
  }
}

/**
 * 二选一确认框（Promise 化，取消返回 false）
 * UI 不可用时返回 false，调用方无需再判断上下文
 */
export async function appConfirm(title: string, message: string, options?: ConfirmOptions): Promise<boolean> {
  const uiContext = getAppUiContext();
  if (!uiContext) {
    hilog.warn(DOMAIN, TAG, 'appConfirm skipped: no UIContext');
    return false;
  }
  const theme = options?.theme ?? currentTheme();
  const confirmColor = options?.danger === true ? DesignTokens.danger() : DesignTokens.accent();
  return new Promise<boolean>((resolve: (value: boolean) => void) => {
    try {
      uiContext.getPromptAction().showDialog({
        title,
        message,
        buttons: [
          { text: options?.cancelText ?? t('cancel'), color: DesignTokens.labelSecondary(theme) },
          { text: options?.confirmText ?? t('confirm'), color: confirmColor },
        ],
      }, (err: object, data: PromptActionResult) => {
        resolve(!err && data.index === 1);
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'appConfirm failed: %{public}s', JSON.stringify(err));
      resolve(false);
    }
  });
}

/**
 * 动作菜单（Promise 化，返回原始下标；用户取消返回 -1）
 * items 超过 5 项时自动折叠成「更多…」，返回值仍是原始下标。
 */
export async function appActionMenu(
  title: string,
  items: string[],
  options?: ActionMenuOptions
): Promise<number> {
  if (items.length === 0) {
    return -1;
  }
  // 长按菜单唤起时给一次「中等」触感，与系统原生菜单手感一致
  hapticService.medium();
  return await showMenuPage(title, items, options ?? {}, 0, items.length);
}

/**
 * 展示菜单的一页
 * @param offset 本页第一项在原始数组中的下标
 * @param totalCount 原始数组长度（用于判断是否还有后续页）
 */
async function showMenuPage(
  title: string,
  items: string[],
  options: ActionMenuOptions,
  offset: number,
  totalCount: number
): Promise<number> {
  const uiContext = getAppUiContext();
  if (!uiContext) {
    return -1;
  }
  const theme = currentTheme();
  const remaining = totalCount - offset;
  const overflow = remaining > MENU_PAGE_SIZE;
  const pageSize = overflow ? MENU_VISIBLE_WHEN_OVERFLOW : remaining;
  const dangerIndexes = options.dangerIndexes ?? [];
  const disabledIndexes = options.disabledIndexes ?? [];

  const buttons: MenuButton[] = [];
  for (let i = 0; i < pageSize; i++) {
    const absoluteIndex = offset + i;
    const original = items[absoluteIndex] ?? '';
    const isDanger = dangerIndexes.indexOf(absoluteIndex) >= 0;
    const isDisabled = disabledIndexes.indexOf(absoluteIndex) >= 0;
    const color = isDisabled
      ? DesignTokens.labelTertiary(theme)
      : (isDanger ? DesignTokens.danger() : DesignTokens.labelPrimary(theme));
    buttons.push({ text: original, color });
  }
  if (overflow) {
    buttons.push({ text: t('more_actions'), color: DesignTokens.labelPrimary(theme) });
  }
  // 不再自己追加「取消」：系统 showActionMenu 底部自带一个，
  // 之前两处叠加会出现两个「取消」（真机可见）。系统取消返回 index < 0，仍映射为 -1。

  return new Promise<number>((resolve: (value: number) => void) => {
    try {
      const buttonsTuple = buttons as MenuButtonTuple;
      uiContext.getPromptAction().showActionMenu({ title, buttons: buttonsTuple },
        (err: object, data: PromptActionResult) => {
        if (err || !data || data.index < 0) {
          resolve(-1);
          return;
        }
        const index = data.index;
        if (overflow && index === pageSize) {
          // 「更多…」：展开剩余项，返回值映射回原始下标
          showMenuPage(title, items, options, offset + pageSize, totalCount)
            .then((result: number) => resolve(result))
            .catch(() => resolve(-1));
          return;
        }
        if (index < 0 || index >= pageSize) {
          // 越界（含系统自带的取消项）一律按取消处理
          resolve(-1);
          return;
        }
        resolve(offset + index);
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'appActionMenu failed: %{public}s', JSON.stringify(err));
      resolve(-1);
    }
  });
}

/** 轻提示（UI 不可用时静默忽略） */
export function appToast(message: string, duration: number = 2000): void {
  if (!message || message.length === 0) {
    return;
  }
  const uiContext = getAppUiContext();
  if (!uiContext) {
    hilog.info(DOMAIN, TAG, 'toast (no UI): %{public}s', message);
    return;
  }
  try {
    uiContext.getPromptAction().showToast({ message, duration });
  } catch (err) {
    hilog.info(DOMAIN, TAG, 'toast fallback: %{public}s', message);
  }
}
