// AboutView - 关于页面
// 对应安卓源码中的 About 页面

import hilog from '@ohos.hilog';
import { navigationService } from '../../service/NavigationService';

const TAG = 'About';
const DOMAIN = 0x0001;

@Component
export struct AboutView {
  @StorageProp('theme') theme: string = 'light';

  aboutToAppear() {
    hilog.info(DOMAIN, TAG, 'AboutView appearing');
  }

  build() {
    Column() {
      // 状态栏
      Row()
        .width('100%')
        .height(24)
        .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')

      // 顶部导航栏
      this.HeaderBar()

      // 关于内容
      List() {
        // 应用描述
        ListItemGroup({ header: this.buildGroupHeader('关于 LX Music') }) {
          ListItem() {
            Column() {
              Text('LX Music')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor('#E63946')
                .margin({ bottom: 8 })

              Text('一个简洁的音乐播放器')
                .fontSize(14)
                .fontColor('#666666')
                .margin({ bottom: 4 })

              Text('版本 1.0.0')
                .fontSize(12)
                .fontColor('#999999')
                .margin({ bottom: 16 })

              Text('LX Music 是一个开源的音乐播放器，支持多音乐源搜索、在线播放、歌词同步等功能。本项目为 HarmonyOS 移植版本，致力于为用户提供流畅的音乐体验。')
                .fontSize(14)
                .fontColor(this.theme === 'dark' ? '#CCCCCC' : '#555555')
                .lineHeight(22)
                .textAlign(TextAlign.JUSTIFY)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
            .alignItems(HorizontalAlign.Start)
          }
        }

        // 开源信息
        ListItemGroup({ header: this.buildGroupHeader('开源信息') }) {
          ListItem() {
            Row() {
              Text('GitHub 仓库')
                .fontSize(15)
              Blank()
              Image($r('sys.symbol.chevron_right'))
                .width(16)
                .height(16)
                .fillColor('#999999')
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .onClick(() => {
              hilog.info(DOMAIN, TAG, 'Open GitHub link');
            })
          }

          ListItem() {
            Row() {
              Text('开源许可证')
                .fontSize(15)
              Blank()
              Text('MIT')
                .fontSize(14)
                .fontColor('#999999')
              Image($r('sys.symbol.chevron_right'))
                .width(16)
                .height(16)
                .fillColor('#999999')
                .margin({ left: 8 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          }
        }

        // 致谢
        ListItemGroup({ header: this.buildGroupHeader('致谢') }) {
          ListItem() {
            Column() {
              Text('感谢所有为 LX Music 做出贡献的开发者。')
                .fontSize(14)
                .fontColor(this.theme === 'dark' ? '#CCCCCC' : '#555555')
                .lineHeight(22)
                .textAlign(TextAlign.JUSTIFY)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
            .alignItems(HorizontalAlign.Start)
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
  }

  @Builder
  HeaderBar() {
    Row() {
      Image($r('sys.symbol.chevron_left'))
        .width(24)
        .height(24)
        .fillColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
        .onClick(() => {
          navigationService.back();
        })

      Text('关于')
        .fontSize(16)
        .fontColor(this.theme === 'dark' ? '#FFFFFF' : '#333333')
        .fontWeight(FontWeight.Medium)
        .margin({ left: 16 })

      Blank()
    }
    .width('100%')
    .height(44)
    .padding({ left: 12 })
    .backgroundColor(this.theme === 'dark' ? '#1C1C1C' : '#FFFFFF')
  }

  onBackPressed(): boolean {
    navigationService.back();
    return true;
  }

  // NavDestination onReady callback
  onReady(params: Record<string, object | string | number | boolean | undefined>): void {
    hilog.info(DOMAIN, TAG, 'AboutView onReady with params: %{public}s', JSON.stringify(params));
  }

  @Builder
  buildGroupHeader(text: string) {
    Column() {
      Text(text)
        .fontSize(13)
        .fontColor('#999999')
        .padding({ left: 16, top: 12, bottom: 8 })
    }
    .width('100%')
    .backgroundColor(this.theme === 'dark' ? '#121212' : '#F5F5F5')
  }
}
