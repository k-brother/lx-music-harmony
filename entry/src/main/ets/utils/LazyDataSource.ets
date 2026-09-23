/**
 * LazyForEach 数据源
 *
 * ArkUI 的 `ForEach` 会把所有子组件一次性建出来 —— 歌单/榜单动辄上千首，
 * 真机上既吃内存又拖慢首帧。HarmonyOS 的解法是 `LazyForEach` + `IDataSource`，
 * 只创建可视区附近的项（配合 List 的 cachedCount）。
 *
 * 这里提供一份通用实现，页面只需：
 *   private source: LazyDataSource<SongItem> = new LazyDataSource<SongItem>();
 *   LazyForEach(this.source, (song, index) => { ... }, (song, index) => key)
 * 数据变化时调用 reload()（整批变化）或 notifyChanged(index)（单行变化）。
 */
export class LazyDataSource<T> implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private items: T[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): T {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /** 当前数据（只读用途；页面侧仍是自己那份 @State 作为业务数据源） */
  snapshot(): T[] {
    return this.items;
  }

  /** 整批替换：加载完成、排序、去重、批量删除后调用 */
  reload(next: T[]): void {
    this.items = next;
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataReloaded();
    }
  }

  /** 只刷新某一行：播放高亮、收藏态等单行变化（比整表重载便宜） */
  notifyChanged(index: number): void {
    if (index < 0 || index >= this.items.length) {
      return;
    }
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i].onDataChange(index);
    }
  }
}
