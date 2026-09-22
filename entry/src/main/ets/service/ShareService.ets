/**
 * 分享服务
 *
 * 对齐安卓版的 `common.shareType`：
 * - `system`：拉起系统分享（HarmonyOS 26 的 `ohos.want.action.sendToData`
 *   + `contentTitle / shareAbstract / shareUrl` 参数字段，见 wantConstant.Params）。
 *   当前 SDK 没有 ShareKit（无 `systemShare.ShareController`），所以这里用 Want 通道
 *   尽力拉起系统分享；设备上没有可分享目标时自动回退为「复制到剪贴板」并给出提示，
 *   保证任何机型上按钮都可用。
 * - `clipboard`：只复制文本（安卓版同名选项）。
 */
import hilog from '@ohos.hilog';
import pasteboard from '@ohos.pasteboard';
import { common, wantConstant } from '@kit.AbilityKit';
import { settingsService } from './SettingsService';
import type { ShareType } from './SettingsService';

const TAG = 'ShareService';
const DOMAIN = 0x0005;

export type { ShareType };

/** 分享结果：走系统分享 / 回退复制 / 彻底失败 */
export type ShareResult = 'system' | 'clipboard' | 'failed';

/** 写入系统剪贴板（同步，失败返回 false） */
export function copyToClipboard(text: string): boolean {
  try {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setDataSync(data);
    return true;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'copyToClipboard failed: %{public}s', JSON.stringify(err));
    return false;
  }
}

/** 直接复制文本（不做系统分享），供"复制"类操作复用 */
export async function copyText(text: string): Promise<boolean> {
  return copyToClipboard(text);
}

/**
 * 按设置分享文本
 * @param context UIAbility 上下文（用于 startAbility）
 * @param text 分享正文
 * @param title 分享面板标题（可空）
 * @param url 附带链接（可空，安卓版分享会带上歌曲详情页地址）
 */
export async function shareText(
  context: common.UIAbilityContext,
  text: string,
  title: string = '',
  url: string = ''
): Promise<ShareResult> {
  if (settingsService.get().shareType === 'system') {
    const started = await trySystemShare(context, text, title, url);
    if (started) {
      return 'system';
    }
    hilog.info(DOMAIN, TAG, 'No system share target, fallback to clipboard');
  }
  return copyToClipboard(text) ? 'clipboard' : 'failed';
}

/** 尽力拉起系统分享；返回是否成功拉起 */
async function trySystemShare(
  context: common.UIAbilityContext,
  text: string,
  title: string,
  url: string
): Promise<boolean> {
  try {
    const parameters: Record<string, Object> = {};
    parameters[wantConstant.Params.SHARE_ABSTRACT_KEY] = text;
    if (title.length > 0) {
      parameters[wantConstant.Params.CONTENT_TITLE_KEY] = title;
    }
    if (url.length > 0) {
      parameters[wantConstant.Params.SHARE_URL_KEY] = url;
    }
    await context.startAbility({
      action: wantConstant.Action.ACTION_SEND_TO_DATA,
      type: 'text/plain',
      parameters,
    });
    return true;
  } catch (err) {
    hilog.info(DOMAIN, TAG, 'startAbility(SystemShare) failed: %{public}s', JSON.stringify(err));
    return false;
  }
}
