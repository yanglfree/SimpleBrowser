import { AppIcon, IconName } from './AppIcon';

/** Native share actions keep saving a page available without leaving the app. */
@Component
export struct SharePanel {
  @Prop title: string = '';
  @Prop host: string = '';
  onDismiss: () => void = (): void => {};
  onSystemShare: () => void = (): void => {};
  onCopy: () => void = (): void => {};
  onSaveLater: () => void = (): void => {};

  build() {
    Column() {
      Column()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.onDismiss())

      this.Panel()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private Panel() {
    Column({ space: 14 }) {
      Row() {
        Text($r('app.string.share_panel_title'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Row() {
          AppIcon({ name: IconName.Close, glyphSize: 16, color: $r('app.color.text_secondary') })
        }
        .width(40)
        .height(40)
        .justifyContent(FlexAlign.Center)
        .onClick(() => this.onDismiss())
      }
      .width('100%')

      Text(this.title.length > 0 ? this.title : this.host)
        .width('100%')
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.host)
        .width('100%')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Row({ space: 10 }) {
        this.Action(IconName.Share, $r('app.string.share_panel_system'), (): void => this.onSystemShare())
        this.Action(IconName.ArrowUpLeft, $r('app.string.share_panel_copy'), (): void => this.onCopy())
        this.Action(IconName.Reader, $r('app.string.share_panel_save_later'), (): void => this.onSaveLater())
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 18, left: 24, right: 24, bottom: 42 })
    .backgroundColor($r('app.color.surface_panel'))
    .borderRadius({ topLeft: 20, topRight: 20 })
  }

  @Builder
  private Action(icon: IconName, label: Resource, onClick: () => void) {
    Column({ space: 8 }) {
      Row() {
        AppIcon({ name: icon, glyphSize: 22, color: $r('app.color.text_primary') })
      }
      .width(48)
      .height(48)
      .justifyContent(FlexAlign.Center)
      .borderRadius(24)
      .backgroundColor($r('app.color.surface_subtle'))
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
    .onClick(onClick)
  }
}
