/**
 * 设置 → 关于
 *
 * 只留三个入口：关于与版本（二级面板）/ 许可协议与隐私政策（弹层）/ 恢复默认设置。
 * 「关于 LX Music、版本信息、运行日志、记录详细日志」四项合并到「关于与版本」的二级面板里，
 * 避免设置页里四行入口各占一行、彼此又高度相关。
 */
import { settingsService } from '../../../service/SettingsService';
import { t, tf } from '../../../service/LocalizationService';
import { navigationService, RouteName } from '../../../service/NavigationService';
import { appConfirmSystem, appToast } from '../../../service/DialogService';
import { logService } from '../../../service/LogService';
import { APP_VERSION } from '../../../service/VersionCheckService';
import { PactDialog } from '../../../components/common/PactDialog';
import { Subscription } from '../../../service/Subscription';
import { SettingsSection } from '../../../components/ui/SettingsSection';
import { BottomSheet } from '../../../components/ui/BottomSheet';
import { SheetHeader } from '../../../components/ui/SheetHeader';
import type { SettingSectionItem } from '../../../components/ui/SettingsTypes';
import { DesignTokens } from '../../../theme/DesignTokens';

@Component
export struct AboutSection {
  @StorageProp('theme') theme: string = 'light';
  @State enableVerboseLog: boolean = false;
  @State logCount: number = 0;
  @State showPact: boolean = false;
  /** 「关于与版本」二级面板 */
  @State showAboutMenu: boolean = false;
  /** 打开的是哪份法律文本：pact = 许可协议，privacy = 隐私政策 */
  @State legalDocument: string = 'pact';

  private settingsWatch: Subscription = new Subscription();

  aboutToAppear() {
    this.loadFromSettings();
    // 外部改动（恢复备份 / 同步下发 / 其它入口）也要刷新本分组
    this.settingsWatch.bindSettings((): void => {
      this.loadFromSettings();
    });
  }

  aboutToDisappear() {
    this.settingsWatch.detach();
  }

  /** 从设置服务读取本分组的当前值 */
  private loadFromSettings(): void {
    this.enableVerboseLog = settingsService.get().enableVerboseLog;
    try {
      this.logCount = logService.count();
    } catch (err) {
      this.logCount = 0;
    }  }

  private buildItems(): SettingSectionItem[] {
    return [
      {
        type: 'button',
        // 关于 LX Music / 版本信息 / 运行日志 / 记录详细日志 合并到一个二级面板
        title: t('settings_about_version'),
        description: `v${APP_VERSION} · HarmonyOS`,
        onClick: (): void => {
          this.showAboutMenu = true;
        },
      },
      {
        type: 'button',
        // 许可协议与隐私政策合并成一行：点开弹层里可切换两篇（原来两行平铺）
        title: t('legal_title'),
        description: t('legal_title_desc'),
        onClick: (): void => {
          this.legalDocument = 'pact';
          this.showPact = true;
        },
      },
      {
        type: 'button',
        title: t('settings_reset'),
        description: t('settings_reset_desc'),
        danger: true,
        onClick: (): void => {
          void this.resetSettings();
        },
      },
    ];
  }

  /** 二级面板：关于页 / 版本信息 / 运行日志 / 详细日志开关 */
  @Builder
  AboutMenuSheet() {
    BottomSheet({
      visible: $showAboutMenu,
      sheetSize: 'content',
      content: (): void => {
        this.AboutMenuContent();
      },
    })
  }

