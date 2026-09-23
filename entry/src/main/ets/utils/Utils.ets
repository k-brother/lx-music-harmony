// 工具函数 - 对应 src/utils/index.ts 和相关工具函数
// 使用 ArkTS 兼容的语法
// 时长格式化请使用 utils/CommonUtils.formatPlayTime

// 数组添加元素（到末尾）
export function arrPush<T>(arr: Array<T>, items: Array<T>): void {
  for (const item of items) {
    arr.push(item);
  }
}

// 数组添加元素（到开头）
export function arrUnshift<T>(arr: Array<T>, items: Array<T>): void {
  for (let i = items.length - 1; i >= 0; i--) {
    arr.unshift(items[i]);
  }
}

// 判断是否为空
export function isEmpty(value: object | string | Array<string> | null): boolean {
  if (value == null) return true;
  if (value instanceof String) return value.length === 0;
  if (Array.isArray(value)) return value.length === 0;
  if (value instanceof Object) {
    const keys = Object.keys(value);
    return keys.length === 0;
  }
  return false;
}

// 深拷贝 - 使用JSON序列化方式
export function deepClone(obj: object): object {
  if (obj === null) {
    return obj;
  }
  
  // 使用JSON序列化/反序列化实现深拷贝
  // 这种方法避免了类型断言，但只适用于可序列化的对象
  try {
    return JSON.parse(JSON.stringify(obj));
  } catch (e) {
    // 如果JSON方法失败，返回原对象
    return obj;
  }
}

// 生成随机ID
export function generateId(): string {
  return Date.now().toString(36) + Math.random().toString(36).substring(2);
}

// 节流函数类型
type ThrottleFunction = (args: Array<string>) => void;

// 节流函数
export function throttle(func: ThrottleFunction, limit: number): ThrottleFunction {
  let lastFunc: number | null = null;
  let lastRan: number = 0;

  return (args: Array<string>): void => {
    const currentTime = Date.now();
    if (lastRan === 0) {
      func(args);
      lastRan = currentTime;
    } else {
      if (lastFunc) clearTimeout(lastFunc);
      lastFunc = setTimeout(() => {
        if (currentTime - lastRan >= limit) {
          func(args);
          lastRan = currentTime;
        }
      }, limit - (currentTime - lastRan));
    }
  };
}

// 防抖函数
export function debounce(func: ThrottleFunction, wait: number): ThrottleFunction {
  let timeout: number | null = null;

  return (args: Array<string>): void => {
    if (timeout) clearTimeout(timeout);
    timeout = setTimeout(() => {
      func(args);
    }, wait);
  };
}

/** 等待若干毫秒（轮询/退避等场景共用一份实现） */
export function delayMs(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, ms);
  });
}
