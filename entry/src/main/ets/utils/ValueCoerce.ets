/**
 * 持久化数据 -> UI 字段的收敛
 *
 * 本地曲库 / 我喜欢列表都是把 JSON 存进 Preferences，跨版本读过老数据时字段可能缺失或
 * 类型不同（数字存成了字符串、字段名变了）。这些值直接喂给 `@Prop`（ArkUI 会校验类型）
 * 或者参与 `Math.*` 计算时会抛异常，真机上表现为「一进页面就闪退」。
 * 统一在这里收敛：字符给空串、数字给 0，不让脏数据走到 UI 层。
 */

/** 一律转成字符串（null/undefined/空值回落 fallback） */
export function asText(value: string | number | boolean | undefined | null, fallback: string = ''): string {
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value === 'string') {
    return value.length > 0 ? value : fallback;
  }
  return `${value}`;
}

/** 一律转成有限数字（NaN / 非法字符串回落 fallback） */
export function asNumber(value: number | string | undefined | null, fallback: number = 0): number {
  if (typeof value === 'number') {
    return isFinite(value) ? value : fallback;
  }
  if (typeof value === 'string') {
    const parsed: number = Number(value);
    return isFinite(parsed) ? parsed : fallback;
  }
  return fallback;
}
