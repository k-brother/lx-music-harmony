/**
 * 桌面卡片跨进程桥接契约（叶子文件，service 与 widget 两个进程共用）
 *
 * 服务卡片由 CardFormAbility 承载、运行在独立进程，与 UIAbility 进程之间只靠
 * preferences 文件通信。这里的键名与文件名是两个进程的唯一契约：
 * - UI 进程（CardFormService）写 CARD_SNAPSHOT_KEY，读 CARD_FORM_IDS_KEY；
 * - 卡片进程（CardFormPrefs）写 CARD_FORM_IDS_KEY，读 CARD_SNAPSHOT_KEY。
 * 任何一边要改值，必须两边同时升级，不允许单方面改。
 */
export const CARD_PREFERENCES_NAME: string = 'lx_music_preferences';
export const CARD_FORM_IDS_KEY: string = 'card.formIds';
export const CARD_SNAPSHOT_KEY: string = 'card.snapshot';

/** 一张已注册卡片的身份（CARD_FORM_IDS_KEY 的值形状；dimension 供 UI 进程按尺寸推送） */
export interface RegisteredCard {
  id: string;
  dimension: number;
}
