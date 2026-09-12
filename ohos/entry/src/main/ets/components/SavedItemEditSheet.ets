import { AppIcon, IconName } from './AppIcon';

/**
 * Rename or delete a single saved page. It is the management surface for the
 * favorites list; adding a bookmark stays one tap away in the menu.
 */
@Component
export struct SavedItemEditSheet {
  @Prop title: string = '';
  @Prop host: string = '';
  @State private name: string = '';
  onSave: (title: string) => void = (_title: string): void => {};
  onDelete: () => void = (): void => {};
  onDismiss: () => void = (): void => {};

  aboutToAppear(): void {
    this.name = this.title;
  }

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
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor($r('app.color.handle'))

      Row({ space: 10 }) {
        Text($r('app.string.edit_favorite_title'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        AppIcon({ name: IconName.Close, glyphSize: 16, color: $r('app.color.text_secondary') })
          .onClick(() => this.onDismiss())
      }
      .width('100%')

      Text(this.host)
        .width('100%')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      TextInput({ text: this.name, placeholder: $r('app.string.favorite_name') })
        .id('favorite-name-input')
        .defaultFocus(true)
        .width('100%')
        .height(46)
        .padding({ left: 14, right: 14 })
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.surface_subtle'))
        .borderRadius(12)
        .caretColor($r('app.color.accent'))
        .onChange((value: string): void => {
          this.name = value;
        })

      Row({ space: 12 }) {
        Row() {
          Text($r('app.string.favorite_delete'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.danger'))
        }
        .height(46)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .borderRadius(12)
        .backgroundColor($r('app.color.surface_subtle'))
        .onClick(() => this.onDelete())

        Row() {
          Text($r('app.string.favorite_save'))
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_background'))
        }
        .height(46)
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .borderRadius(12)
        .backgroundColor($r('app.color.accent'))
        .onClick(() => this.onSave(this.name))
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 10, left: 24, right: 24, bottom: 42 })
    .backgroundColor($r('app.color.surface_panel'))
    .borderRadius({ topLeft: 20, topRight: 20 })
  }
}
