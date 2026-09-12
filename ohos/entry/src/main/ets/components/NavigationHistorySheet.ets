import { AppIcon, IconName } from './AppIcon';
import { WebHistoryEntry } from '../services/WebKernelService';

@Component
export struct NavigationHistorySheet {
  @Prop entries: WebHistoryEntry[] = [];
  onDismiss: () => void = (): void => {};
  onSelect: (step: number) => void = (_step: number): void => {};

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
    Column() {
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor($r('app.color.handle'))

      Row({ space: 12 }) {
        Text($r('app.string.navigation_history_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        AppIcon({ name: IconName.Close, glyphSize: 18, color: $r('app.color.text_secondary') })
          .onClick(() => this.onDismiss())
      }
      .width('100%')
      .margin({ top: 16, bottom: 12 })

      Divider()
        .strokeWidth(1)
        .color($r('app.color.border'))

      if (this.entries.length === 0) {
        Text($r('app.string.navigation_history_empty'))
          .width('100%')
          .height(72)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
          .padding({ top: 28 })
      } else {
        Scroll() {
          Column() {
            ForEach(this.entries, (entry: WebHistoryEntry) => {
              Column({ space: 4 }) {
                Text(entry.title)
                  .width('100%')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(entry.url)
                  .width('100%')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .padding({ top: 13, bottom: 13 })
              .onClick(() => this.onSelect(entry.step))
            }, (entry: WebHistoryEntry) => `${entry.step}-${entry.url}`)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 10, left: 24, right: 24, bottom: 34 })
    .backgroundColor($r('app.color.surface_panel'))
    .borderRadius({ topLeft: 20, topRight: 20 })
    .shadow({ radius: 12, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: -2 })
  }
}
