import { image } from '@kit.ImageKit';
import { BrowserTab } from '../models/BrowserModels';
import { displayHost, isHomeUrl } from '../utils/UrlUtils';
import { AppIcon, IconName } from './AppIcon';
import {
  TAB_CARD_ACTIVE_BORDER,
  TAB_CARD_BORDER,
  TAB_CARD_CLOSE_ICON_SIZE,
  TAB_CARD_CLOSE_SWIPE_DISTANCE,
  TAB_CARD_HEADER_BOTTOM,
  TAB_CARD_HEADER_HORIZONTAL,
  TAB_CARD_HEADER_TOP,
  TAB_CARD_RADIUS,
  TAB_CARD_SHADOW_OFFSET_Y,
  TAB_CARD_SHADOW_RADIUS,
  TAB_CARD_SWITCH_SWIPE_DISTANCE,
  TAB_CARD_SWIPE_DISTANCE,
  TAB_CARD_TITLE_SIZE,
  TAB_CLOSE_HIT_SIZE,
  TAB_CONTROL_GAP,
  TAB_NEW_BUTTON_BOTTOM_MARGIN,
  TAB_NEW_BUTTON_HEIGHT,
  TAB_NEW_BUTTON_HORIZONTAL_PADDING,
  TAB_NEW_BUTTON_ICON_SIZE,
  TAB_NEW_BUTTON_RADIUS,
  TAB_NEW_BUTTON_TEXT_SIZE,
  TAB_OVERVIEW_ACTION_SIZE,
  TAB_OVERVIEW_GRID_BOTTOM,
  TAB_OVERVIEW_HEADER_BOTTOM,
  TAB_OVERVIEW_HEADER_HORIZONTAL,
  TAB_OVERVIEW_HEADER_TOP,
  TAB_OVERVIEW_TITLE_SIZE,
  TAB_PRIVATE_GESTURE_DURATION,
  TAB_STACK_HEIGHT,
  TAB_STACK_OFFSET,
  TAB_THUMB_HEIGHT
} from './TabTokens';

/** A snapshot of a tab taken the last time it was on screen. */
export interface TabThumbnail {
  id: string;
  shot: image.PixelMap;
}

/**
 * 1e — two columns of cards, the active tab outlined in ink green. Reached by
 * continuing to swipe up from the action sheet.
 */
