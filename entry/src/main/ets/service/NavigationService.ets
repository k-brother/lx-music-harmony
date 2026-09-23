// NavigationService - 页面导航服务
// 使用 Navigation 组件 + NavPathStack 进行页面导航

import hilog from '@ohos.hilog';

// 页面路由名称
export enum RouteName {
  HOME = 'home',
  PLAY_DETAIL = 'playdetail',
  SONGLIST_DETAIL = 'songlistdetail',
  BOARD_DETAIL = 'boarddetail',
  CUSTOM_SOURCE = 'customsource',
  ABOUT = 'about',
  SETTINGS = 'settings',
  HISTORY_LIST = 'historylist',
  COMMENT = 'comment',
  /** 自建歌单管理页 */
  USER_LISTS = 'userlists',
  /** 我喜欢的列表页 */
  LOVE_LIST = 'lovelist',
  /** 本地音乐 */
  LOCAL_MUSIC = 'localmusic',
  /** 运行日志 */
  LOGS = 'logs',
}

// 导航参数类型
export interface NavigationParams {
  songListId?: string;
  songListName?: string;
  songListSource?: string;
  boardId?: string;
  boardName?: string;
  boardSource?: string;
  networkTest?: boolean;
  /** 评论页等：当前歌曲 */
  musicId?: string;
  musicName?: string;
  musicSinger?: string;
  musicAlbum?: string;
  musicPic?: string;
  musicSource?: string;
  commentType?: string;
}

// 导航服务类
export class NavigationService {
  private static instance: NavigationService;
  private navPathStack: NavPathStack | null = null;
  private lastNavigateAtMs: number = 0;
  private lastNavigateRoute: string = '';
  private navigateSeq: number = 0;

  private constructor() {}

  // 单例获取
  static getInstance(): NavigationService {
    if (!NavigationService.instance) {
      NavigationService.instance = new NavigationService();
    }
    return NavigationService.instance;
  }

  // 设置 NavPathStack
  setNavPathStack(stack: NavPathStack): void {
    this.navPathStack = stack;
  }

  // 页面跳转
  navigateTo(routeName: RouteName, params?: NavigationParams): void {
    if (!this.navPathStack) {
      hilog.error(0x0001, 'NavigationService', 'NavPathStack not initialized');
      return;
    }
    const routeNameStr = routeName.toString();
    this.navigateSeq += 1;
    const navId = this.navigateSeq;
    const now = Date.now();
    // 防止极短时间内重复 push 同一路由（迷你播放器点击时偶发双触发）
    if (this.lastNavigateRoute === routeNameStr && now - this.lastNavigateAtMs < 800) {
      hilog.warn(0x0001, 'NavigationService', 'Skip duplicate navigate id=%{public}d route=%{public}s', navId, routeNameStr);
      return;
    }
    this.lastNavigateRoute = routeNameStr;
    this.lastNavigateAtMs = now;
    let sizeBefore = -1;
    try {
      sizeBefore = this.navPathStack.size();
    } catch (_e) {
      sizeBefore = -1;
    }
    hilog.info(0x0001, 'NavigationService',
      'Navigating id=%{public}d to: %{public}s with params: %{public}s, stackBefore=%{public}d',
      navId, routeNameStr, JSON.stringify(params), sizeBefore);

    // 使用 pushPathByName 进行跳转
    const param: NavigationParams = params || {} as NavigationParams;
    try {
      this.navPathStack.pushPathByName(routeNameStr, param);
      let sizeAfter = -1;
      try {
        sizeAfter = this.navPathStack.size();
      } catch (_e) {
        sizeAfter = -1;
      }
      hilog.info(0x0001, 'NavigationService', 'Navigate id=%{public}d push success, stackAfter=%{public}d', navId, sizeAfter);
    } catch (e) {
      hilog.error(0x0001, 'NavigationService', 'Navigate id=%{public}d push failed: %{public}s', navId, JSON.stringify(e));
      const msg = e instanceof Error ? e.message : JSON.stringify(e);
      throw new Error(msg);
    }
  }

  // 返回上一页
  back(): void {
    if (!this.navPathStack) {
      hilog.error(0x0001, 'NavigationService', 'NavPathStack not initialized');
      return;
    }
    this.navPathStack.pop();
  }

  // 替换当前页面
  replaceTo(routeName: RouteName, params?: NavigationParams): void {
    if (!this.navPathStack) {
      hilog.error(0x0001, 'NavigationService', 'NavPathStack not initialized');
      return;
    }
    this.navPathStack.replacePathByName(routeName.toString(), params || {} as NavigationParams);
  }

  // 返回到指定页面
  backTo(routeName: RouteName): void {
    if (!this.navPathStack) {
      hilog.error(0x0001, 'NavigationService', 'NavPathStack not initialized');
      return;
    }
    this.navPathStack.popToName(routeName.toString());
  }

  // 返回首页 - 清空栈后跳转
  backToHome(): void {
    if (!this.navPathStack) {
      hilog.error(0x0001, 'NavigationService', 'NavPathStack not initialized');
      return;
    }
    this.navPathStack.clear();
    this.navPathStack.pushPathByName('home', {} as NavigationParams);
  }

  // 获取当前页面的参数
  getCurrentParams(): NavigationParams | null {
    if (!this.navPathStack) {
      hilog.error(0x0001, 'NavigationService', 'NavPathStack not initialized');
      return null;
    }
    try {
      const size = this.navPathStack.size();
      if (size > 0) {
        const param: Object | undefined = this.navPathStack.getParamByIndex(size - 1) as Object | undefined;
        if (param !== null && param !== undefined && this.isNavigationParams(param)) {
          return param as NavigationParams;
        }
      }
    } catch (e) {
      hilog.error(0x0001, 'NavigationService', 'Failed to get current params: %{public}s', JSON.stringify(e));
    }
    return null;
  }

  // 类型检查方法：验证参数是否为NavigationParams类型
  private isNavigationParams(param: Object): boolean {
    if (param && typeof param === 'object') {
      const obj = param as Record<string, Object>;
      // 检查必要的字段类型
      if (obj.songListId !== undefined && typeof obj.songListId !== 'string') return false;
      if (obj.songListName !== undefined && typeof obj.songListName !== 'string') return false;
      if (obj.songListSource !== undefined && typeof obj.songListSource !== 'string') return false;
      if (obj.boardId !== undefined && typeof obj.boardId !== 'string') return false;
      if (obj.boardName !== undefined && typeof obj.boardName !== 'string') return false;
      if (obj.boardSource !== undefined && typeof obj.boardSource !== 'string') return false;
      if (obj.networkTest !== undefined && typeof obj.networkTest !== 'boolean') return false;
      return true;
    }
    return false;
  }

}

// 导出导航服务实例
export const navigationService = NavigationService.getInstance();

// 导出页面跳转便捷函数
export const navigateTo = (routeName: RouteName, params?: NavigationParams) => {
  navigationService.navigateTo(routeName, params);
};

export const back = () => {
  navigationService.back();
};

export const replaceTo = (routeName: RouteName, params?: NavigationParams) => {
  navigationService.replaceTo(routeName, params);
};

export const backTo = (routeName: RouteName) => {
  navigationService.backTo(routeName);
};

export const backToHome = () => {
  navigationService.backToHome();
};
