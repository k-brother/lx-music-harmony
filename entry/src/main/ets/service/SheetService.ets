/**
 * 全局底部面板服务（命令式调用）
 *
 * 背景：设置页的分组是渲染在 Scroll 里的，把 BottomSheet 挂在分组内会被滚动容器裁剪
 * （真机上表现为「点了没反应」）。凡是浮层都应该挂在页面根节点之上，
 * 因此这里统一成「服务发请求 → 根部宿主渲染」的模式：
 *
 *   const theme = await sheetService.select('浅色主题', options, current);
 *   const size = await sheetService.input('字体大小', '14', { numberOnly: true });
 *
 * 取消时返回空字符串，调用方按「未修改」处理。
 */
import hilog from '@ohos.hilog';

const TAG = 'SheetService';
const DOMAIN = 0x0005;

/** 面板选项 */
export interface SheetOption {
  label: string;
  value: string;
}

export type SheetKind = 'select' | 'input';

/** 一次面板请求（宿主据此渲染） */
export interface SheetRequest {
  kind: SheetKind;
  title: string;
  options: SheetOption[];
  value: string;
  placeholder: string;
  numberOnly: boolean;
  /** 完成：选中值 / 输入值；取消返回空字符串 */
  resolve: (value: string) => void;
}

type SheetPresenter = (request: SheetRequest) => void;

class SheetServiceImpl {
  private presenter: SheetPresenter | null = null;
  private busy: boolean = false;

  /** 宿主注册（应用启动时由 SheetHost 调用一次） */
  register(presenter: SheetPresenter): void {
    this.presenter = presenter;
  }

  /** 单选面板 */
  select(title: string, options: SheetOption[], value: string): Promise<string> {
    return this.request('select', title, options, value, '', false);
  }

  /** 输入面板 */
  input(
    title: string, value: string, placeholder: string = '', numberOnly: boolean = false
  ): Promise<string> {
    return this.request('input', title, [], value, placeholder, numberOnly);
  }

  private request(
    kind: SheetKind,
    title: string,
    options: SheetOption[],
    value: string,
    placeholder: string,
    numberOnly: boolean
  ): Promise<string> {
    if (!this.presenter) {
      hilog.warn(DOMAIN, TAG, 'No sheet host registered, request dropped: %{public}s', title);
      return Promise.resolve('');
    }
    if (this.busy) {
      // 上一个面板还没结束，忽略重复请求，避免叠两个浮层
      hilog.warn(DOMAIN, TAG, 'Sheet already showing, request dropped: %{public}s', title);
      return Promise.resolve('');
    }
    this.busy = true;
    return new Promise<string>((resolve: (result: string) => void) => {
      const finish = (result: string): void => {
        this.busy = false;
        resolve(result);
      };
      const request: SheetRequest = {
        kind,
        title,
        options,
        value,
        placeholder,
        numberOnly,
        resolve: finish,
      };
      this.presenter?.(request);
    });
  }
}

export const sheetService = new SheetServiceImpl();
