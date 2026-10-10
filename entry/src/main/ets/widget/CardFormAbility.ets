/**
 * 桌面卡片生命周期（卡片进程侧）
 *
 * 与 UI 进程的分工（官方推荐模型：数据由 provider 进程推）：
 * - 本 Ability 只负责卡片自身生命周期：添加/移除时维护 formId 注册表，
 *   添加/系统刷新时从快照补第一帧；
 * - **不做网络 IO**：封面只认本地路径（CardFormCover.prepareLocal）。官方要求
 *   FormExtensionAbility 轻量、快速返回，网络下载留给 UI 进程；
 * - 每帧推完紧接着 publish CARD_REFRESH_EVENT，请 UI 进程把「最新一帧（含封面图）」
 *   整帧推过来 —— 这样扩展进程既不需要下载，也不会长期显示旧数据。
 * - 播放过程中的实时推送本来由 UI 进程负责，这里不重复监听。
 */
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import type { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import type { BusinessError } from '@kit.BasicServicesKit';
import { CardFormPrefs, type CardSnapshot } from './CardFormPrefs';
import { CardFormCover, type CardCoverFd } from '../utils/CardFormCover';
import { CardPushPayload } from '../utils/CardFormPayload';
import { CARD_REFRESH_EVENT } from '../utils/CardFormKeys';

const TAG = 'CardFormAbility';
const DOMAIN = 0x0003;
const EVENT_PUSH_DELAY_MS: number = 300;

/** 从 want 参数解析卡片身份；缺 IDENTITY_KEY 视为无效添加 */
function parseFormParam<T>(params: Record<string, Object> | undefined, key: string): T | null {
  if (params === undefined) {
    return null;
  }
  const value: Object | undefined = params[key];
  if (value === undefined || value === null) {
    return null;
  }
  return value as T;
}

export default class CardFormAbility extends FormExtensionAbility {
  private readonly prefs: CardFormPrefs = new CardFormPrefs();

  onCreate(): void {
    this.prefs.attach(this.context);
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    const params: Record<string, Object> | undefined = want.parameters;
    const formId: string = parseFormParam<string>(params, formInfo.FormParam.IDENTITY_KEY) ?? '';
    const dimension: number = parseFormParam<number>(params, formInfo.FormParam.DIMENSION_KEY) ??
      formInfo.FormDimension.Dimension_2_2;
    if (formId.length > 0) {
      this.prefs.registerFormId(this.context, formId, dimension);
      // 首帧只给本进程能拿到的内容（同步返回：本地封面 + 文本）；
      // 网络封面与最新一句由 UI 进程补推，所以紧接着发一次刷新请求
      setTimeout((): void => {
        this.pushData(formId, dimension);
      }, 0);
      this.requestProviderRefresh();
    }
    return formBindingData.createFormBindingData(this.buildPayload(formId, dimension, null));
  }

  onUpdateForm(formId: string): void {
    this.pushData(formId, 0);
    this.requestProviderRefresh();
  }

  onFormEvent(formId: string): void {
    setTimeout((): void => {
      this.pushData(formId, 0);
    }, EVENT_PUSH_DELAY_MS);
    this.requestProviderRefresh();
  }

  onRemoveForm(formId: string): void {
    this.prefs.unregisterFormId(this.context, formId);
  }

  private buildPayload(formId: string, dimension: number,
    snapshot: CardSnapshot | null): CardPushPayload {
    const payload: CardPushPayload = new CardPushPayload();
    if (snapshot !== null) {
      payload.title = snapshot.title;
      payload.singer = snapshot.singer;
      payload.playing = snapshot.playing;
      payload.lyric = snapshot.lyric;
    }
    payload.formId = formId;
    payload.dimension = dimension;
    return payload;
  }

  private async pushData(formId: string, dimension: number): Promise<void> {
    const snapshot: CardSnapshot | null = this.prefs.readSnapshot(this.context);
    const payload: CardPushPayload = this.buildPayload(formId, dimension, snapshot);
    const cover: string = snapshot !== null ? snapshot.cover : '';
    if (cover.length > 0) {
      // 只认本地封面：网络封面不在扩展进程下载（见文件头「与 UI 进程的分工」）
      const image: CardCoverFd | null = CardFormCover.prepareLocal(cover);
      if (image !== null && image.fd >= 0) {
        payload.imgName = image.name;
        payload.formImages[image.name] = image.fd;
      }
    }
    try {
      const data: formBindingData.FormBindingData = formBindingData.createFormBindingData(payload);
      await formProvider.updateForm(formId, data);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'updateForm %{public}s 失败: %{public}s', formId,
        err instanceof Error ? err.message : JSON.stringify(err));
    }
  }

  /**
   * 请求 UI 进程补推一帧。
   * commonEvent 是跨进程的官方通道，本仓已在锁屏实况窗链路验证过同一套写法；
   * 失败只记日志：本进程那一帧已经渲染，只是少了封面/最新一句。
   */
  private requestProviderRefresh(): void {
    try {
      const options: commonEventManager.CommonEventPublishData = {};
      commonEventManager.publish(CARD_REFRESH_EVENT, options, (err: BusinessError): void => {
        if (err) {
          hilog.warn(DOMAIN, TAG, 'publish refresh request failed: %{public}s', JSON.stringify(err));
        }
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'requestProviderRefresh failed: %{public}s', JSON.stringify(err));
    }
  }
}
