/**
 * Confirmation surface for web-origin permissions. Native permission prompts
 * are only requested after the user has understood and accepted this sheet.
 */
@Component
export struct PermissionSheet {
  @Prop origin: string = '';
  @Prop resources: Resource[] = [];
  onAllow: () => void = (): void => {};
  onDeny: () => void = (): void => {};

  build() {
    Column() {
      Column()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.onDeny())

      Column() {
        Row()
          .width(36)
          .height(4)
          .borderRadius(2)
          .backgroundColor($r('app.color.handle'))
          .margin({ bottom: 16 })

        Text($r('app.string.site_permission_request_title'))
          .width('100%')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))

        Text(this.origin)
          .width('100%')
          .margin({ top: 8 })
          .fontSize(14)
          .fontColor($r('app.color.accent'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text($r('app.string.site_permission_request_message'))
          .width('100%')
          .margin({ top: 14 })
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))

        Column() {
          ForEach(this.resources, (resource: Resource) => {
            Text(resource)
              .width('100%')
              .height(44)
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
              .border({ width: { bottom: 1 }, color: $r('app.color.border') })
          }, (resource: Resource, index: number) => `${index}`)
        }
        .width('100%')
        .margin({ top: 12 })

        Row({ space: 12 }) {
          Text($r('app.string.site_permission_deny'))
            .layoutWeight(1)
            .height(48)
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
            .borderRadius(16)
            .backgroundColor($r('app.color.surface_subtle'))
            .onClick(() => this.onDeny())
          Text($r('app.string.site_permission_allow'))
            .layoutWeight(1)
            .height(48)
            .fontSize(15)
            .fontColor(Color.White)
            .textAlign(TextAlign.Center)
            .borderRadius(16)
            .backgroundColor($r('app.color.accent'))
            .onClick(() => this.onAllow())
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
