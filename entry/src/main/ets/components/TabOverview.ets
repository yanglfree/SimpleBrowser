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
  TAB_CARD_HEIGHT,
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
  TAB_OVERVIEW_GRID_GAP,
  TAB_OVERVIEW_HEADER_BOTTOM,
  TAB_OVERVIEW_HEADER_HORIZONTAL,
  TAB_OVERVIEW_HEADER_TOP,
  TAB_OVERVIEW_TITLE_SIZE,
  TAB_PRIVATE_GESTURE_DURATION,
  TAB_THUMB_HEIGHT
} from './TabTokens';

const TAB_OVERVIEW_MIN_CARD_WIDTH: number = 240;
const TAB_OVERVIEW_MAX_COLUMNS: number = 4;
const TAB_OVERVIEW_CONTENT_MAX_WIDTH: number = 1440;

export function tabOverviewColumnCount(availableWidth: number): number {
  const contentWidth: number = Math.max(0, availableWidth - TAB_OVERVIEW_HEADER_HORIZONTAL * 2);
  const columns: number = Math.floor(
    (contentWidth + TAB_OVERVIEW_GRID_GAP) / (TAB_OVERVIEW_MIN_CARD_WIDTH + TAB_OVERVIEW_GRID_GAP)
  );
  return Math.max(1, Math.min(TAB_OVERVIEW_MAX_COLUMNS, columns));
}

export function tabOverviewGridHeight(count: number, columns: number): number {
  const safeColumns: number = Math.max(1, columns);
  const rows: number = Math.ceil(Math.max(0, count) / safeColumns);
  const cards: number = rows * TAB_CARD_HEIGHT + Math.max(rows - 1, 0) * TAB_OVERVIEW_GRID_GAP;
  return cards + TAB_OVERVIEW_GRID_BOTTOM;
}

/** A snapshot of a tab taken the last time it was on screen. */
export interface TabThumbnail {
  id: string;
  shot: image.PixelMap;
}

/**
 * @Builder parameters have to arrive as one object — the `$$` by-reference form —
 * for the builder to re-render. Passed as plain values, a grid keeps showing the
 * tabs it was first handed no matter how many the user closes.
 */
interface TabListParams {
  tabs: BrowserTab[];
}

interface TabCardParams {
  tab: BrowserTab;
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
  /** Status bar height — the overview is drawn behind the system bars. */
  @Prop topInset: number = 0;
  @Prop availableWidth: number = 0;
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
        .constraintSize({ maxWidth: TAB_OVERVIEW_CONTENT_MAX_WIDTH })
        .padding({
          top: TAB_OVERVIEW_HEADER_TOP + this.topInset,
          left: TAB_OVERVIEW_HEADER_HORIZONTAL,
          right: TAB_OVERVIEW_HEADER_HORIZONTAL,
          bottom: TAB_OVERVIEW_HEADER_BOTTOM
        })

