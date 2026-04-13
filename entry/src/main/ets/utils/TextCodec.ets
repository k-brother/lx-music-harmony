/**
 * UTF-8 编解码门面（替代各处分散的 TextEncoder/TextDecoder，便于跟随 SDK 升级）
 */
import util from '@ohos.util';

export function utf8Encode(text: string): Uint8Array {
  return new util.TextEncoder().encodeInto(text);
}

export function utf8Decode(bytes: Uint8Array, label: string = 'utf-8'): string {
  return new util.TextDecoder(label).decodeToString(bytes);
}
