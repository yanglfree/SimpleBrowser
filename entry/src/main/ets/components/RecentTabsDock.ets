import { BrowserTab } from '../models/BrowserModels';
import { displayHost, isHomeUrl } from '../utils/UrlUtils';
import { AppIcon, IconName } from './AppIcon';
import {
  RECENT_TAB_CARD_GAP,
  RECENT_TAB_CARD_HEIGHT,
  RECENT_TAB_CARD_CONTENT_GAP,
  RECENT_TAB_CARD_HORIZONTAL_PADDING,
  RECENT_TAB_CARD_META_SIZE,
  RECENT_TAB_CARD_RADIUS,
  RECENT_TAB_CARD_TITLE_SIZE,
  RECENT_TAB_CARD_WIDTH,
  RECENT_TAB_ACTIVE_DOT_SIZE,
  RECENT_TAB_NEW_CONTENT_GAP,
  RECENT_TAB_NEW_ICON_SIZE,
  RECENT_TABS_DOCK_ACTION_SIZE,
  RECENT_TABS_DOCK_ACTION_LEFT_PADDING,
  RECENT_TABS_DOCK_ACTION_VERTICAL_PADDING,
  RECENT_TABS_DOCK_BOTTOM_PADDING,
  RECENT_TABS_DOCK_HANDLE_HEIGHT,
  RECENT_TABS_DOCK_HANDLE_WIDTH,
  RECENT_TABS_DOCK_HEADER_SIZE,
  RECENT_TABS_DOCK_HORIZONTAL_PADDING,
  RECENT_TABS_DOCK_LIST_HEIGHT,
  RECENT_TABS_DOCK_MAX_WIDTH,
  RECENT_TABS_DOCK_RADIUS,
  RECENT_TABS_DOCK_SECTION_GAP,
  RECENT_TABS_DOCK_SHADOW_OFFSET_Y,
  RECENT_TABS_DOCK_SHADOW_RADIUS,
  TAB_CARD_ACTIVE_BORDER,
  TAB_CARD_BORDER,
  RECENT_TABS_DOCK_TOP_PADDING
} from './TabTokens';

interface RecentTabParams {
  tab: BrowserTab;
}

