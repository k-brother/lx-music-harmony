/**
 * 事件系统
 * 应用内部事件总线
 */
import hilog from '@ohos.hilog';

const TAG = 'EventBus';
const DOMAIN = 0x0006;

// 事件类型接口
interface EventTypesInterface {
  PLAY_STATE_CHANGED: string;
  PLAY_PROGRESS_CHANGED: string;
  PLAY_MUSIC_CHANGED: string;
  PLAY_LIST_CHANGED: string;
  SEARCH_STARTED: string;
  SEARCH_COMPLETED: string;
  SEARCH_CLEARED: string;
  LIST_UPDATED: string;
  LIST_MUSIC_ADDED: string;
  LIST_MUSIC_REMOVED: string;
  SETTING_CHANGED: string;
  THEME_CHANGED: string;
  ERROR_OCCURRED: string;
  TOAST_SHOW: string;
}

// 事件类型
export const EventTypes: EventTypesInterface = {
  // 播放事件
  PLAY_STATE_CHANGED: 'play:stateChanged',
  PLAY_PROGRESS_CHANGED: 'play:progressChanged',
  PLAY_MUSIC_CHANGED: 'play:musicChanged',
  PLAY_LIST_CHANGED: 'play:listChanged',

  // 搜索事件
  SEARCH_STARTED: 'search:started',
  SEARCH_COMPLETED: 'search:completed',
  SEARCH_CLEARED: 'search:cleared',

  // 列表事件
  LIST_UPDATED: 'list:updated',
  LIST_MUSIC_ADDED: 'list:musicAdded',
  LIST_MUSIC_REMOVED: 'list:musicRemoved',

  // 设置事件
  SETTING_CHANGED: 'setting:changed',
  THEME_CHANGED: 'theme:changed',

  // 全局事件
  ERROR_OCCURRED: 'app:error',
  TOAST_SHOW: 'app:toast',
};

// 事件监听器类型
type EventListener = (data?: Object) => void;

// 事件数据接口
interface PlayStateChangedData {
  isPlay: boolean;
}

interface PlayProgressChangedData {
  nowPlayTime: number;
  maxPlayTime: number;
  progress: number;
}

interface PlayMusicChangedData {
  id: string;
  name: string;
  singer: string;
  album: string;
  pic: string;
}

interface SearchStartedData {
  keyword: string;
}

interface SearchCompletedData {
  results: Object[];
}

interface ListUpdatedData {
  listId: string;
}

interface ThemeChangedData {
  isDark: boolean;
}

interface ErrorOccurredData {
  message: string;
}

interface ToastShowData {
  message: string;
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

  /**
   * 清除特定事件的所有监听器
   */
  clearEvent(event: string): void {
    this.listeners.delete(event);
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

/**
 * 播放状态变化
 */
export function emitPlayStateChanged(isPlay: boolean): void {
  const data: PlayStateChangedData = { isPlay: isPlay };
  emit(EventTypes.PLAY_STATE_CHANGED, data);
}

/**
 * 播放进度变化
 */
export function emitPlayProgressChanged(progress: PlayProgressChangedData): void {
  emit(EventTypes.PLAY_PROGRESS_CHANGED, progress);
}

/**
 * 播放音乐变化
 */
export function emitPlayMusicChanged(music: PlayMusicChangedData): void {
  emit(EventTypes.PLAY_MUSIC_CHANGED, music);
}

/**
 * 搜索开始
 */
export function emitSearchStarted(keyword: string): void {
  const data: SearchStartedData = { keyword: keyword };
  emit(EventTypes.SEARCH_STARTED, data);
}

/**
 * 搜索完成
 */
export function emitSearchCompleted(results: Object[]): void {
  const data: SearchCompletedData = { results: results };
  emit(EventTypes.SEARCH_COMPLETED, data);
}

/**
 * 列表更新
 */
export function emitListUpdated(listId: string): void {
  const data: ListUpdatedData = { listId: listId };
  emit(EventTypes.LIST_UPDATED, data);
}

/**
 * 主题变化
 */
export function emitThemeChanged(isDark: boolean): void {
  const data: ThemeChangedData = { isDark: isDark };
  emit(EventTypes.THEME_CHANGED, data);
}

/**
 * 显示错误
 */
export function emitError(message: string): void {
  const data: ErrorOccurredData = { message: message };
  emit(EventTypes.ERROR_OCCURRED, data);
}

/**
 * 显示提示
 */
export function emitToast(message: string): void {
  const data: ToastShowData = { message: message };
  emit(EventTypes.TOAST_SHOW, data);
}

// 事件总线接口
export interface EventBusInterface {
  EventTypes: EventTypesInterface;
  on: (event: string, callback: EventListener) => () => void;
  once: (event: string, callback: EventListener) => () => void;
  off: (event: string, callback: EventListener) => void;
  emit: (event: string, data?: Object) => void;
  clear: () => void;
  emitPlayStateChanged: (isPlay: boolean) => void;
  emitPlayProgressChanged: (progress: PlayProgressChangedData) => void;
  emitPlayMusicChanged: (music: PlayMusicChangedData) => void;
  emitSearchStarted: (keyword: string) => void;
  emitSearchCompleted: (results: Object[]) => void;
  emitListUpdated: (listId: string) => void;
  emitThemeChanged: (isDark: boolean) => void;
  emitError: (message: string) => void;
  emitToast: (message: string) => void;
}

// 导出事件总线
const eventBus: EventBusInterface = {
  EventTypes,
  on,
  once,
  off,
  emit,
  clear,
  emitPlayStateChanged,
  emitPlayProgressChanged,
  emitPlayMusicChanged,
  emitSearchStarted,
  emitSearchCompleted,
  emitListUpdated,
  emitThemeChanged,
  emitError,
  emitToast,
};

export default eventBus;
