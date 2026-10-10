/**
 * 桌面卡片跨进程契约编解码（叶子文件，UI 进程与卡片进程共用）
 *
 * formIds 列表的 JSON 形状原先在 `service/CardFormService`（读）与
 * `widget/CardFormPrefs`（读写）各写一遍，含同一段"兼容旧 string[]"逻辑，
 * 改一处漏一处就会两边口径漂移。这里收口成一组纯函数，调用方只负责 IO 与日志。
 */
import type { RegisteredCard } from './CardFormKeys';

/** 旧格式（string[] 只存 id）与缺字段时的默认尺寸档：2*4 = 3 */
const DEFAULT_DIMENSION: number = 3;

/**
 * JSON 字符串 → 卡片列表：兼容旧格式、按 id 去重、过滤非法项。
 * 解析异常不在这里吞掉，由调用方 catch 后决定兜底值（保持"纯函数不记日志"）。
 */
export function decodeRegisteredCards(raw: string): RegisteredCard[] {
  const parsed: Object[] = JSON.parse(raw.length > 0 ? raw : '[]') as Object[];
  const out: RegisteredCard[] = [];
  for (const item of parsed) {
    // 兼容旧格式 string[]（只存 id）：按 2*4 处理
    if (typeof item === 'string') {
      const id: string = item as string;
      if (id.length > 0 && out.findIndex((c: RegisteredCard): boolean => c.id === id) < 0) {
        out.push({ id: id, dimension: DEFAULT_DIMENSION });
      }
      continue;
    }
    const rec: RegisteredCard = item as RegisteredCard;
    if (typeof rec.id === 'string' && rec.id.length > 0 &&
        out.findIndex((c: RegisteredCard): boolean => c.id === rec.id) < 0) {
      out.push({ id: rec.id, dimension: typeof rec.dimension === 'number' ? rec.dimension : DEFAULT_DIMENSION });
    }
  }
  return out;
}

/** 卡片列表 → JSON 字符串 */
export function encodeRegisteredCards(cards: RegisteredCard[]): string {
  return JSON.stringify(cards);
}