  @Builder
  AboutMenuContent() {
    Column() {
      SheetHeader({
        title: t('settings_about_version'),
        onClose: (): void => {
          this.showAboutMenu = false;
        },
      })
      .margin({ bottom: 8 })

      Column() {
        AboutMenuRow({
          icon: $r('sys.symbol.info_circle'),
          title: t('settings_about_lx'),
          onTap: (): void => {
            this.showAboutMenu = false;
            navigationService.navigateTo(RouteName.ABOUT);
          },
        })

        AboutMenuRow({
          icon: $r('sys.symbol.arrow_up_circle'),
          title: t('settings_version'),
          description: `v${APP_VERSION} (HarmonyOS)`,
          onTap: (): void => {
            appToast(`LX Music v${APP_VERSION}\nHarmonyOS NEXT`);
          },
        })

        AboutMenuRow({
          icon: $r('sys.symbol.doc_plaintext'),
          title: t('settings_logs'),
          description: tf('settings_logs_desc', [this.logCount.toString()]),
          onTap: (): void => {
            this.showAboutMenu = false;
            navigationService.navigateTo(RouteName.LOGS);
          },
        })

        AboutMenuRow({
          icon: $r('sys.symbol.checkmark_circle'),
          title: t('settings_log_verbose'),
          description: t('settings_log_verbose_desc'),
          toggleable: true,
          checked: this.enableVerboseLog,
          onToggle: (value: boolean): void => {
            this.enableVerboseLog = value;
            void settingsService.update({ enableVerboseLog: value });
          },
        })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // 面板行是 @Component 而不是 @Builder：@Builder 的参数不会随状态刷新
  // （详细日志开关、日志条数都是会变的状态），组件 + @Prop 才可靠。

  /**
   * 恢复默认设置。
   *
   * 危险操作：二次确认后整包写回默认值（SettingsService.resetToDefaults）。
   * 已同意过协议的状态不会被回退，避免用户莫名其妙被重新拦住。
   */
  private async resetSettings(): Promise<void> {
    const confirmed = await appConfirmSystem(
      t('settings_reset'),
      t('confirm_reset_settings'),
      { danger: true });
    if (!confirmed) {
      return;
    }
    await settingsService.resetToDefaults();
    appToast(t('toast_settings_reset'));
    this.loadFromSettings();
  }

  build() {
    Stack() {
      SettingsSection({ title: t('settings_about'), items: this.buildItems() })

      // 二级面板：关于与版本
      this.AboutMenuSheet()

      if (this.showPact) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(DesignTokens.maskColor())

          PactDialog({
            readonlyMode: true,
            initialDocument: this.legalDocument,
            visible: true,
            onClose: (): void => {
              this.showPact = false;
            },
          })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
  }
}

/**
 * 「关于与版本」二级面板里的一行：左图标 + 标题/说明 + 右侧箭头或开关。
 *
 * 独立成组件而不是 @Builder：@Builder 的参数不随状态刷新，
 * 而这一行要看「详细日志开关状态」和「日志条数」，会变的内容必须走 @Prop。
 */
@Component
struct AboutMenuRow {
  @StorageProp('theme') theme: string = 'light';
  @Prop icon: Resource;
  @Prop title: string = '';
  @Prop description: string = '';
  /** 开关行（右侧 Switch，点击不关面板） */
  @Prop toggleable: boolean = false;
  @Prop checked: boolean = false;
  onTap?: () => void;
  onToggle?: (value: boolean) => void;

  build() {
    Row({ space: 12 }) {
      SymbolGlyph(this.icon)
        .fontSize(DesignTokens.iconLg())
        .fontColor([DesignTokens.labelSecondary(this.theme)])

      Column({ space: 2 }) {
        Text(this.title)
          .fontSize(DesignTokens.fontTitle())
          .fontColor(DesignTokens.labelPrimary(this.theme))
          .maxLines(1)
        if (this.description.length > 0) {
          Text(this.description)
            .fontSize(DesignTokens.fontCaption())
            .fontColor(DesignTokens.labelTertiary(this.theme))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.toggleable) {
        Toggle({ type: ToggleType.Switch, isOn: this.checked })
          .selectedColor(DesignTokens.accent())
          .onChange((value: boolean): void => {
            if (this.onToggle) {
              this.onToggle(value);
            }
          })
      } else {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(DesignTokens.fontHeadline())
          .fontColor([DesignTokens.labelTertiary(this.theme)])
      }
    }
    .width('100%')
    .height(DesignTokens.touchTarget())
    .padding({ left: 4, right: 4 })
    .alignItems(VerticalAlign.Center)
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityText(this.title)
    .onClick(() => {
      if (this.toggleable) {
        if (this.onToggle) {
          this.onToggle(!this.checked);
        }
        return;
      }
      if (this.onTap) {
        this.onTap();
      }
    })
  }
}
