// HotSearch Store - 对应 src/store/hotSearch/state.ts
// 热搜状态管理

// 热搜来源
export type HotSearchSource = 'kw' | 'kg' | 'tx' | 'mg' | 'wy';

// 热搜项
export interface HotSearchItem {
  index: number;
  title: string;
  source: HotSearchSource;
  url: string;
}

// 热搜状态
export class HotSearchState {
  // 热搜列表
  hotSearchList: HotSearchItem[] = [];

  // 是否正在获取
  isFetching: boolean = false;

  // 更新时间
  updateTime: number = 0;
}

// 导出单例
export const hotSearchState = new HotSearchState();
