import { DesignTokens } from '../../theme/DesignTokens';
import { t } from '../../service/LocalizationService';
import { navigationService } from '../../service/NavigationService';

@Component
export struct NavBackButton {
  @StorageProp('theme') theme: string = 'light';

  build() {
    Stack() {
      Circle({ width: 34, height: 34 })
        .fill(DesignTokens.mutedFill(this.theme))
      Image($r('app.media.ic_pd_back'))
        .width(16)
        .height(16)
        .fillColor(DesignTokens.labelPrimary(this.theme))
    }
    .responseRegion(DesignTokens.touchRegion(34))
    .accessibilityText(t('a11y_back'))
    .onClick(() => {
      navigationService.back();
    })
  }
}
