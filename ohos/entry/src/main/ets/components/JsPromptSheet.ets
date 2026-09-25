@Component
export struct JsPromptSheet {
  @Prop title: string = '';
  @Prop message: string = '';
  @Prop defaultValue: string = '';
  onCancel: () => void = (): void => {};
  onConfirm: (value: string) => void = (_value: string): void => {};

  @State private text: string = '';

  aboutToAppear(): void {
    this.text = this.defaultValue;
  }

  build() {
    Column({ space: 16 }) {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .width('100%')
      
      if (this.message.length > 0) {
        Text(this.message)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      }

      TextInput({ text: this.text })
        .id('js-prompt-input')
        .type(InputType.Normal)
        .onChange((value: string): void => { this.text = value; })
        .width('100%')
        .height(48)
        .backgroundColor($r('app.color.surface_subtle'))

      Row({ space: 12 }) {
        Button($r('app.string.cancel'), { type: ButtonType.Capsule })
          .id('js-prompt-cancel')
          .backgroundColor($r('app.color.surface_subtle'))
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .onClick(() => {
            this.onCancel();
          })

        Button($r('app.string.action_ok'), { type: ButtonType.Capsule })
          .id('js-prompt-confirm')
          .backgroundColor($r('app.color.accent'))
          .fontColor($r('app.color.accent_foreground'))
          .layoutWeight(1)
          .onClick(() => {
            this.onConfirm(this.text);
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
