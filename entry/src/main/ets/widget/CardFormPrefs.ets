/**
 * 卡片进程的跨进程 preferences 助手
 *
 * FormExtensionAbility 运行在独立进程，preferences 有进程内缓存：UI 进程写入的
 * 快照不会自动对本进程可见。每次读取前先 removePreferencesFromCacheSync 强制重读文件，
 * 但刷新做 2s 节流 —— 对方项目用 60s，导致「新卡片一分钟内拿不到数据」。
 *
 * 键名契约见 utils/CardFormKeys；写入方划分：
 * - 本进程写 CARD_FORM_IDS_KEY（卡片添加/移除时注册 formId）；
 * - 只读 CARD_SNAPSHOT_KEY（UI 进程 CardFormService 维护的快照）。
 */
import { preferences } from '@kit.ArkData';
import type { Context } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CARD_FORM_IDS_KEY, CARD_SNAPSHOT_KEY, type RegisteredCard } from '../utils/CardFormKeys';
import { APP_PREFERENCES_NAME } from '../utils/PreferenceNames';
import { decodeRegisteredCards, encodeRegisteredCards } from '../utils/CardFormCodec';

const TAG = 'CardFormPrefs';
const DOMAIN = 0x0003;
const REFRESH_THROTTLE_MS: number = 2000;

/** UI 进程落盘的播放快照（字段与 service/CardFormService 的 CardSnapshot 一致） */
export interface CardSnapshot {
  title: string;
  singer: string;
  cover: string;
  playing: boolean;
  lyric: string;
}

export class CardFormPrefs {
  private store: preferences.Preferences | null = null;
  private lastRefreshAt: number = 0;

  attach(context: Context): void {
    this.refresh(context);
  }

  /** 丢弃进程内缓存并重新打开文件（2s 节流）；任何读取前调用 */
  refresh(context: Context): void {
    const now: number = Date.now();
    if (now - this.lastRefreshAt < REFRESH_THROTTLE_MS && this.store !== null) {
      return;
    }
    this.lastRefreshAt = now;
    try {
      preferences.removePreferencesFromCacheSync(context, { name: APP_PREFERENCES_NAME });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '清除 preferences 缓存失败: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
    }
    try {
      this.store = preferences.getPreferencesSync(context, { name: APP_PREFERENCES_NAME });
    } catch (err) {
      this.store = null;
      hilog.warn(DOMAIN, TAG, '打开 preferences 失败: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
    }
  }

  /** 读 UI 进程的播放快照；无数据或解析失败返回 null */
  readSnapshot(context: Context): CardSnapshot | null {
    this.refresh(context);
    if (this.store === null) {
      return null;
    }
    let raw: string = '';
    try {
      raw = this.store.getSync(CARD_SNAPSHOT_KEY, '') as string;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '读快照失败: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      return null;
    }
    if (raw.length === 0) {
      return null;
    }
    try {
      return JSON.parse(raw) as CardSnapshot;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '快照解析失败: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      return null;
    }
  }

  /** 注册卡片（去重，dimension 变化时更新） */
  registerFormId(context: Context, formId: string, dimension: number): void {
    if (formId.length === 0) {
      return;
    }
    const list: RegisteredCard[] = this.readRegisteredCards(context);
    for (const card of list) {
      if (card.id === formId) {
        if (card.dimension !== dimension) {
          card.dimension = dimension;
          this.writeRegisteredCards(context, list);
        }
        return;
      }
    }
    list.push({ id: formId, dimension: dimension });
    this.writeRegisteredCards(context, list);
  }

  /** 移除卡片 */
  unregisterFormId(context: Context, formId: string): void {
    const list: RegisteredCard[] = this.readRegisteredCards(context);
    const kept: RegisteredCard[] = [];
    for (const card of list) {
      if (card.id !== formId) {
        kept.push(card);
      }
    }
    if (kept.length === list.length) {
      return;
    }
    this.writeRegisteredCards(context, kept);
  }

  private readRegisteredCards(context: Context): RegisteredCard[] {
    this.refresh(context);
    if (this.store === null) {
      return [];
    }
    try {
      const raw: string = this.store.getSync(CARD_FORM_IDS_KEY, '[]') as string;
      return decodeRegisteredCards(raw);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '读 formIds 失败: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
      return [];
    }
  }

  private writeRegisteredCards(context: Context, list: RegisteredCard[]): void {
    // 写前强制刷新：避免拿旧缓存覆盖 UI 进程刚注册的其它卡片
    this.lastRefreshAt = 0;
    this.refresh(context);
    if (this.store === null) {
      return;
    }
    try {
      this.store.putSync(CARD_FORM_IDS_KEY, encodeRegisteredCards(list));
      this.store.flush();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, '写 formIds 失败: %{public}s',
        err instanceof Error ? err.message : JSON.stringify(err));
    }
  }
}
