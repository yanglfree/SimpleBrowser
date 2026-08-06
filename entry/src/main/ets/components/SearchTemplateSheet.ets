@Component
export struct SearchTemplateSheet {
  initialValue: string = '';
  onSave: (template: string) => void = (_template: string): void => {};
  onDismiss: () => void = (): void => {};
  @State private text: string = '';

  aboutToAppear(): void {
    this.text = this.initialValue;
  }

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

        Text($r('app.string.custom_search_template'))
          .width('100%')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))

        Text($r('app.string.custom_search_template_hint'))
          .width('100%')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))

        TextInput({ text: this.text, placeholder: 'https://example.com/search?q=%s' })
          .width('100%')
          .height(48)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface_subtle'))
          .borderRadius(12)
          .onChange((value: string): void => { this.text = value; })

        Row({ space: 20 }) {
          Text($r('app.string.cancel'))
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => this.onDismiss())
          Text($r('app.string.save'))
            .fontSize(15)
            .fontColor($r('app.color.accent'))
            .onClick(() => this.save())
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
      }
      .width('100%')
      .padding({ top: 10, left: 28, right: 28, bottom: 46 })
      .backgroundColor($r('app.color.surface_panel'))
      .borderRadius({ topLeft: 20, topRight: 20 })
    }
    .width('100%')
    .height('100%')
  }

  private save(): void {
    if (this.text.length === 0 || this.text.includes('%s')) {
      this.onSave(this.text);
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({ message: $r('app.string.custom_search_template_invalid') });
    } catch (_error) {
      // The inline hint remains the fallback when a prompt is unavailable.
    }
  }
}
