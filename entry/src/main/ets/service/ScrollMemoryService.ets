/**
 * 列表滚动位置记忆
 *
 * 「设置 → 列表 → 记住列表滚动位置」开启时，离开列表再回来要落回上次的位置。
 * 原先只有歌单详情实现了这套逻辑，其它长列表（榜单详情、历史、我喜欢、本地音乐）
 * 都没有，同一个开关在不同页面的表现不一致。
 *
 * 这里只负责「按 key 存 / 取」这一个职责，key 由调用方拼（页面/列表维度自己最清楚）；
 * 恢复时机（等布局完成再 scrollTo）仍属于页面的事，见各页的 restore 方法。
 */
import { getStorageService } from '../core/interfaces/IStorageService';
import { appLog as hilog } from '../core/log/AppLogger';

const DOMAIN = 0x0001;
const TAG = 'ScrollMemory';
/** 存储键前缀（历史数据沿用同一前缀，老记录依旧读得到） */
const KEY_PREFIX = 'list.scroll.';

/** 歌单详情的 key：按「源 + 列表 id」区分 */
export function songlistScrollKey(sourceId: string, listId: string): string {
  return `${KEY_PREFIX}${sourceId}.${listId}`;
}

/** 固定页面的 key：如 `list.scroll.page.history` */
export function pageScrollKey(page: string): string {
  return `${KEY_PREFIX}page.${page}`;
}

/** 带参数的页面 key：如榜单详情 `list.scroll.page.board_<id>` */
export function parameterizedPageScrollKey(page: string, param: string): string {
  return `${KEY_PREFIX}page.${page}_${param}`;
}

/** 读取上次滚动位置（无记录 / 非法数据返回 0） */
export async function loadScrollOffset(key: string): Promise<number> {
  if (key.length === 0) {
    return 0;
  }
  try {
    const offset = await getStorageService().getNumber(key, 0);
    return offset > 0 ? offset : 0;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'load failed: %{public}s', JSON.stringify(err));
    return 0;
  }
}

/** 记录滚动位置（关闭记忆、数据未就绪或位置为 0 时不写，避免把有效记录覆盖成顶部） */
export async function saveScrollOffset(
  key: string, offset: number, enabled: boolean, loaded: boolean
): Promise<void> {
  if (!enabled || !loaded || key.length === 0 || offset <= 0) {
    return;
  }
  try {
    await getStorageService().setNumber(key, Math.floor(offset));
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'save failed: %{public}s', JSON.stringify(err));
  }
}

/**
 * 单个列表的滚动记忆把手。
 *
 * 页面只需要「数据就绪时 restore、离开时 save + dispose」三句话，
 * 定时器与「等一帧再 scrollTo」的时序问题都收在这里（这是四个页面最容易写歪的部分）。
 */
export class ScrollMemoryHandle {
  private key: string;
  private scroller: Scroller;
  private timer: number = -1;
  private dataLoaded: boolean = false;

  constructor(key: string, scroller: Scroller) {
    this.key = key;
    this.scroller = scroller;
  }

  /** 数据已渲染到列表里（没就绪前不恢复、也不记录） */
  markLoaded(): void {
    this.dataLoaded = true;
  }

  /**
   * 换一个记忆 key（页面参数在加载时才拿到时用，例如榜单详情要等 boardId）。
   * 换 key 会复位「已就绪」状态，避免把 A 榜单的位置记到 B 榜单上。
   */
  setKey(key: string): void {
    if (this.key === key) {
      return;
    }
    this.clearTimer();
    this.key = key;
    this.dataLoaded = false;
  }

  /** 恢复上次位置；delayMs 是留给列表完成布局的时间 */
  restore(enabled: boolean, delayMs: number = 120): void {
    if (!enabled || this.key.length === 0) {
      return;
    }
    this.clearTimer();
    this.timer = setTimeout((): void => {
      this.timer = -1;
      loadScrollOffset(this.key).then((offset: number): void => {
        if (offset <= 0) {
          return;
        }
        try {
          this.scroller.scrollTo({ xOffset: 0, yOffset: offset, animation: false });
        } catch (err) {
          hilog.warn(DOMAIN, TAG, 'scrollTo failed: %{public}s', JSON.stringify(err));
        }
      }).catch((err: Error): void => {
        hilog.warn(DOMAIN, TAG, 'restore failed: %{public}s', err.message);
      });
    }, delayMs);
  }

  /** 离开页面时记录当前位置 */
  save(enabled: boolean): void {
    let offset: number = 0;
    try {
      offset = this.scroller.currentOffset().yOffset;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'read offset failed: %{public}s', JSON.stringify(err));
    }
    void saveScrollOffset(this.key, offset, enabled, this.dataLoaded);
  }

  /** 释放定时器（页面销毁时必须调用，否则回调会打到已销毁的列表上） */
  dispose(): void {
    this.clearTimer();
    this.dataLoaded = false;
  }

  private clearTimer(): void {
    if (this.timer !== -1) {
      clearTimeout(this.timer);
      this.timer = -1;
    }
  }
}
