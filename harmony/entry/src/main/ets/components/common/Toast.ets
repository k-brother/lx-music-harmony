/**
 * 统一Toast组件
 * 用于显示临时提示信息，自动消失
 */

@Component
export struct Toast {
  @Prop message: string = '';
  @Prop duration: number = 2000; // 显示时长(ms)
  @Prop show: boolean = false;

  build() {
    if (this.show) {
      Stack() {
        Column() {
          Text(this.message)
            .fontSize(14)
            .fontColor('#FFFFFF')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .backgroundColor('rgba(0, 0, 0, 0.75)')
            .borderRadius(8)
        }
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
    }
  }
}

/**
 * Toast显示管理器
 * 单例模式，提供全局Toast控制
 */
export class ToastManager {
  private static instance: ToastManager = null;
  private message: string = '';
  private duration: number = 2000;
  private showToast: boolean = false;

  private constructor() {}

  static getInstance(): ToastManager {
    if (ToastManager.instance === null) {
      ToastManager.instance = new ToastManager();
    }
    return ToastManager.instance;
  }

  /**
   * 显示Toast
   * @param message 显示的消息
   * @param duration 显示时长，默认2000ms
   */
  show(message: string, duration: number = 2000): void {
    this.message = message;
    this.duration = duration;
    this.showToast = true;

    // 自动隐藏
    setTimeout(() => {
      this.showToast = false;
    }, duration);
  }

  getMessage(): string {
    return this.message;
  }

  getDuration(): number {
    return this.duration;
  }

  isShow(): boolean {
    return this.showToast;
  }
}
