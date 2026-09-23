import { t } from '../../service/LocalizationService';
// AboutView - 关于页面
// 对应安卓源码中的 About 页面

import { hilog } from '@kit.PerformanceAnalysisKit';
import { DesignTokens } from '../../theme/DesignTokens';
import { Breakpoints } from '../../theme/Breakpoints';
import { NavBackButton } from '../../components/common/NavBackButton';
import { showAppToast, TOAST_DURATION_DEFAULT } from '../../utils/Toast';
import { tf } from '../../service/LocalizationService';
import { stateEvent, type VersionInfo } from '../../event/StateEvent';
import { checkVersionNow, compareVersion, getLastVersionInfo, APP_VERSION } from '../../service/VersionCheckService';
import type { common } from '@kit.AbilityKit';
import { NavBar } from '../../components/ui/NavBar';

const TAG = 'About';
const DOMAIN = 0x0001;

@Component
export struct AboutView {
  @StorageProp('theme') theme: string = 'light';
  @StorageProp('language') language: string = 'zh-CN';
  /** 一多：窗口宽度（vp），大屏内容列居中 */
  @StorageProp('windowWidthVp') windowWidthVp: number = 360;
  @StorageProp('langVersion') langVersion: number = 0;

  /** 版本检查状态：idle / checking / latest / newer / failed */
  @State versionStatus: string = 'idle';
  @State remoteVersion: string = '';
  @State remoteDesc: string = '';
  private versionUnsub: (() => void) | null = null;

  aboutToAppear() {
    hilog.info(DOMAIN, TAG, 'AboutView appearing');
    // 启动时的延迟检查结果也会推到这里；进入页面先展示上次结果
    const cached = getLastVersionInfo();
    if (cached) {
      this.applyVersionInfo(cached);
    }
    stateEvent.on('versionInfoUpdated', this.onVersionInfoUpdated);
    this.versionUnsub = (): void => {
      stateEvent.off('versionInfoUpdated', this.onVersionInfoUpdated);
    };
  }

  aboutToDisappear() {
    if (this.versionUnsub) {
      this.versionUnsub();
      this.versionUnsub = null;
    }
  }

