import { SiteControl, SiteControlMode, cloneSiteControl } from '../models/SiteControlModels';
import { AppIcon, IconName } from './AppIcon';

@Component
export struct SiteControlSheet {
  @Prop topInset: number = 0;
  @Prop control: SiteControl;
  onChange: (control: SiteControl) => void = (_control: SiteControl): void => {};
  onDismiss: () => void = (): void => {};

  build() {
    Column() {
      Row({ space: 12 }) {
        AppIcon({ name: IconName.ArrowLeft, glyphSize: 21, color: $r('app.color.text_primary') })
          .onClick(() => this.onDismiss())
        Column({ space: 2 }) {
          Text($r('app.string.site_control_title'))
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.control.host)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height(56 + Math.max(0, this.topInset))
      .padding({ top: Math.max(0, this.topInset), left: 24, right: 24 })
      .alignItems(VerticalAlign.Center)
      .border({ width: { bottom: 1 }, color: $r('app.color.border') })

      Scroll() {
        Column({ space: 0 }) {
          Text($r('app.string.site_control_description'))
            .width('100%')
            .fontSize(13)
            .lineHeight(20)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 24, right: 24, top: 18, bottom: 12 })
          this.ControlRow($r('app.string.site_control_network'), this.control.networkBlocking,
            (mode: SiteControlMode): void => this.update('networkBlocking', mode))
          this.ControlRow($r('app.string.site_control_tracker'), this.control.trackerBlocking,
            (mode: SiteControlMode): void => this.update('trackerBlocking', mode))
          Text($r('app.string.site_control_tracker_note'))
            .width('100%')
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 24, right: 24, top: 8, bottom: 8 })
          this.ControlRow($r('app.string.site_control_cosmetic'), this.control.cosmeticCleanup,
            (mode: SiteControlMode): void => this.update('cosmeticCleanup', mode))
          this.ControlRow($r('app.string.site_control_reader'), this.control.autoReader,
            (mode: SiteControlMode): void => this.update('autoReader', mode))
          this.ControlRow($r('app.string.site_control_dark'), this.control.darkMode,
            (mode: SiteControlMode): void => this.update('darkMode', mode))
          this.ControlRow($r('app.string.site_control_desktop'), this.control.desktopUserAgent,
            (mode: SiteControlMode): void => this.update('desktopUserAgent', mode))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 36 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private ControlRow(
    label: Resource,
    mode: SiteControlMode,
    onNext: (mode: SiteControlMode) => void
  ) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Text(this.modeLabel(mode))
        .fontSize(13)
        .fontColor(mode === SiteControlMode.Inherit ? $r('app.color.text_secondary') : $r('app.color.accent'))
      AppIcon({ name: IconName.ChevronRight, glyphSize: 16, color: $r('app.color.text_secondary') })
    }
    .width('100%')
    .height(58)
    .padding({ left: 24, right: 24 })
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
    .onClick(() => onNext(this.nextMode(mode)))
  }

  private update(field: string, mode: SiteControlMode): void {
    const next: SiteControl = cloneSiteControl(this.control);
    if (field === 'networkBlocking') {
      next.networkBlocking = mode;
    } else if (field === 'trackerBlocking') {
      next.trackerBlocking = mode;
    } else if (field === 'cosmeticCleanup') {
      next.cosmeticCleanup = mode;
    } else if (field === 'autoReader') {
      next.autoReader = mode;
    } else if (field === 'darkMode') {
      next.darkMode = mode;
    } else if (field === 'desktopUserAgent') {
      next.desktopUserAgent = mode;
    }
    this.onChange(next);
  }

  private nextMode(mode: SiteControlMode): SiteControlMode {
    if (mode === SiteControlMode.Inherit) {
      return SiteControlMode.Enabled;
    }
    if (mode === SiteControlMode.Enabled) {
      return SiteControlMode.Disabled;
    }
    return SiteControlMode.Inherit;
  }

  private modeLabel(mode: SiteControlMode): Resource {
    if (mode === SiteControlMode.Enabled) {
      return $r('app.string.site_control_enabled');
    }
    if (mode === SiteControlMode.Disabled) {
      return $r('app.string.site_control_disabled');
    }
    return $r('app.string.site_control_inherit');
  }
}
