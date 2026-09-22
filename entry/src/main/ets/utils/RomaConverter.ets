/**
 * 中文罗马音（拼音）转换
 *
 * 直接用系统 ICU 转写能力（@ohos.i18n 的 Transliterator），
 * 不引入自带拼音表，避免几万字的映射数据与体积开销。
 * 设备不支持该转写时返回空串，由调用方降级为不显示罗马音。
 */
import i18n from '@ohos.i18n';
import hilog from '@ohos.hilog';

const TAG = 'RomaConverter';
const DOMAIN = 0x0006;

let translator: i18n.Transliterator | null = null;
let initialized: boolean = false;

function ensureTranslator(): i18n.Transliterator | null {
  if (initialized) {
    return translator;
  }
  initialized = true;
  // 先试带 ASCII 化的组合（输出纯拼音），失败再退回 Han-Latin
  const ids: string[] = ['Han-Latin; Latin-ASCII', 'Han-Latin'];
  for (let i = 0; i < ids.length; i++) {
    try {
      translator = i18n.Transliterator.getInstance(ids[i]);
      hilog.info(DOMAIN, TAG, 'Transliterator ready: %{public}s', ids[i]);
      return translator;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'Transliterator %{public}s unavailable: %{public}s',
        ids[i], err instanceof Error ? err.message : JSON.stringify(err));
    }
  }
  return null;
}

/**
 * 把中文文本转成拼音（罗马音）。
 * 转换不可用时返回空串。
 */
export function toRoma(text: string): string {
  const source = (text ?? '').trim();
  if (source.length === 0) {
    return '';
  }
  const instance = ensureTranslator();
  if (!instance) {
    return '';
  }
  try {
    return instance.transform(source);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'transform failed: %{public}s',
      err instanceof Error ? err.message : JSON.stringify(err));
    return '';
  }
}

/** 罗马音当前是否可用（设置页据此决定是否显示开关） */
export function isRomaSupported(): boolean {
  return ensureTranslator() !== null;
}