  private onVersionInfoUpdated = (data: string): void => {
    try {
      const info = JSON.parse(data) as VersionInfo | null;
      if (info) {
        this.applyVersionInfo(info);
      }
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'onVersionInfoUpdated parse failed: %{public}s', JSON.stringify(err));
    }
  };

  /** 比对远端版本与当前版本，得出展示状态 */
  private applyVersionInfo(info: VersionInfo): void {
    this.remoteVersion = info.version;
    this.remoteDesc = info.desc ?? '';
    this.versionStatus = compareVersion(info.version, APP_VERSION) > 0 ? 'newer' : 'latest';
  }

  /** 手动检查更新 */
  private async runVersionCheck(): Promise<void> {
    if (this.versionStatus === 'checking') {
      return;
    }
    this.versionStatus = 'checking';
    const info = await checkVersionNow();
    if (!info) {
      this.versionStatus = 'failed';
      this.toast(t('version_check_failed'));
      return;
    }
    this.applyVersionInfo(info);
    this.toast(this.versionStatus === 'newer'
      ? tf('version_new_available', [info.version])
      : t('version_latest'));
  }

  private toast(message: string): void {
    showAppToast(this.getUIContext(), message, TOAST_DURATION_DEFAULT);
  }

  /** 版本状态行文案 */
  private versionTip(): string {
    if (this.versionStatus === 'checking') {
      return t('version_checking');
    }
    if (this.versionStatus === 'newer') {
      return tf('version_new_available', [this.remoteVersion]);
    }
    if (this.versionStatus === 'latest') {
      return t('version_latest');
    }
    if (this.versionStatus === 'failed') {
      return t('version_check_failed');
    }
    return t('version_tip_unknown');
  }

  /** 用系统浏览器打开链接 */
  private openUrl(url: string): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      context.startAbility({
        action: 'ohos.want.action.viewData',
        uri: url,
      }).catch((err: Error) => {
        hilog.warn(DOMAIN, TAG, 'openUrl failed: %{public}s', err.message);
        this.toast(t('toast_operation_failed'));
      });
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'openUrl failed: %{public}s', JSON.stringify(err));
      this.toast(t('toast_operation_failed'));
    }
  }

  /** 应用描述 */
  @Builder
  AppInfoGroup() {
    ListItemGroup({ header: this.buildGroupHeader(t('about_lx_title')) }) {
      ListItem() {
        Column() {
          Text('LX Music')
            .fontSize(DesignTokens.fontLarge())
            .fontWeight(FontWeight.Bold)
            .fontColor(DesignTokens.accent())
            .margin({ bottom: 8 })

          Text(t('about_slogan'))
            .fontSize(DesignTokens.fontBody())
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .margin({ bottom: 4 })

          Text(t('about_version_value'))
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .margin({ bottom: 16 })

          Text(t('about_app_desc'))
            .fontSize(DesignTokens.fontBody())
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .lineHeight(22)
            .textAlign(TextAlign.JUSTIFY)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .alignItems(HorizontalAlign.Start)
      }
    }
  }

  /** 版本信息（当前版本 / 检查更新 / 结果提示） */
  @Builder
  VersionGroup() {
    ListItemGroup({ header: this.buildGroupHeader(t('settings_version')) }) {
      this.CurrentVersionItem()
      this.CheckVersionItem()
      if (this.versionStatus === 'newer') {
        this.OpenReleaseItem()
      }
    }
  }

  /** 当前版本号 */
  @Builder
  CurrentVersionItem() {
    ListItem() {
      Row() {
        Text(t('version_current'))
          .fontSize(DesignTokens.fontSubhead())
        Blank()
        Text(`v${APP_VERSION}`)
          .fontSize(DesignTokens.fontBody())
          .fontColor(DesignTokens.labelSecondary(this.theme))
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    }
  }

  /** 检查更新：状态行（检查中转圈 / 其余给刷新图标）+ 结果文案 + 新版说明 */
  @Builder
  CheckVersionItem() {
    ListItem() {
      Column() {
        Row() {
          Text(t('version_check'))
            .fontSize(DesignTokens.fontSubhead())
          Blank()
          if (this.versionStatus === 'checking') {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(DesignTokens.accent())
          } else {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(DesignTokens.fontIconLg())
              .fontColor([DesignTokens.accent()])
          }
        }
        .width('100%')

        Text(this.versionTip())
          .fontSize(DesignTokens.fontCaption())
          .fontColor(this.versionStatus === 'newer' ? DesignTokens.accent() : DesignTokens.labelTertiary(this.theme))
          .margin({ top: 4 })
          .width('100%')

        if (this.versionStatus === 'newer' && this.remoteDesc.length > 0) {
          Text(this.remoteDesc)
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .margin({ top: 4 })
            .width('100%')
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .onClick(() => {
        void this.runVersionCheck();
      })
    }
  }

  /** 有新版本时：打开发布页 */
  @Builder
  OpenReleaseItem() {
    ListItem() {
      Row() {
        Text(t('version_open_release'))
          .fontSize(DesignTokens.fontSubhead())
          .fontColor(DesignTokens.accent())
        Blank()
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(DesignTokens.fontIconLg())
          .fontColor([DesignTokens.labelSecondary(this.theme)])
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .onClick(() => {
        this.openUrl('https://github.com/lyswhut/lx-music-mobile/releases');
      })
    }
  }

  /** 开源信息 */
  @Builder
  OpenSourceGroup() {
    ListItemGroup({ header: this.buildGroupHeader(t('about_opensource')) }) {
      ListItem() {
        Row() {
          Text(t('ui_github_repo'))
            .fontSize(DesignTokens.fontSubhead())
          Blank()
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(DesignTokens.fontIconLg())
            .fontColor([DesignTokens.labelSecondary(this.theme)])
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .onClick(() => {
          this.openUrl('https://github.com/lyswhut/lx-music-mobile');
        })
      }

      ListItem() {
        Row() {
          Text(t('about_license'))
            .fontSize(DesignTokens.fontSubhead())
          Blank()
          Text('MIT')
            .fontSize(DesignTokens.fontBody())
            .fontColor(DesignTokens.labelSecondary(this.theme))
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(DesignTokens.fontIconLg())
            .fontColor([DesignTokens.labelSecondary(this.theme)])
            .margin({ left: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      }
    }
  }

  /** 致谢 */
  @Builder
  ThanksGroup() {
    ListItemGroup({ header: this.buildGroupHeader(t('about_thanks')) }) {
      ListItem() {
        Column() {
          Text(t('about_thanks_detail'))
            .fontSize(DesignTokens.fontBody())
            .fontColor(DesignTokens.labelSecondary(this.theme))
            .lineHeight(22)
            .textAlign(TextAlign.JUSTIFY)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .alignItems(HorizontalAlign.Start)
      }
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      this.HeaderBar()

      // 关于内容
      List() {
        this.AppInfoGroup()
        this.VersionGroup()
        this.OpenSourceGroup()
        this.ThanksGroup()
      }
      .width('100%')
      .layoutWeight(1)
      // 一多：平板/PC 上关于信息不拉满整屏，内容列居中（与其它页面同一套留白）
      .padding({
        left: Breakpoints.contentInset(this.windowWidthVp),
        right: Breakpoints.contentInset(this.windowWidthVp),
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  HeaderBar() {
    NavBar({ title: t('settings_about') })
  }

  // NavDestination onReady callback
  onReady(params: Record<string, object | string | number | boolean | undefined>): void {
    hilog.info(DOMAIN, TAG, 'AboutView onReady with params: %{public}s', JSON.stringify(params));
  }

  @Builder
  buildGroupHeader(text: string) {
    Column() {
      Text(text)
        .fontSize(DesignTokens.fontCallout())
        .fontColor(DesignTokens.labelSecondary(this.theme))
        .padding({ left: 16, top: 12, bottom: 8 })
    }
    .width('100%')
    .backgroundColor(DesignTokens.pageBg(this.theme))
  }
}
