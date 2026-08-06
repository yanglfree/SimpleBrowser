import { SecurityState } from '../models/BrowserModels';
import { AppIcon, IconName } from './AppIcon';

@Component
export struct SecurityPanel {
  @Prop host: string = '';
  @Prop url: string = '';
  @Prop state: SecurityState = SecurityState.Unknown;
  onDismiss: () => void = (): void => {};

  build() {
    Column() {
      Column()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.onDismiss())

      Column({ space: 14 }) {
        Row()
          .width(36)
          .height(4)
          .borderRadius(2)
          .backgroundColor($r('app.color.handle'))

        Row({ space: 12 }) {
          AppIcon({
            name: this.state === SecurityState.Secure ? IconName.ShieldCheck : IconName.Shield,
            glyphSize: 24,
            color: this.state === SecurityState.Secure
              ? $r('app.color.accent')
              : $r('app.color.text_secondary')
          })
          Text(this.stateTitle())
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')

        Text(this.stateMessage())
          .width('100%')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))

        Divider()
          .strokeWidth(1)
          .color($r('app.color.border'))

        Column({ space: 6 }) {
          Text($r('app.string.security_site'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
          Text(this.host.length > 0 ? this.host : this.url)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')

        Text($r('app.string.security_certificate_note'))
          .width('100%')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding({ top: 10, left: 28, right: 28, bottom: 46 })
      .backgroundColor($r('app.color.surface_panel'))
      .borderRadius({ topLeft: 20, topRight: 20 })
      .shadow({ radius: 12, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: -2 })
    }
    .width('100%')
    .height('100%')
  }

  private stateTitle(): Resource {
    if (this.state === SecurityState.Secure) return $r('app.string.security_secure');
    if (this.state === SecurityState.CertificateError) return $r('app.string.security_certificate_error');
    if (this.state === SecurityState.Insecure) return $r('app.string.security_insecure');
    return $r('app.string.security_unknown');
  }

  private stateMessage(): Resource {
    if (this.state === SecurityState.Secure) return $r('app.string.security_secure_message');
    if (this.state === SecurityState.CertificateError) return $r('app.string.security_certificate_message');
    if (this.state === SecurityState.Insecure) return $r('app.string.security_insecure_message');
    return $r('app.string.security_unknown_message');
  }
}