        Scroll() {
          Column() {
            this.TabGrid({ tabs: this.tabs })

            if (this.privateTabs.length > 0) {
              Text($r('app.string.private_badge'))
                .width('100%')
                .constraintSize({ maxWidth: TAB_OVERVIEW_CONTENT_MAX_WIDTH })
                .fontSize(TAB_OVERVIEW_TITLE_SIZE)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_secondary'))
                .padding({
                  top: TAB_OVERVIEW_HEADER_BOTTOM,
                  left: TAB_OVERVIEW_HEADER_HORIZONTAL,
                  right: TAB_OVERVIEW_HEADER_HORIZONTAL,
                  bottom: TAB_OVERVIEW_HEADER_BOTTOM
                })
              this.TabGrid({ tabs: this.privateTabs })
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
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
  private TabGrid($$: TabListParams) {
    Grid() {
      ForEach($$.tabs, (tab: BrowserTab) => {
        GridItem() {
          this.TabCard({ tab: tab })
        }
      }, (tab: BrowserTab) => `${tab.id}-${tab.url}-${tab.title}`)
    }
    .columnsTemplate(this.columnsTemplate())
    .columnsGap(TAB_OVERVIEW_GRID_GAP)
    .rowsGap(TAB_OVERVIEW_GRID_GAP)
    // The grid sits in a Scroll, so it cannot inherit a height — it is measured
    // from the row count instead, and the outer Scroll does the scrolling.
    .height(tabOverviewGridHeight($$.tabs.length, this.columnCount()))
    .padding({
      left: TAB_OVERVIEW_HEADER_HORIZONTAL,
      right: TAB_OVERVIEW_HEADER_HORIZONTAL,
      bottom: TAB_OVERVIEW_GRID_BOTTOM
    })
    .width('100%')
    .constraintSize({ maxWidth: TAB_OVERVIEW_CONTENT_MAX_WIDTH })
  }

  @Builder
  private TabCard($$: TabCardParams) {
    Column() {
      Row() {
        Text(this.cardTitle($$.tab))
          .fontSize(TAB_CARD_TITLE_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor($$.tab.id === this.activeTabId
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
          .id(`close-tab-${$$.tab.id}`)
          .width(TAB_CLOSE_HIT_SIZE)
          .height(TAB_CLOSE_HIT_SIZE)
          .justifyContent(FlexAlign.Center)
          .focusable(true)
          .hoverEffect(HoverEffect.Auto)
          .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.9 })
          .onClick(() => this.onClose($$.tab.id))
      }
      .width('100%')
      .padding({
        top: TAB_CARD_HEADER_TOP,
        left: TAB_CARD_HEADER_HORIZONTAL,
        right: TAB_CARD_HEADER_HORIZONTAL,
        bottom: TAB_CARD_HEADER_BOTTOM
      })

      this.Thumbnail({ tab: $$.tab })
    }
    .width('100%')
    .height(TAB_CARD_HEIGHT)
    .clip(true)
    .borderRadius(TAB_CARD_RADIUS)
    .backgroundColor($r('app.color.surface_panel'))
    .border({
      width: $$.tab.id === this.activeTabId ? TAB_CARD_ACTIVE_BORDER : TAB_CARD_BORDER,
      color: $$.tab.id === this.activeTabId ? $r('app.color.accent') : $r('app.color.border')
    })
    .shadow({
      radius: TAB_CARD_SHADOW_RADIUS,
      color: $r('app.color.shadow_soft'),
      offsetX: 0,
      offsetY: TAB_CARD_SHADOW_OFFSET_Y
    })
    .focusable(true)
    .defaultFocus($$.tab.id === this.activeTabId)
    .hoverEffect(HoverEffect.Auto)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.985 })
    .onClick(() => this.onSelect($$.tab.id))
    .gesture(
      PanGesture({ direction: PanDirection.All, distance: TAB_CARD_SWIPE_DISTANCE })
        .onActionEnd((event: GestureEvent) => {
          const horizontal: boolean = Math.abs(event.offsetX) > Math.abs(event.offsetY);
          if (!horizontal && event.offsetY <= -TAB_CARD_CLOSE_SWIPE_DISTANCE) {
            this.onClose($$.tab.id);
          } else if (horizontal && event.offsetX <= -TAB_CARD_SWITCH_SWIPE_DISTANCE) {
            this.onSwitch(1);
          } else if (horizontal && event.offsetX >= TAB_CARD_SWITCH_SWIPE_DISTANCE) {
            this.onSwitch(-1);
          }
        })
    )
  }

  @Builder
  private Thumbnail($$: TabCardParams) {
    Column() {
      // ForEach over a 0-or-1 element list: renders the snapshot when there is
      // one without handing a possibly-undefined PixelMap to Image().
      ForEach(this.thumbnailsFor($$.tab.id), (item: TabThumbnail) => {
        Image(item.shot)
          .width('100%')
          .height(TAB_THUMB_HEIGHT)
          .objectFit(ImageFit.Cover)
      }, (item: TabThumbnail) => item.id)

      if (this.thumbnailsFor($$.tab.id).length === 0) {
        this.ThumbnailPlaceholder({ tab: $$.tab })
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
  private ThumbnailPlaceholder($$: TabCardParams) {
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
    .opacity($$.tab.isPrivate ? 0.5 : 1)
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
    .focusable(true)
    .hoverEffect(HoverEffect.Auto)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.96 })
    .onClick(() => this.onNewTab())
    .gesture(
      LongPressGesture({ repeat: false, duration: TAB_PRIVATE_GESTURE_DURATION })
        .onAction(() => this.onNewPrivateTab())
    )
  }

  private thumbnailsFor(id: string): TabThumbnail[] {
    if (this.privateTabs.some((tab: BrowserTab): boolean => tab.id === id)) {
      return [];
    }
    return this.thumbnails.filter((item: TabThumbnail) => item.id === id);
  }

  private columnCount(): number {
    return tabOverviewColumnCount(this.availableWidth);
  }

  private columnsTemplate(): string {
    return new Array<string>(this.columnCount()).fill('1fr').join(' ');
  }

  private cardTitle(tab: BrowserTab): ResourceStr {
    if (isHomeUrl(tab.url)) {
      return $r('app.string.new_tab');
    }
    const host: string = displayHost(tab.url);
    return host.length > 0 ? host : tab.title;
  }
}
