/**
 * 桌面卡片 updateForm 负载（叶子文件，UI 进程与卡片进程共用）
 *
 * 字段名就是卡片页 @LocalStorageProp 的绑定键，两边进程各自构造同形状实例：
 * - UI 进程（CardFormService）：切歌/播放态/歌词变化时推送，per-form 填 formId/dimension；
 * - 卡片进程（CardFormAbility）：卡片添加/系统刷新时补第一帧。
 * imgName 对应 memory://imgName 图片，fd 由 formImages 映射保活，见 utils/CardFormCover。
 */
export class CardPushPayload {
  title: string = '';
  singer: string = '';
  playing: boolean = false;
  lyric: string = '';
  imgName: string = '';
  formImages: Record<string, number> = {};
  formId: string = '';
  dimension: number = 3;
}