/** The middle layer of tab navigation: one-touch access to the current working set. */
@Component
export struct RecentTabsDock {
  @Prop tabs: BrowserTab[] = [];
  @Prop activeTabId: string = '';
  onDismiss: () => void = (): void => {};
  onSelect: (id: string) => void = (): void => {};
  onOpenAll: () => void = (): void => {};
  onNewTab: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.onDismiss())

      Column({ space: RECENT_TABS_DOCK_SECTION_GAP }) {
        Row()
          .width(RECENT_TABS_DOCK_HANDLE_WIDTH)
          .height(RECENT_TABS_DOCK_HANDLE_HEIGHT)
          .borderRadius(RECENT_TABS_DOCK_HANDLE_HEIGHT / 2)
          .backgroundColor($r('app.color.handle'))

        Row() {
          Text($r('app.string.recent_tabs_title'))
            .fontSize(RECENT_TABS_DOCK_HEADER_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Text($r('app.string.all_tabs'))
            .id('recent-tabs-all')
            .fontSize(RECENT_TABS_DOCK_ACTION_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent'))
            .padding({
              top: RECENT_TABS_DOCK_ACTION_VERTICAL_PADDING,
              bottom: RECENT_TABS_DOCK_ACTION_VERTICAL_PADDING,
              left: RECENT_TABS_DOCK_ACTION_LEFT_PADDING
            })
            .onClick(() => this.onOpenAll())
        }
        .width('100%')

        List({ space: RECENT_TAB_CARD_GAP }) {
          ForEach(this.tabs, (tab: BrowserTab) => {
            ListItem() {
              this.RecentTab({ tab: tab })
            }
          }, (tab: BrowserTab) => `${tab.id}-${tab.lastVisitedAt}`)

          ListItem() {
            this.NewTab()
          }
        }
        .width('100%')
        .height(RECENT_TABS_DOCK_LIST_HEIGHT)
        .listDirection(Axis.Horizontal)
        .scrollBar(BarState.Off)
      }
      .id('recent-tabs-dock')
      .width('100%')
      .constraintSize({ maxWidth: RECENT_TABS_DOCK_MAX_WIDTH })
      .alignItems(HorizontalAlign.Center)
      .padding({
        top: RECENT_TABS_DOCK_TOP_PADDING,
        left: RECENT_TABS_DOCK_HORIZONTAL_PADDING,
        right: RECENT_TABS_DOCK_HORIZONTAL_PADDING,
        bottom: RECENT_TABS_DOCK_BOTTOM_PADDING
      })
      .borderRadius({ topLeft: RECENT_TABS_DOCK_RADIUS, topRight: RECENT_TABS_DOCK_RADIUS })
      .backgroundColor($r('app.color.surface_panel'))
      .shadow({
        radius: RECENT_TABS_DOCK_SHADOW_RADIUS,
        color: $r('app.color.shadow_soft'),
        offsetY: RECENT_TABS_DOCK_SHADOW_OFFSET_Y
      })
      // Consume taps inside the panel so they never reach the page behind the scrim.
      .onClick((): void => {})
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private RecentTab($$: RecentTabParams) {
    Column({ space: RECENT_TAB_CARD_CONTENT_GAP }) {
      Row({ space: RECENT_TAB_CARD_CONTENT_GAP }) {
        if ($$.tab.id === this.activeTabId) {
          Row()
            .width(RECENT_TAB_ACTIVE_DOT_SIZE)
            .height(RECENT_TAB_ACTIVE_DOT_SIZE)
            .borderRadius(RECENT_TAB_ACTIVE_DOT_SIZE / 2)
            .backgroundColor($r('app.color.accent'))
        }
        Text(this.tabTitle($$.tab))
          .fontSize(RECENT_TAB_CARD_TITLE_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')

      Text($$.tab.isPrivate ? $r('app.string.private_badge') : this.tabHost($$.tab))
        .fontSize(RECENT_TAB_CARD_META_SIZE)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .id(`recent-tab-${$$.tab.id}`)
    .width(RECENT_TAB_CARD_WIDTH)
    .height(RECENT_TAB_CARD_HEIGHT)
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .padding({ left: RECENT_TAB_CARD_HORIZONTAL_PADDING, right: RECENT_TAB_CARD_HORIZONTAL_PADDING })
    .borderRadius(RECENT_TAB_CARD_RADIUS)
    .backgroundColor($$.tab.id === this.activeTabId
      ? $r('app.color.surface_subtle')
      : $r('app.color.page_background'))
    .border({
      width: $$.tab.id === this.activeTabId ? TAB_CARD_ACTIVE_BORDER : TAB_CARD_BORDER,
      color: $$.tab.id === this.activeTabId ? $r('app.color.accent') : $r('app.color.border')
    })
    .onClick(() => this.onSelect($$.tab.id))
  }

  @Builder
  private NewTab() {
    Column({ space: RECENT_TAB_NEW_CONTENT_GAP }) {
      AppIcon({
        name: IconName.Plus,
        glyphSize: RECENT_TAB_NEW_ICON_SIZE,
        color: $r('app.color.accent_strong')
      })
      Text($r('app.string.new_tab'))
        .fontSize(RECENT_TAB_CARD_META_SIZE)
        .fontColor($r('app.color.text_secondary'))
        .maxLines(1)
    }
    .id('recent-tabs-new')
    .width(RECENT_TAB_CARD_HEIGHT)
    .height(RECENT_TAB_CARD_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .borderRadius(RECENT_TAB_CARD_RADIUS)
    .backgroundColor($r('app.color.page_background'))
    .border({ width: TAB_CARD_BORDER, color: $r('app.color.border') })
    .onClick(() => this.onNewTab())
  }

  private tabTitle(tab: BrowserTab): ResourceStr {
    if (isHomeUrl(tab.url)) {
      return $r('app.string.new_tab');
    }
    const title: string = tab.title.trim();
    return title.length > 0 ? title : this.tabHost(tab);
  }

  private tabHost(tab: BrowserTab): ResourceStr {
    const host: string = displayHost(tab.url);
    return host.length > 0 ? host : $r('app.string.new_tab');
  }
}
