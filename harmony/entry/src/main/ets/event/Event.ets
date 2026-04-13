// 事件系统 - 对应 src/event/Event.ts
// 简化版事件系统 - ArkTS 兼容版本

// 事件监听器类型
type EventListener = (data: string) => void;

// 事件系统类
class EventClass {
  private listeners: Map<string, EventListener[]> = new Map();

  on(eventName: string, listener: EventListener): void {
    let targetListeners = this.listeners.get(eventName);
    if (!targetListeners) {
      targetListeners = [];
      this.listeners.set(eventName, targetListeners);
    }
    targetListeners.push(listener);
  }

  off(eventName: string, listener: EventListener): void {
    let targetListeners = this.listeners.get(eventName);
    if (!targetListeners) return;
    let index = -1;
    for (let i = 0; i < targetListeners.length; i++) {
      if (targetListeners[i] === listener) {
        index = i;
        break;
      }
    }
    if (index < 0) return;
    targetListeners.splice(index, 1);
  }

  emit(eventName: string, data: string): void {
    let targetListeners = this.listeners.get(eventName);
    if (!targetListeners) return;
    for (let i = 0; i < targetListeners.length; i++) {
      targetListeners[i](data);
    }
  }

  offAll(eventName: string): void {
    let targetListeners = this.listeners.get(eventName);
    if (!targetListeners) return;
    this.listeners.delete(eventName);
  }
}

// 导出单例
export const eventInstance = new EventClass();

// 导出事件系统类
export { EventClass };
