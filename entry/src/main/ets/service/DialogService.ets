/**
 * 对话框 / 菜单 / 轻提示统一入口
 *
 * 之前每个页面各写一遍：
 *   - 系统居中确认弹窗（标题/按钮居中，和平台观感不统一）
 *   - 系统动作菜单（按钮数量受限，超过 6 个要自己拆二级菜单）
 *   - 轻提示 + try/catch
 * 现在统一到这里，页面只关心「问一句」或「列一组动作」：
 *   const ok = await appConfirm('删除', '删除后不可恢复');
 *   const index = await appActionMenu('歌曲名', ['播放','下一首播放','收藏','分享','不喜欢'], [4]);
 *   appToast('已添加');
 *
 * 菜单与确认框都渲染成同一种底部面板（components/ui/MenuSheet）：
 * 每行「左图标 + 右文案」、左对齐、行高一致，危险项用危险色。
 * `appActionMenu` 的返回值始终是**原始数组下标**，调用方沿用原有分支即可。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { t } from './LocalizationService';
import { getAppUiContext } from './UiContext';
import { DesignTokens } from '../theme/DesignTokens';
import { hapticService } from './HapticService';
import { sheetService, type SheetRow } from './SheetService';
import { menuIconFor } from '../utils/MenuIcons';

const DOMAIN = 0x0005;
const TAG = 'DialogService';

/** showDialog 回调里的下标结果 */
interface PromptActionResult {
  index: number;
}

/** 系统对话框需要的主题名（只用于取颜色） */
function currentThemeName(): string {
  try {
    return AppStorage.get<string>('theme') ?? 'light';
  } catch (err) {
    return 'light';
  }
}
/** 确认框选项 */
export interface ConfirmOptions {
  confirmText?: string;
  cancelText?: string;
  /** 危险动作：确认行用危险色 + 删除图标（删除、清空等） */
  danger?: boolean;
}

/** 菜单选项 */
export interface ActionMenuOptions {
  /** 危险项下标（用危险色渲染） */
  dangerIndexes?: number[];
  /** 禁用项下标（仍会显示，但点击返回该下标，由调用方决定忽略） */
  disabledIndexes?: number[];
}

/**
 * 二选一确认框（Promise 化，取消返回 false）
 *
 * 视觉上不再用系统居中弹窗（标题/按钮都居中，和信息类菜单不是一套观感），
 * 改成与动作菜单同源的底部面板：每行「左图标 + 右文案」、左对齐，
 * 确认行在危险动作时用危险色 + 垃圾桶图标，取消行固定在最下面。
 * UI 不可用时返回 false，调用方无需再判断上下文
 */
export async function appConfirm(title: string, message: string, options?: ConfirmOptions): Promise<boolean> {
  const danger: boolean = options?.danger === true;
  const rows: SheetRow[] = [
    {
      label: options?.confirmText ?? t('confirm'),
      icon: danger ? $r('sys.symbol.trash') : $r('sys.symbol.checkmark_circle'),
      danger: danger,
      disabled: false,
      index: 0,
    },
  ];
  const picked: number = await sheetService.confirm(title, message, rows);
  // 点确认行 = 0；右上角关闭/点遮罩 = -1（取消）
  return picked === 0;
}

/**
 * 单按钮提示框（只有「知道了」）。
 * 用于「插件加载失败」这类只需告知、不需要选择的场景，
 * 避免各页面自己拼系统 dialog。
 *
 * 同样走底部面板：与菜单/确认框同一套「左图标 + 右文案」观感，不再用居中弹窗。
 */
export async function appAlert(title: string, message: string, options?: ConfirmOptions): Promise<void> {
  const rows: SheetRow[] = [
    {
      label: options?.confirmText ?? t('got_it'),
      icon: $r('sys.symbol.checkmark_circle'),
      danger: false,
      disabled: false,
      index: 0,
    },
  ];
  // 面板不可用（例如页面已销毁）时 sheetService 会直接返回 -1，
  // 内容同时已经进日志仓库，便于「运行日志」排查。
  await sheetService.confirm(title, message, rows);
  hilog.info(DOMAIN, TAG, 'appAlert: %{public}s - %{public}s', title, message);
}

/**
 * 系统居中确认框（给「不适合底部面板」的场景用）。
 *
 * 退出应用这类「系统级、与页面内容无关」的确认，用系统弹窗更符合预期
 * （底部面板看起来像页面内的操作菜单）；其余业务确认仍走面板，
 * 保持「每行左图标 + 右文案」的统一观感。
 */
export async function appConfirmSystem(
  title: string, message: string, options?: ConfirmOptions
): Promise<boolean> {
  const uiContext = getAppUiContext();
  if (!uiContext) {
    hilog.warn(DOMAIN, TAG, 'appConfirmSystem skipped: no UIContext');
    return false;
  }
  const confirmColor: string = options?.danger === true ? DesignTokens.danger() : DesignTokens.accent();
  return new Promise<boolean>((resolve: (value: boolean) => void) => {
    try {
      uiContext.getPromptAction().showDialog({
        title,
        message,
        buttons: [
          { text: options?.cancelText ?? t('cancel'), color: DesignTokens.labelSecondary(currentThemeName()) },
          { text: options?.confirmText ?? t('confirm'), color: confirmColor },
        ],
      }, (err: object, data: PromptActionResult) => {
        resolve(!err && data.index === 1);
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'appConfirmSystem failed: %{public}s', JSON.stringify(err));
      resolve(false);
    }
  });
}

/**
 * 动作菜单（Promise 化，返回原始下标；用户取消返回 -1）
 *
 * 统一走底部面板 MenuSheet：每行「左图标 + 右文案」、左对齐，行高一致，
 * 项数不再受系统 showActionMenu 的 6 项限制，因此也不需要「更多…」折叠。
 * 传入的 items 顺序即返回值下标，调用方沿用原有分支即可。
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

  const dangerIndexes: number[] = options?.dangerIndexes ?? [];
  const disabledIndexes: number[] = options?.disabledIndexes ?? [];
  const rows: SheetRow[] = [];
  for (let i = 0; i < items.length; i++) {
    const label: string = items[i] ?? '';
    const row: SheetRow = {
      label,
      icon: menuIconFor(label),
      danger: dangerIndexes.indexOf(i) >= 0,
      disabled: disabledIndexes.indexOf(i) >= 0,
      index: i,
    };
    rows.push(row);
  }
  return await sheetService.menu(title, rows);
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
