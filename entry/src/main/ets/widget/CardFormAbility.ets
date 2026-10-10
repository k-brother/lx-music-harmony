/**
 * 桌面卡片生命周期（卡片进程侧）
 *
 * 与 UI 进程的分工（见 service/CardFormService 头注释）：
 * - 本 Ability 只负责卡片自身生命周期：添加/移除时维护 formId 注册表，
 *   添加/系统刷新时从快照补第一帧（含封面下载，进程间 fd 不能复用）；
 * - 播放过程中的实时推送由 UI 进程负责，这里不重复监听。
 *
 * 对方项目的取舍：onFormEvent 后延迟 300ms 再推，给 UI 进程留出落盘时间，
 * 避免卡片刷新回读到上一帧快照。
 */
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import type { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CardFormPrefs, type CardSnapshot } from './CardFormPrefs';
import { CardFormCover, type CardCoverFd } from '../utils/CardFormCover';
import { CardPushPayload } from '../utils/CardFormPayload';

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
      // 首帧只给文本（同步返回），封面异步下载后补推
      setTimeout((): void => {
        this.pushData(formId, dimension);
      }, 0);
    }
    return formBindingData.createFormBindingData(this.buildPayload(formId, dimension, null));
  }

  onUpdateForm(formId: string): void {
    this.pushData(formId, 0);
  }

  onFormEvent(formId: string): void {
    setTimeout((): void => {
      this.pushData(formId, 0);
    }, EVENT_PUSH_DELAY_MS);
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
      const image: CardCoverFd | null = await CardFormCover.prepare(this.context.tempDir, cover);
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
}
