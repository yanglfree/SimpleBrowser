import { AppIcon, IconName } from './AppIcon';
import {
  TAB_CONTROL_GAP,
  TAB_LAUNCHER_HEIGHT,
  TAB_LAUNCHER_HORIZONTAL_PADDING,
  TAB_LAUNCHER_ICON_SIZE,
  TAB_LAUNCHER_RADIUS,
  TAB_LAUNCHER_TEXT_SIZE
} from './TabTokens';

/** The visible entry point for tab switching and new-tab creation. */
@Component
export struct TabLauncher {
  @Prop count: number = 1;
  onOpen: () => void = (): void => {};

  build() {
    Row({ space: TAB_CONTROL_GAP }) {
      AppIcon({
        name: IconName.Tabs,
        glyphSize: TAB_LAUNCHER_ICON_SIZE,
        color: $r('app.color.accent_strong')
      })
      Text() {
        Span(`${this.count}`)
          .fontWeight(FontWeight.Medium)
        Span(' ')
        Span($r('app.string.tabs_count_suffix'))
      }
        .fontSize(TAB_LAUNCHER_TEXT_SIZE)
        .fontColor($r('app.color.text_primary'))
        .fontFeature('"tnum" 1')
    }
    .id('tab-launcher')
    .height(TAB_LAUNCHER_HEIGHT)
    .padding({ left: TAB_LAUNCHER_HORIZONTAL_PADDING, right: TAB_LAUNCHER_HORIZONTAL_PADDING })
    .borderRadius(TAB_LAUNCHER_RADIUS)
    .backgroundColor($r('app.color.surface_panel'))
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({ radius: 12, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: 2 })
    .onClick(() => this.onOpen())
  }
}
