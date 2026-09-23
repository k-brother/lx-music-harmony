/**
 * 事件系统
 * 应用内部事件总线
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'EventBus';
const DOMAIN = 0x0006;

// 事件类型接口
interface EventTypesInterface {
  SEARCH_REQUEST: string;
  LIST_UPDATED: string;
  SETTING_CHANGED: string;
  PLAYBACK_ERROR: string;
}

/**
 * 事件类型
 *
 * 只保留真正有人在用的事件：播放状态/进度/歌曲信息的跨模块通知已经由
 * PlayerService 自己的订阅接口（onStatusChange 等）承担，这里不再重复一份；
 * 主题深浅色由 ThemeService 的监听器回调，语言变更直接重渲染。
 */
export const EventTypes: EventTypesInterface = {
  /** 其他页面请求首页发起搜索（如歌单里的「查看歌手/专辑」） */
  SEARCH_REQUEST: 'search:request',
  LIST_UPDATED: 'list:updated',
  SETTING_CHANGED: 'setting:changed',
  /** 播放期错误（解码/网络等）：界面据此提示用户（如「已跳过这首歌」） */
  PLAYBACK_ERROR: 'playback:error',
};

// 事件监听器类型
type EventListener = (data?: Object) => void;

// 事件数据接口





interface ListUpdatedData {
  listId: string;
}


export interface SettingChangedData {
  key: string;
}



// 事件总线类（内部使用）
class EventBusImpl {
  private listeners: Map<string, EventListener[]> = new Map();

  /**
   * 订阅事件
   */
  on(event: string, listener: EventListener): () => void {
    let eventListeners = this.listeners.get(event);
    if (!eventListeners) {
      eventListeners = [];
      this.listeners.set(event, eventListeners);
    }
    eventListeners.push(listener);

    // 返回取消订阅函数
    return () => {
      this.off(event, listener);
    };
  }

  /**
   * 订阅一次性事件
   */
  once(event: string, listener: EventListener): () => void {
    const wrapper: EventListener = (data?: Object) => {
      listener(data);
      this.off(event, wrapper);
    };
    return this.on(event, wrapper);
  }

  /**
   * 取消订阅
   */
  off(event: string, listener: EventListener): void {
    const eventListeners = this.listeners.get(event);
    if (eventListeners) {
      const index = eventListeners.indexOf(listener);
      if (index > -1) {
        eventListeners.splice(index, 1);
      }
      if (eventListeners.length === 0) {
        this.listeners.delete(event);
      }
    }
  }

  /**
   * 触发事件
   */
  emit(event: string, data?: Object): void {
    const eventListeners = this.listeners.get(event);
    if (eventListeners) {
      // 复制数组避免监听器中添加/移除导致的问题
      const listenerCount = eventListeners.length;
      for (let i = 0; i < listenerCount; i++) {
        try {
          eventListeners[i](data);
        } catch (err) {
          hilog.error(DOMAIN, TAG, 'Event listener error: %{public}s', JSON.stringify(err));
        }
      }
    }
  }

  /**
   * 清除所有监听器
   */
  clear(): void {
    this.listeners.clear();
  }

}

// 单例（内部使用）
const eventBusImpl = new EventBusImpl();

/**
 * 订阅事件
 */
export function on(event: string, listener: EventListener): () => void {
  return eventBusImpl.on(event, listener);
}

/**
 * 订阅一次性事件
 */
export function once(event: string, listener: EventListener): () => void {
  return eventBusImpl.once(event, listener);
}

/**
 * 取消订阅
 */
export function off(event: string, listener: EventListener): void {
  eventBusImpl.off(event, listener);
}

/**
 * 触发事件
 */
export function emit(event: string, data?: Object): void {
  eventBusImpl.emit(event, data);
}

/**
 * 清除所有监听器
 */
export function clear(): void {
  eventBusImpl.clear();
}

// ============ 快捷方法 ============






/** 请求首页发起搜索（其他页面「查看歌手/专辑」用） */
export interface SearchRequestData {
  keyword: string;
}

export function emitSearchRequest(keyword: string): void {
  const data: SearchRequestData = { keyword: keyword };
  emit(EventTypes.SEARCH_REQUEST, data);
}

/**
 * 列表更新
 */
export function emitListUpdated(listId: string): void {
  const data: ListUpdatedData = { listId: listId };
  emit(EventTypes.LIST_UPDATED, data);
}


/**
 * 设置变化（key 为变更的设置项，'all' 表示整体初始化完成）
 */
export function emitSettingChanged(key: string): void {
  const data: SettingChangedData = { key: key };
  emit(EventTypes.SETTING_CHANGED, data);
}

/** 播放错误数据：被跳过的歌曲名 + 是否已跳过（否则是停下来） */
export interface PlaybackErrorData {
  title: string;
  skipped: boolean;
}

/**
 * 播放出错（由 PlayerService 在播放器报错后发出）。
 * 界面负责提示，播放器/服务不直接弹 toast，保持分层。
 */
export function emitPlaybackError(title: string, skipped: boolean): void {
  const data: PlaybackErrorData = { title: title, skipped: skipped };
  emit(EventTypes.PLAYBACK_ERROR, data);
}



// 事件总线门面（供需要「一个对象拿到全部事件能力」的地方使用）
export interface EventBusInterface {
  EventTypes: EventTypesInterface;
  on: (event: string, callback: EventListener) => () => void;
  once: (event: string, callback: EventListener) => () => void;
  off: (event: string, callback: EventListener) => void;
  emit: (event: string, data?: Object) => void;
  clear: () => void;
  emitListUpdated: (listId: string) => void;
  emitSearchRequest: (keyword: string) => void;
  emitSettingChanged: (key: string) => void;
  emitPlaybackError: (title: string, skipped: boolean) => void;
}

// 导出事件总线
const eventBus: EventBusInterface = {
  EventTypes,
  on,
  once,
  off,
  emit,
  clear,
  emitListUpdated,
  emitSearchRequest,
  emitSettingChanged,
  emitPlaybackError,
};

export default eventBus;
