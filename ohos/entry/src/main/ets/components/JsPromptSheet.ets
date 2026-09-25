/**
 * window.prompt() answer sheet. The title is the page host rather than any
 * page-supplied text, so a page cannot impersonate browser chrome.
 */
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

        Text(this.title)
          .width('100%')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.message.length > 0) {
          Text(this.message)
            .width('100%')
            .margin({ top: 8 })
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }

        TextInput({ text: this.text })
          .id('js-prompt-input')
          .type(InputType.Normal)
          .onChange((value: string): void => { this.text = value; })
          .width('100%')
          .height(48)
          .margin({ top: 16 })
          .backgroundColor($r('app.color.surface_subtle'))

        Row({ space: 12 }) {
          Text($r('app.string.cancel'))
            .id('js-prompt-cancel')
            .layoutWeight(1)
            .height(48)
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .borderRadius(16)
            .backgroundColor($r('app.color.surface_subtle'))
            .onClick(() => this.onCancel())
          Text($r('app.string.action_ok'))
            .id('js-prompt-confirm')
            .layoutWeight(1)
            .height(48)
            .fontSize(15)
            .fontColor($r('app.color.accent_foreground'))
            .textAlign(TextAlign.Center)
            .borderRadius(16)
            .backgroundColor($r('app.color.accent'))
            .onClick(() => this.onConfirm(this.text))
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
