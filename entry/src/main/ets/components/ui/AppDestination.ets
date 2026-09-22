/**
 * 路由目的地包装
 *
 * NavIndex 里 13 段「NavDestination + hideTitleBar + onReady 打日志」是同一份样板，
 * 统一到这里：新增页面只写一行，转场/埋点这类横切逻辑也只需改一处。
 */
import { appLog as hilog } from '../../core/log/AppLogger';

const DOMAIN: number = 0x0001;
const TAG: string = 'NavIndex';

@Component
export struct AppDestination {
  /** 页面名，用于 onReady 日志（便于排查「带参数跳转」问题） */
  @Prop routeName: string = '';
  /** 页面内容 */
  @BuilderParam content: () => void;

  build() {
    NavDestination() {
      this.content()
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      const params = context.pathInfo.param as Record<string, object | string | number | boolean | undefined>;
      hilog.info(DOMAIN, TAG, '%{public}s onReady with params: %{public}s',
        this.routeName, JSON.stringify(params));
    })
  }
}
