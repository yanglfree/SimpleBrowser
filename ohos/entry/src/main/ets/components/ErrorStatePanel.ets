import { LoadErrorKind } from '../models/BrowserModels';
import { AppIcon, IconName } from './AppIcon';

const BREATH_TICK_MS: number = 1000;
const BREATH_DURATION_MS: number = 900;
const BREATH_SCALE: number = 0.06;

/**
 * The failed-page state. Network failures (offline/timeout/dns) get a large
 * gently-breathing "no signal" glyph; certificate and unknown errors stay text
 * led but share the same typography and a filled retry action.
 */
@Component
export struct ErrorStatePanel {
  @Prop kind: LoadErrorKind = LoadErrorKind.Unknown;
  @Prop bottomInset: number = 0;
  onRetry: () => void = (): void => {};
  onCertificateDetails: () => void = (): void => {};
  @State private breath: number = 0;
  private breathTimer: number = -1;

  aboutToAppear(): void {
    this.startBreath();
  }

  aboutToDisappear(): void {
    this.stopBreath();
  }

  build() {
    Column({ space: 14 }) {
      if (this.showIcon()) {
        Stack({ alignContent: Alignment.Center }) {
          AppIcon({
            name: this.iconFor(this.kind),
            glyphSize: 54,
            color: $r('app.color.text_secondary'),
            strokeWidth: 1.4
          })
        }
        .width(96)
        .height(96)
        .borderRadius(48)
        .backgroundColor($r('app.color.surface_subtle'))
        .scale({ x: 1 + this.breath * BREATH_SCALE, y: 1 + this.breath * BREATH_SCALE })
      }

      Text(this.errorTitle())
        .fontSize(19)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Center)

      Text(this.errorMessage())
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .padding({ left: 32, right: 32 })
        .maxLines(3)

      Row() {
        Text($r('app.string.retry'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_background'))
      }
      .width(128)
      .height(44)
      .justifyContent(FlexAlign.Center)
      .borderRadius(22)
      .backgroundColor($r('app.color.accent'))
      .margin({ top: 6 })
      .onClick(() => this.onRetry())

      if (this.kind === LoadErrorKind.Certificate) {
        Text($r('app.string.certificate_details'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => this.onCertificateDetails())
      }
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: this.bottomInset })
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.page_background'))
  }

  private showIcon(): boolean {
    return this.kind === LoadErrorKind.Offline ||
      this.kind === LoadErrorKind.Timeout ||
      this.kind === LoadErrorKind.Dns;
  }

  private iconFor(kind: LoadErrorKind): IconName {
    if (kind === LoadErrorKind.Dns) {
      return IconName.CloudOff;
    }
    return IconName.WifiOff;
  }

  private errorTitle(): Resource {
    if (this.kind === LoadErrorKind.Offline) {
      return $r('app.string.error_offline_title');
    }
    if (this.kind === LoadErrorKind.Timeout) {
      return $r('app.string.error_timeout_title');
    }
    if (this.kind === LoadErrorKind.Dns) {
      return $r('app.string.error_dns_title');
    }
    if (this.kind === LoadErrorKind.Certificate) {
      return $r('app.string.error_certificate_title');
    }
    return $r('app.string.error_unknown_title');
  }

  private errorMessage(): Resource {
    if (this.kind === LoadErrorKind.Offline) {
      return $r('app.string.error_offline_message');
    }
    if (this.kind === LoadErrorKind.Timeout) {
      return $r('app.string.error_timeout_message');
    }
    if (this.kind === LoadErrorKind.Dns) {
      return $r('app.string.error_dns_message');
    }
    if (this.kind === LoadErrorKind.Certificate) {
      return $r('app.string.error_certificate_message');
    }
    return $r('app.string.error_unknown_message');
  }

  private startBreath(): void {
    if (!this.showIcon() || this.breathTimer >= 0) {
      return;
    }
    this.breath = 0;
    this.breathTimer = setInterval((): void => {
      this.getUIContext().animateTo({
        duration: BREATH_DURATION_MS,
        curve: Curve.EaseInOut
      }, (): void => {
        this.breath = this.breath > 0 ? 0 : 1;
      });
    }, BREATH_TICK_MS);
  }

  private stopBreath(): void {
    if (this.breathTimer >= 0) {
      clearInterval(this.breathTimer);
      this.breathTimer = -1;
    }
  }
}
