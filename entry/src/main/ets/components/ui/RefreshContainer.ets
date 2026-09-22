/**
 * 下拉刷新容器
 *
 * 主流音乐 App 的列表页都能下拉重新拉数据，这里统一成一个容器：
 * 页面只提供「刷新中」状态和刷新回调，刷新指示器样式在一处维护。
 *
 * 用法：
 *   RefreshContainer({
 *     refreshing: $isRefreshing,
 *     onRefresh: (): void => { void this.reload(); },
 *   }) {
 *     this.Content()
 *   }
 */
import { DesignTokens } from '../../theme/DesignTokens';

@Component
export struct RefreshContainer {
  @StorageProp('theme') theme: string = 'light';
  /** 是否处于刷新中（页面负责在数据回来后置回 false） */
  @Link refreshing: boolean;
  @BuilderParam content: () => void;
  onRefresh?: () => void;

  build() {
    Refresh({ refreshing: $$this.refreshing }) {
      this.content()
    }
    .onRefreshing(() => {
      if (this.onRefresh) {
        this.onRefresh();
      }
    })
    .pullDownRatio(0.5)
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }
}