@Component
export struct TabOverview {
  @Prop tabs: BrowserTab[] = [];
  @Prop privateTabs: BrowserTab[] = [];
  @Prop activeTabId: string = '';
  /** Snapshots captured when a tab was last on screen; absent for a cold tab. */
  thumbnails: TabThumbnail[] = [];
  onSelect: (id: string) => void = (_id: string): void => {};
  onSwitch: (direction: number) => void = (_direction: number): void => {};
  onClose: (id: string) => void = (_id: string): void => {};
  onCloseAll: () => void = (): void => {};
  onNewTab: () => void = (): void => {};
  onNewPrivateTab: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Text() {
            Span(`${this.tabs.length + this.privateTabs.length}`)
            Span(' ')
            Span($r('app.string.tabs_count_suffix'))
          }
          .fontSize(TAB_OVERVIEW_TITLE_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .fontFeature('"tnum" 1')
          .layoutWeight(1)

          Text($r('app.string.close_all_tabs'))
            .fontSize(TAB_OVERVIEW_ACTION_SIZE)
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => this.onCloseAll())
        }
        .width('100%')
        .padding({
          top: TAB_OVERVIEW_HEADER_TOP,
          left: TAB_OVERVIEW_HEADER_HORIZONTAL,
          right: TAB_OVERVIEW_HEADER_HORIZONTAL,
          bottom: TAB_OVERVIEW_HEADER_BOTTOM
        })

        Scroll() {
          Column({ space: 12 }) {
            this.TabStack(this.tabs)

            if (this.privateTabs.length > 0) {
              Text($r('app.string.private_badge'))
                .width('100%')
                .fontSize(TAB_OVERVIEW_TITLE_SIZE)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .padding({
                  top: TAB_OVERVIEW_HEADER_BOTTOM,
                  left: TAB_OVERVIEW_HEADER_HORIZONTAL,
                  right: TAB_OVERVIEW_HEADER_HORIZONTAL,
                  bottom: TAB_OVERVIEW_HEADER_BOTTOM
                })
              this.TabStack(this.privateTabs)
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')

      this.NewTabButton()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private TabStack(tabs: BrowserTab[]) {
    Stack({ alignContent: Alignment.Top }) {
      ForEach(this.stackTabs(tabs), (tab: BrowserTab, index: number) => {
        this.TabCard(tab, index, tabs.length)
      }, (tab: BrowserTab) => tab.id)
    }
    .height(TAB_STACK_HEIGHT)
    .padding({
      left: TAB_OVERVIEW_HEADER_HORIZONTAL,
      right: TAB_OVERVIEW_HEADER_HORIZONTAL,
      bottom: TAB_OVERVIEW_GRID_BOTTOM
    })
    .width('100%')
  }

  @Builder
  private TabCard(tab: BrowserTab, stackIndex: number = 0, stackCount: number = 1) {
    Column() {
      Row() {
        Text(this.cardTitle(tab))
          .fontSize(TAB_CARD_TITLE_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(tab.id === this.activeTabId
            ? $r('app.color.text_primary')
            : $r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Row() {
          AppIcon({
            name: IconName.Close,
            glyphSize: TAB_CARD_CLOSE_ICON_SIZE,
            color: $r('app.color.text_secondary')
          })
        }
          .id(`close-tab-${tab.id}`)
          .width(TAB_CLOSE_HIT_SIZE)
          .height(TAB_CLOSE_HIT_SIZE)
          .justifyContent(FlexAlign.Center)
          .onClick(() => this.onClose(tab.id))
      }
      .width('100%')
      .padding({
        top: TAB_CARD_HEADER_TOP,
        left: TAB_CARD_HEADER_HORIZONTAL,
        right: TAB_CARD_HEADER_HORIZONTAL,
        bottom: TAB_CARD_HEADER_BOTTOM
      })

      this.Thumbnail(tab)
    }
    .width('100%')
    .clip(true)
    .borderRadius(TAB_CARD_RADIUS)
    .backgroundColor($r('app.color.surface_panel'))
    .border({
      width: tab.id === this.activeTabId ? TAB_CARD_ACTIVE_BORDER : TAB_CARD_BORDER,
      color: tab.id === this.activeTabId ? $r('app.color.accent') : $r('app.color.border')
    })
    .shadow({
      radius: TAB_CARD_SHADOW_RADIUS,
      color: $r('app.color.shadow_soft'),
      offsetX: 0,
      offsetY: TAB_CARD_SHADOW_OFFSET_Y
    })
    .align(Alignment.Top)
    .translate({ y: Math.min(stackIndex, 3) * TAB_STACK_OFFSET })
    .scale({
      x: 1 - Math.min(stackIndex, 3) * 0.035,
      y: 1 - Math.min(stackIndex, 3) * 0.035
    })
    .zIndex(stackCount - stackIndex)
    .animation({ duration: 180, curve: Curve.FastOutSlowIn })
    .onClick(() => this.onSelect(tab.id))
    .gesture(
      PanGesture({ direction: PanDirection.All, distance: TAB_CARD_SWIPE_DISTANCE })
        .onActionEnd((event: GestureEvent) => {
          const horizontal: boolean = Math.abs(event.offsetX) > Math.abs(event.offsetY);
          if (!horizontal && event.offsetY <= -TAB_CARD_CLOSE_SWIPE_DISTANCE) {
            this.onClose(tab.id);
          } else if (horizontal && event.offsetX <= -TAB_CARD_SWITCH_SWIPE_DISTANCE) {
            this.onSwitch(1);
          } else if (horizontal && event.offsetX >= TAB_CARD_SWITCH_SWIPE_DISTANCE) {
            this.onSwitch(-1);
          }
        })
    )
  }

  @Builder
  private Thumbnail(tab: BrowserTab) {
    Column() {
      // ForEach over a 0-or-1 element list: renders the snapshot when there is
      // one without handing a possibly-undefined PixelMap to Image().
      ForEach(this.thumbnailsFor(tab.id), (item: TabThumbnail) => {
        Image(item.shot)
          .width('100%')
          .height(TAB_THUMB_HEIGHT)
          .objectFit(ImageFit.Cover)
      }, (item: TabThumbnail) => item.id)

      if (this.thumbnailsFor(tab.id).length === 0) {
        this.ThumbnailPlaceholder(tab)
      }
    }
    .width('100%')
    .height(TAB_THUMB_HEIGHT)
    .clip(true)
    .backgroundColor($r('app.color.page_background'))
    .border({ width: { top: 1 }, color: $r('app.color.border') })
  }

  /** Shown until the tab has been on screen once and could be snapshotted. */
  @Builder
  private ThumbnailPlaceholder(tab: BrowserTab) {
    Column({ space: 8 }) {
      Row()
        .width('40%')
        .height(6)
        .borderRadius(3)
        .backgroundColor($r('app.color.skeleton_weak'))
      Row()
        .width('92%')
        .height(9)
        .borderRadius(4)
        .backgroundColor($r('app.color.skeleton_strong'))
      Row()
        .width('70%')
        .height(9)
        .borderRadius(4)
        .backgroundColor($r('app.color.skeleton_strong'))
      Row()
        .width('100%')
        .height(70)
        .borderRadius(8)
        .backgroundColor($r('app.color.surface_subtle'))
        .margin({ top: 6 })
      Row()
        .width('88%')
        .height(6)
        .borderRadius(3)
        .backgroundColor($r('app.color.skeleton_weak'))
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, left: 12, right: 12 })
    .opacity(tab.isPrivate ? 0.5 : 1)
  }

  @Builder
  private NewTabButton() {
    Row({ space: TAB_CONTROL_GAP }) {
      AppIcon({
        name: IconName.Plus,
        glyphSize: TAB_NEW_BUTTON_ICON_SIZE,
        color: $r('app.color.text_primary')
      })
      Text($r('app.string.new_tab'))
        .fontSize(TAB_NEW_BUTTON_TEXT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
    }
    .height(TAB_NEW_BUTTON_HEIGHT)
    .padding({ left: TAB_NEW_BUTTON_HORIZONTAL_PADDING, right: TAB_NEW_BUTTON_HORIZONTAL_PADDING })
    .justifyContent(FlexAlign.Center)
    .borderRadius(TAB_NEW_BUTTON_RADIUS)
    .backgroundColor($r('app.color.surface_panel'))
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({ radius: 12, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: 2 })
    .margin({ bottom: TAB_NEW_BUTTON_BOTTOM_MARGIN })
    .onClick(() => this.onNewTab())
    .gesture(
      LongPressGesture({ repeat: false, duration: TAB_PRIVATE_GESTURE_DURATION })
        .onAction(() => this.onNewPrivateTab())
    )
  }

  private thumbnailsFor(id: string): TabThumbnail[] {
    return this.thumbnails.filter((item: TabThumbnail) => item.id === id);
  }

  private stackTabs(tabs: BrowserTab[]): BrowserTab[] {
    const active: BrowserTab[] = tabs.filter((tab: BrowserTab) => tab.id === this.activeTabId);
    const inactive: BrowserTab[] = tabs.filter((tab: BrowserTab) => tab.id !== this.activeTabId);
    return active.concat(inactive);
  }

  private cardTitle(tab: BrowserTab): ResourceStr {
    if (isHomeUrl(tab.url)) {
      return $r('app.string.new_tab');
    }
    const host: string = displayHost(tab.url);
    return host.length > 0 ? host : tab.title;
  }
}
