import { AppIcon, IconName } from './AppIcon';

@Component
export struct FindSheet {
  @Prop query: string = '';
  @Prop current: number = 0;
  @Prop total: number = 0;
  onQueryChange: (query: string) => void = (_query: string): void => {};
  onPrevious: () => void = (): void => {};
  onNext: () => void = (): void => {};
  onDismiss: () => void = (): void => {};

  build() {
    Column() {
      Row({ space: 8 }) {
        TextInput({ text: this.query, placeholder: $r('app.string.find_placeholder') })
          .layoutWeight(1)
          .height(44)
          .padding({ left: 12, right: 12 })
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.surface_subtle'))
          .borderRadius(12)
          .onChange((value: string): void => this.onQueryChange(value))
        Text(`${this.current}/${this.total}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .fontFeature('"tnum" 1')
        Row() {
          AppIcon({ name: IconName.ChevronLeft, glyphSize: 18, color: $r('app.color.text_primary') })
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .opacity(this.total > 0 ? 1 : 0.35)
        .onClick(() => this.onPrevious())
        Row() {
          AppIcon({ name: IconName.ChevronRight, glyphSize: 18, color: $r('app.color.text_primary') })
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .opacity(this.total > 0 ? 1 : 0.35)
        .onClick(() => this.onNext())
        Row() {
          AppIcon({ name: IconName.Close, glyphSize: 16, color: $r('app.color.text_secondary') })
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.onDismiss())
      }
      .width('100%')
      .padding({ top: 12, left: 14, right: 10, bottom: 10 })
      .backgroundColor($r('app.color.surface_panel'))
      .border({ width: { bottom: 1 }, color: $r('app.color.border') })

      Column()
        .layoutWeight(1)
        .width('100%')
        .onClick(() => this.onDismiss())
    }
    .width('100%')
    .height('100%')
  }
}
