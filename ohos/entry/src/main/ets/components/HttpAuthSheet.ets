

@Component
export struct HttpAuthSheet {
  @Prop host: string = '';
  event?: OnHttpAuthRequestEvent;
  onCancel: () => void = (): void => {};
  onConfirm: () => void = (): void => {};

  @State private username: string = '';
  @State private password: string = '';

  build() {
    Column({ space: 16 }) {
      Text($r('app.string.http_auth_title'))
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .width('100%')
      
      Text(this.host)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      TextInput({ placeholder: $r('app.string.http_auth_username'), text: this.username })
        .type(InputType.Normal)
        .onChange((value: string) => this.username = value)
        .width('100%')
        .height(48)
        .backgroundColor($r('app.color.surface_subtle'))

      TextInput({ placeholder: $r('app.string.http_auth_password'), text: this.password })
        .type(InputType.Password)
        .onChange((value: string) => this.password = value)
        .width('100%')
        .height(48)
        .backgroundColor($r('app.color.surface_subtle'))

      Row({ space: 12 }) {
        Button('Cancel', { type: ButtonType.Capsule })
          .backgroundColor($r('app.color.surface_subtle'))
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .onClick(() => {
            if (this.event && this.event.handler) {
              this.event.handler.cancel();
            }
            this.onCancel();
          })

        Button('Confirm', { type: ButtonType.Capsule })
          .backgroundColor($r('app.color.accent'))
          .fontColor($r('app.color.content_background'))
          .layoutWeight(1)
          .onClick(() => {
            if (this.event && this.event.handler) {
              this.event.handler.confirm(this.username, this.password);
            }
            this.onConfirm();
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .padding(24)
    .width('100%')
    .backgroundColor($r('app.color.page_background'))
    .borderRadius({ topLeft: 24, topRight: 24 })
  }
}
