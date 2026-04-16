/**
 * 全局 WebSocket 工厂与负载解析（业务勿直接 import @ohos.net.webSocket，便于统一升级与埋点）
 */
import webSocket from '@ohos.net.webSocket';
import hilog from '@ohos.hilog';
import { utf8Decode } from '../../../utils/TextCodec';

const TAG = 'WebSocket';
const DOMAIN = 0x0001;

export function createLxWebSocket(): webSocket.WebSocket {
  return webSocket.createWebSocket();
}

/** 将 WS 帧解析为 UTF-8 文本（兼容 string / ArrayBuffer） */
export function decodeWsPayload(data: string | ArrayBuffer): string {
  if (typeof data === 'string') {
    return data;
  }
  const uint8Array = new Uint8Array(data as ArrayBuffer);
  try {
    return utf8Decode(uint8Array);
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'decodeWsPayload utf8Decode failed: %{public}s', (e as Error)?.message);
    let messageStr = '';
    for (let i = 0; i < uint8Array.length; i++) {
      messageStr += String.fromCharCode(uint8Array[i]);
    }
    return messageStr;
  }
}
