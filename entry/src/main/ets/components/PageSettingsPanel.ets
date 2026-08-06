import { AppSwitch } from './AppSwitch';
import { AppIcon, IconName } from './AppIcon';

@Component
export struct PageSettingsPanel {
  @Prop quickSitesEnabled: boolean = true;
  @Prop backgroundEnabled: boolean = true;
  @Prop appearanceLabel: ResourceStr = '';
  onToggleQuickSites: () => void = (): void => {};
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

      Column({ space: 16 }) {
        Text($r('app.string.page_settings'))
          .width('100%')
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.home_text_primary'))

        Column() {
          this.ToggleRow($r('app.string.page_shortcuts'), this.quickSitesEnabled, true,
            this.onToggleQuickSites)
          this.ToggleRow($r('app.string.page_background'), this.backgroundEnabled, false,
            this.onToggleBackground)
        }
        .width('100%')
        .padding({ left: 16, right: 12 })
        .borderRadius(18)
        .backgroundColor($r('app.color.home_panel_subtle'))

        Row() {
          Text($r('app.string.page_theme'))
            .layoutWeight(1)
            .fontSize(16)
            .fontColor($r('app.color.home_text_primary'))
          Text(this.appearanceLabel)
            .fontSize(14)
            .fontColor($r('app.color.home_text_secondary'))
          AppIcon({ name: IconName.ChevronRight, glyphSize: 17, color: $r('app.color.home_text_secondary') })
        }
        .width('100%')
        .height(58)
        .padding({ left: 16, right: 14 })
        .borderRadius(18)
        .backgroundColor($r('app.color.home_panel_subtle'))
        .onClick(() => this.onOpenSettings())

        Text($r('app.string.more_settings'))
          .width('100%')
          .height(48)
          .borderRadius(14)
          .border({ width: 1, color: $r('app.color.home_panel_border') })
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.home_text_primary'))
          .textAlign(TextAlign.Center)
          .onClick(() => this.onOpenSettings())
      }
      .width('72%')
      .margin({ top: 52, right: 18 })
      .padding({ top: 24, left: 20, right: 20, bottom: 20 })
      .borderRadius(26)
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
        .fontSize(16)
        .fontColor($r('app.color.home_text_primary'))
      AppSwitch({ checked: checked, accessibilityLabel: label, onToggle: onToggle })
    }
    .width('100%')
    .height(58)
    .border(divided
      ? { width: { bottom: 1 }, color: $r('app.color.home_panel_divider') }
      : { width: 0 })
  }
}
