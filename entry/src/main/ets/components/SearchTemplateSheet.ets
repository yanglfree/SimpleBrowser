@Component
export struct SearchTemplateSheet {
  initialValue: string = '';
  @Prop isWide: boolean = false;
  onSave: (template: string) => void = (_template: string): void => {};
  onDismiss: () => void = (): void => {};
  @State private text: string = '';

  aboutToAppear(): void {
    this.text = this.initialValue;
  }

  build() {
    Stack({ alignContent: this.isWide ? Alignment.Center : Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.onDismiss())

      Column({ space: 14 }) {
        if (!this.isWide) {
          Row()
            .width(36)
            .height(4)
            .borderRadius(2)
            .backgroundColor($r('app.color.handle'))
        }

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
      .width(this.isWide ? '88%' : '100%')
      .constraintSize({ maxWidth: this.isWide ? 520 : '100%' })
      .padding({ top: this.isWide ? 24 : 10, left: 28, right: 28, bottom: this.isWide ? 24 : 46 })
      .backgroundColor($r('app.color.surface_panel'))
      .borderRadius(this.isWide ? 20 : { topLeft: 20, topRight: 20 })
      .border({ width: this.isWide ? 1 : 0, color: $r('app.color.border') })
      .shadow(this.isWide ? { radius: 18, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: 6 } : undefined)
      .onClick((): void => {})
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
