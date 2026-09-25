/**
 * HTTP Basic/Digest credential prompt. Credentials go straight to the pending
 * handler and are never stored; Index cancels the handler whenever this sheet
 * closes without confirming.
 */
@Component
export struct HttpAuthSheet {
  @Prop host: string = '';
  event?: OnHttpAuthRequestEvent;
  onCancel: () => void = (): void => {};
  onConfirm: () => void = (): void => {};

  @State private username: string = '';
  @State private password: string = '';

  build() {
    Column() {
      Column()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.onCancel())

      Column() {
        Row()
          .width(36)
          .height(4)
          .borderRadius(2)
          .backgroundColor($r('app.color.handle'))
          .margin({ bottom: 16 })

        Text($r('app.string.http_auth_title'))
          .width('100%')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))

        Text(this.host)
          .width('100%')
          .margin({ top: 8 })
          .fontSize(14)
          .fontColor($r('app.color.accent'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        TextInput({ placeholder: $r('app.string.http_auth_username'), text: this.username })
          .id('http-auth-username')
          .type(InputType.Normal)
          .onChange((value: string): void => { this.username = value; })
          .width('100%')
          .height(48)
          .margin({ top: 16 })
          .backgroundColor($r('app.color.surface_subtle'))

        TextInput({ placeholder: $r('app.string.http_auth_password'), text: this.password })
          .id('http-auth-password')
          .type(InputType.Password)
          .onChange((value: string): void => { this.password = value; })
          .width('100%')
          .height(48)
          .margin({ top: 12 })
          .backgroundColor($r('app.color.surface_subtle'))

        Row({ space: 12 }) {
          Text($r('app.string.cancel'))
            .id('http-auth-cancel')
            .layoutWeight(1)
            .height(48)
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .borderRadius(16)
            .backgroundColor($r('app.color.surface_subtle'))
            .onClick(() => this.onCancel())
          Text($r('app.string.action_ok'))
            .id('http-auth-confirm')
            .layoutWeight(1)
            .height(48)
            .fontSize(15)
            .fontColor($r('app.color.accent_foreground'))
            .textAlign(TextAlign.Center)
            .borderRadius(16)
            .backgroundColor($r('app.color.accent'))
            .onClick(() => {
              this.event?.handler.confirm(this.username, this.password);
              this.onConfirm();
            })
        }
        .width('100%')
        .margin({ top: 20 })
      }
      .width('100%')
      .padding({ top: 10, left: 28, right: 28, bottom: 46 })
      .backgroundColor($r('app.color.surface_panel'))
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
  }
}
