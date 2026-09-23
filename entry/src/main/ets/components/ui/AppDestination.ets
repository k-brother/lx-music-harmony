/**
 * 路由目的地包装
 *
 * NavIndex 里 13 段「NavDestination + hideTitleBar + onReady 打日志」是同一份样板，
 * 统一到这里：新增页面只写一行，转场/埋点这类横切逻辑也只需改一处。
 */
import { appLog as hilog } from '../../core/log/AppLogger';
import { navigationService } from '../../service/NavigationService';

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
    // 返回键统一走 NavigationService 的拦截栈：页面若注册了拦截器（例如多选态
    // 先退出多选），返回 true 表示已消费；否则返回 false 走系统默认（弹出本页）
    .onBackPressed((): boolean => {
      return navigationService.handleBackPressed();
    })
    .onReady((context: NavDestinationContext) => {
      const params = context.pathInfo.param as Record<string, object | string | number | boolean | undefined>;
      hilog.info(DOMAIN, TAG, '%{public}s onReady with params: %{public}s',
        this.routeName, JSON.stringify(params));
    })
  }
}
