import { AppSwitch } from './AppSwitch';
import { AppIcon, IconName } from './AppIcon';
import { QUICK_SITE_LIMIT_MAX, QUICK_SITE_LIMIT_MIN } from '../models/BrowserModels';

@Component
export struct PageSettingsPanel {
  @Prop quickSitesEnabled: boolean = true;
  @Prop quickSiteLimit: number = 6;
  @Prop backgroundEnabled: boolean = true;
  @Prop appearanceLabel: ResourceStr = '';
  onToggleQuickSites: () => void = (): void => {};
  onChangeQuickSiteLimit: (limit: number) => void = (_limit: number): void => {};
  onToggleBackground: () => void = (): void => {};
  onOpenSettings: () => void = (): void => {};
  onDismiss: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.onDismiss())

      Column({ space: 12 }) {
        Text($r('app.string.page_settings'))
          .width('100%')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.home_text_primary'))

        Column() {
          this.ToggleRow($r('app.string.page_shortcuts'), this.quickSitesEnabled, true,
            this.onToggleQuickSites)
          this.ToggleRow($r('app.string.page_background'), this.backgroundEnabled, true,
            this.onToggleBackground)
          this.QuickSiteLimitRow()
        }
        .width('100%')
        .padding({ left: 14, right: 10 })
        .borderRadius(14)
        .backgroundColor($r('app.color.home_panel_subtle'))

        Row() {
          Text($r('app.string.page_theme'))
            .layoutWeight(1)
            .fontSize(14)
            .fontColor($r('app.color.home_text_primary'))
          Text(this.appearanceLabel)
            .fontSize(13)
            .fontColor($r('app.color.home_text_secondary'))
          AppIcon({ name: IconName.ChevronRight, glyphSize: 16, color: $r('app.color.home_text_secondary') })
        }
        .width('100%')
        .height(50)
        .padding({ left: 14, right: 12 })
        .borderRadius(14)
        .backgroundColor($r('app.color.home_panel_subtle'))
        .onClick(() => this.onOpenSettings())

        Text($r('app.string.more_settings'))
          .width('100%')
          .height(42)
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.home_panel_border') })
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.home_text_primary'))
          .textAlign(TextAlign.Center)
          .onClick(() => this.onOpenSettings())
      }
      .width('62%')
      .constraintSize({ maxWidth: 620 })
      .margin({ top: 48, right: 16 })
      .padding({ top: 18, left: 18, right: 18, bottom: 18 })
      .borderRadius(22)
      .backgroundColor($r('app.color.home_panel_background'))
      .backdropBlur(28)
      .shadow({ radius: 24, color: $r('app.color.home_panel_shadow'), offsetX: 0, offsetY: 10 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private ToggleRow(label: Resource, checked: boolean, divided: boolean, onToggle: () => void) {
    Row() {
      Text(label)
        .layoutWeight(1)
        .fontSize(14)
        .fontColor($r('app.color.home_text_primary'))
      AppSwitch({ checked: checked, accessibilityLabel: label, onToggle: onToggle })
    }
    .width('100%')
    .height(50)
    .border(divided
      ? { width: { bottom: 1 }, color: $r('app.color.home_panel_divider') }
      : { width: 0 })
  }

  @Builder
  private QuickSiteLimitRow() {
    Row() {
      Text($r('app.string.page_shortcut_limit'))
        .layoutWeight(1)
        .fontSize(14)
        .fontColor($r('app.color.home_text_primary'))

      Row({ space: 6 }) {
        this.LimitButton(
          IconName.ChevronLeft,
          this.quickSiteLimit > QUICK_SITE_LIMIT_MIN,
          () => this.onChangeQuickSiteLimit(this.quickSiteLimit - 2)
        )
        Text(`${this.quickSiteLimit}`)
          .width(28)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.home_text_primary'))
          .textAlign(TextAlign.Center)
        this.LimitButton(
          IconName.ChevronRight,
          this.quickSiteLimit < QUICK_SITE_LIMIT_MAX,
          () => this.onChangeQuickSiteLimit(this.quickSiteLimit + 2)
        )
      }
    }
    .width('100%')
    .height(50)
  }

  @Builder
  private LimitButton(icon: IconName, enabled: boolean, action: () => void) {
    Column() {
      AppIcon({ name: icon, glyphSize: 15, color: $r('app.color.home_text_primary') })
    }
    .width(30)
    .height(30)
    .justifyContent(FlexAlign.Center)
    .borderRadius(15)
    .backgroundColor($r('app.color.home_panel_subtle'))
    .opacity(enabled ? 1 : 0.35)
    .onClick(() => {
      if (enabled) {
        action();
      }
    })
  }
}
