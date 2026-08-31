import { BrowserTab, LoadErrorKind } from '../models/BrowserModels';
import { displayHost, isHomeUrl } from '../utils/UrlUtils';
import { AppIcon, IconName } from './AppIcon';
import { TabThumbnail } from './TabOverview';

export const DESKTOP_TAB_STRIP_HEIGHT: number = 44;

const TAB_STRIP_MIN_TAB_WIDTH: number = 88;
const TAB_STRIP_MAX_TAB_WIDTH: number = 240;
const TAB_STRIP_PINNED_WIDTH: number = 52;
const TAB_STRIP_HORIZONTAL_PADDING: number = 16;
const TAB_STRIP_NEW_TAB_WIDTH: number = 36;
const TAB_STRIP_ITEM_GAP: number = 4;
const TAB_STRIP_TAB_HEIGHT: number = 36;
/**
 * Rounded at the top only and flush with the strip's bottom edge: the active tab
 * has to run into the toolbar to read as the toolbar's tab rather than a card
 * floating on the rail.
 */
const TAB_STRIP_TAB_RADIUS: BorderRadiuses = {
  topLeft: 10,
  topRight: 10,
  bottomLeft: 0,
  bottomRight: 0
};
const TAB_STRIP_FAVICON_SIZE: number = 15;
const TAB_REORDER_DISTANCE: number = 36;
const TAB_PREVIEW_DELAY_MS: number = 350;
const ESCAPE_KEY_CODE: number = 2070;
const TAB_ADJUST_LONG_PRESS_MS: number = 450;
const TAB_ADJUST_SHIFT_DURATION: number = 160;
const TAB_ADJUST_LIFT_SCALE: number = 1.06;

/**
 * Where a tab dragged by `offsetX` would land. Whole slots only: a tab has to be
 * dragged past the middle of its neighbour before the neighbour gives way, which
 * is what stops a tab jittering between two positions under a shaky finger.
 */
export function tabDragDropIndex(
  fromIndex: number,
  tabCount: number,
  offsetX: number,
  slotWidth: number
): number {
  if (fromIndex < 0 || fromIndex >= tabCount || slotWidth <= 0) {
    return -1;
  }
  const moved: number = Math.round(offsetX / slotWidth);
  return Math.min(Math.max(fromIndex + moved, 0), tabCount - 1);
}

/**
 * How far a tab that is not being dragged has to step aside. Everything between
 * the tab's old and new index shifts one slot towards the gap it came from.
 */
export function tabReorderShift(
  index: number,
  fromIndex: number,
  dropIndex: number,
  slotWidth: number
): number {
  if (fromIndex < 0 || dropIndex < 0 || index === fromIndex) {
    return 0;
  }
  if (fromIndex < dropIndex && index > fromIndex && index <= dropIndex) {
    return -slotWidth;
  }
  if (fromIndex > dropIndex && index >= dropIndex && index < fromIndex) {
    return slotWidth;
  }
  return 0;
}

export function desktopTabWidth(availableWidth: number, tabCount: number, pinnedCount: number): number {
  const safeTabCount: number = Math.max(0, tabCount);
  const safePinnedCount: number = Math.min(Math.max(0, pinnedCount), safeTabCount);
  const unpinnedCount: number = safeTabCount - safePinnedCount;
  if (unpinnedCount === 0) {
    return TAB_STRIP_MIN_TAB_WIDTH;
  }
  const itemGaps: number = safeTabCount * TAB_STRIP_ITEM_GAP;
  const widthForUnpinnedTabs: number = availableWidth - TAB_STRIP_HORIZONTAL_PADDING -
    TAB_STRIP_NEW_TAB_WIDTH - itemGaps - safePinnedCount * TAB_STRIP_PINNED_WIDTH;
  return Math.min(
    TAB_STRIP_MAX_TAB_WIDTH,
    Math.max(TAB_STRIP_MIN_TAB_WIDTH, Math.floor(widthForUnpinnedTabs / unpinnedCount))
  );
}

@Component
export struct DesktopTabStrip {
  @Prop tabs: BrowserTab[] = [];
  @Prop availableWidth: number = 0;
  @Prop @Watch('activeTabChanged') activeTabId: string = '';
  @Prop thumbnails: TabThumbnail[] = [];
  @Prop liveTabIds: string[] = [];
  @Prop canMoveToWindow: boolean = false;
  onSelect: (id: string) => void = (_id: string): void => {};
  onClose: (id: string) => void = (_id: string): void => {};
  onReorder: (id: string, direction: number) => void = (_id: string, _direction: number): void => {};
  onMoveTab: (id: string, targetIndex: number) => void = (_id: string, _targetIndex: number): void => {};
  onCloseOthers: (id: string) => void = (_id: string): void => {};
  onCopyUrl: (id: string) => void = (_id: string): void => {};
  onTogglePinned: (id: string) => void = (_id: string): void => {};
  onOpenSplit: (id: string) => void = (_id: string): void => {};
  onMoveToWindow: (id: string) => void = (_id: string): void => {};
  onNewTab: () => void = (): void => {};
  private scroller: Scroller = new Scroller();
  private contextTabId: string = '';
  @State private previewTabId: string = '';
  @State private previewVisible: boolean = false;
  private hoverToken: number = 0;
  /** Non-empty while the strip is in adjust mode; holds the tab that was pressed. */
  @State private adjustingTabId: string = '';
  @State private dragOffsetX: number = 0;
  @State private dropIndex: number = -1;

  build() {
    Row({ space: 8 }) {
      List({ space: 4, scroller: this.scroller }) {
        ForEach(this.tabs, (tab: BrowserTab) => {
          ListItem() {
            Column() {
              this.Tab(tab)
            }
            .height(DESKTOP_TAB_STRIP_HEIGHT)
            .justifyContent(FlexAlign.End)
          }
          .width(this.tabWidth(tab))
        }, (tab: BrowserTab): string => `${tab.id}-${tab.isPinned}-${tab.title}`)

        ListItem() {
          Column() {
            Row() {
              AppIcon({ name: IconName.Plus, glyphSize: 17, color: $r('app.color.dock_icon') })
            }
            .id('desktop-new-tab')
            .width(TAB_STRIP_NEW_TAB_WIDTH)
            .height(TAB_STRIP_TAB_HEIGHT)
            .justifyContent(FlexAlign.Center)
            .borderRadius(TAB_STRIP_TAB_RADIUS)
            .focusable(true)
            .hoverEffect(HoverEffect.Auto)
            .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
            .accessibilityText($r('app.string.new_tab'))
            .onClick(() => this.onNewTab())
          }
          .height(DESKTOP_TAB_STRIP_HEIGHT)
          .justifyContent(FlexAlign.End)
        }
        .width(TAB_STRIP_NEW_TAB_WIDTH)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
      .height(DESKTOP_TAB_STRIP_HEIGHT)
      .onAppear(() => this.scrollActiveTabIntoView(false))
      .onScrollIndex((): void => this.dismissPreview())
    }
    .width('100%')
    .height(DESKTOP_TAB_STRIP_HEIGHT)
    .padding({ left: 8, right: 8 })
    .backgroundColor($r('app.color.surface_subtle'))
    .focusable(true)
    .onKeyEvent((event: KeyEvent): boolean => {
      if (event.type === KeyType.Down && event.keyCode === ESCAPE_KEY_CODE) {
        this.dismissPreview();
        this.leaveAdjustMode();
        return true;
      }
      return false;
    })
  }

  @Builder
  private Tab(tab: BrowserTab) {
    Row({ space: 7 }) {
      AppIcon({
        name: tab.isPrivate ? IconName.Incognito : IconName.Globe,
        glyphSize: TAB_STRIP_FAVICON_SIZE,
        color: $r('app.color.text_secondary')
      })
      Text(this.tabTitle(tab))
        .fontSize(13)
        .fontWeight(tab.id === this.activeTabId ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(tab.id === this.activeTabId
          ? $r('app.color.text_primary')
          : $r('app.color.dock_icon'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (!tab.isPinned) {
        Row() {
          AppIcon({ name: IconName.Close, glyphSize: 13, color: $r('app.color.dock_icon') })
        }
        .width(26)
        .height(26)
        .justifyContent(FlexAlign.Center)
        .borderRadius(13)
        .hoverEffect(HoverEffect.Auto)
        .accessibilityText($r('app.string.tab_close'))
        .onClick(() => this.onClose(tab.id))
      }
    }
    .id(`desktop-tab-${tab.id}`)
    .width('100%')
    .height(TAB_STRIP_TAB_HEIGHT)
    .padding({ left: tab.isPinned ? 10 : 12, right: tab.isPinned ? 10 : 5 })
    .borderRadius(TAB_STRIP_TAB_RADIUS)
    .backgroundColor(tab.id === this.activeTabId
      ? $r('app.color.page_background')
      : Color.Transparent)
    .border(this.adjustingTabId === tab.id
      ? { width: 1.5, color: $r('app.color.accent') }
      : { width: 0 })
    .translate({ x: this.tabTranslation(tab) })
    .scale(this.isDragging(tab)
      ? { x: TAB_ADJUST_LIFT_SCALE, y: TAB_ADJUST_LIFT_SCALE }
      : { x: 1, y: 1 })
    // Only the tabs stepping aside animate; the dragged one has to track the
    // finger exactly or it feels like it is being reeled in on elastic.
    .animation({
      duration: this.isDragging(tab) ? 0 : TAB_ADJUST_SHIFT_DURATION,
      curve: Curve.Friction
    })
    .zIndex(this.isDragging(tab) ? 2 : 1)
    .shadow(this.isDragging(tab)
      ? { radius: 12, color: $r('app.color.shadow_soft'), offsetY: 2 }
      : undefined)
    .focusable(true)
    .defaultFocus(tab.id === this.activeTabId)
    .hoverEffect(HoverEffect.Auto)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => {
      // In adjust mode a tap is the way out, not a tab switch — the long press
      // that opened the mode must not read as "open this tab".
      if (this.adjustingTabId.length > 0) {
        this.leaveAdjustMode();
        return;
      }
      this.onSelect(tab.id);
    })
    .onMouse((event: MouseEvent): void => {
      if (event.button === MouseButton.Right && event.action === MouseAction.Press) {
        this.contextTabId = tab.id;
      } else if (event.button === MouseButton.Middle && event.action === MouseAction.Release) {
        this.onClose(tab.id);
      }
    })
    .onHover((isHovering: boolean): void => {
      if (this.adjustingTabId.length > 0) {
        return;
      }
      if (isHovering) {
        this.schedulePreview(tab.id);
      } else {
        this.dismissPreview();
      }
    })
    // One parallel group rather than a long press plus a separate pan: entering
    // adjust mode re-renders the strip, and a pan bound on its own is dropped
    // mid-touch by that rebuild — which broke the press-and-drag-in-one-motion
    // every other tab strip supports.
    .parallelGesture(
      GestureGroup(GestureMode.Parallel,
        LongPressGesture({ repeat: false, duration: TAB_ADJUST_LONG_PRESS_MS })
          .onAction(() => this.enterAdjustMode(tab.id)),
        PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
          .onActionStart((): void => {
            if (this.adjustingTabId === tab.id) {
              this.dragOffsetX = 0;
              this.dropIndex = this.indexOf(tab.id);
            }
          })
          .onActionUpdate((event: GestureEvent): void => {
            if (this.adjustingTabId !== tab.id) {
              return;
            }
            this.dragOffsetX = event.offsetX;
            this.dropIndex = tabDragDropIndex(
              this.indexOf(tab.id),
              this.tabs.length,
              event.offsetX,
              this.slotWidth(tab)
            );
          })
          .onActionEnd((event: GestureEvent): void => {
            if (this.adjustingTabId === tab.id) {
              this.commitDrag(tab.id);
              return;
            }
            // Outside adjust mode the old one-step nudge still works, so
            // reordering never depends on discovering the long press.
            if (Math.abs(event.offsetX) >= TAB_REORDER_DISTANCE) {
              this.onReorder(tab.id, event.offsetX < 0 ? 1 : -1);
            }
          })
      )
    )
    .bindContextMenu(this.TabContextMenu, ResponseType.RightClick)
    .bindPopup(this.previewVisible && this.previewTabId === tab.id, {
      builder: this.HoverPreview,
      placement: Placement.Bottom,
      enableArrow: false
    })
  }

  @Builder
  private HoverPreview() {
    ForEach(this.previewTabs(), (tab: BrowserTab) => {
      Column() {
        if (!tab.isPrivate && this.thumbnailFor(tab.id).length > 0) {
          Image(this.thumbnailFor(tab.id)[0].shot)
            .width(252)
            .height(138)
            .objectFit(ImageFit.Cover)
        } else {
          Column({ space: 8 }) {
            AppIcon({
              name: tab.isPrivate ? IconName.Incognito : IconName.Tabs,
              glyphSize: 26,
              color: $r('app.color.text_secondary')
            })
            Text(this.previewState(tab))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
          .width(252)
          .height(138)
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.surface_subtle'))
        }
        Column({ space: 3 }) {
          Text(this.tabTitle(tab))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(displayHost(tab.url))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(12)
      }
      .width(252)
      .clip(true)
      .borderRadius(14)
    }, (tab: BrowserTab): string => tab.id)
  }

  @Builder
  private TabContextMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.tab_close') })
        .onClick(() => this.onClose(this.contextTabId))
      MenuItem({ content: $r('app.string.tab_close_others') })
        .onClick(() => this.onCloseOthers(this.contextTabId))
      MenuItem({ content: $r('app.string.tab_copy_url') })
        .onClick(() => this.onCopyUrl(this.contextTabId))
      MenuItem({ content: $r('app.string.tab_open_right') })
        .onClick(() => this.onOpenSplit(this.contextTabId))
      if (this.canMoveToWindow) {
        MenuItem({ content: $r('app.string.tab_move_new_window') })
          .onClick(() => this.onMoveToWindow(this.contextTabId))
      }
      if (!this.contextTab()?.isPrivate) {
        MenuItem({ content: this.contextTab()?.isPinned === true
          ? $r('app.string.tab_unpin')
          : $r('app.string.tab_pin') })
          .onClick(() => this.onTogglePinned(this.contextTabId))
      }
    }
  }

  private contextTab(): BrowserTab | undefined {
    return this.tabs.find((tab: BrowserTab): boolean => tab.id === this.contextTabId);
  }

  private activeTabChanged(): void {
    this.dismissPreview();
    this.scrollActiveTabIntoView(true);
  }

  private enterAdjustMode(tabId: string): void {
    if (this.adjustingTabId === tabId) {
      return;
    }
    this.dismissPreview();
    this.adjustingTabId = tabId;
    this.dragOffsetX = 0;
    this.dropIndex = this.indexOf(tabId);
  }

  private leaveAdjustMode(): void {
    this.adjustingTabId = '';
    this.dragOffsetX = 0;
    this.dropIndex = -1;
  }

  private commitDrag(tabId: string): void {
    const from: number = this.indexOf(tabId);
    const target: number = this.dropIndex;
    this.leaveAdjustMode();
    if (from >= 0 && target >= 0 && target !== from) {
      this.onMoveTab(tabId, target);
    }
  }

  private isDragging(tab: BrowserTab): boolean {
    return this.adjustingTabId === tab.id && this.dropIndex >= 0;
  }

  private tabTranslation(tab: BrowserTab): number {
    if (this.adjustingTabId.length === 0) {
      return 0;
    }
    if (this.adjustingTabId === tab.id) {
      return this.dragOffsetX;
    }
    const from: number = this.indexOf(this.adjustingTabId);
    const dragged: BrowserTab | undefined = this.tabs[from];
    if (dragged === undefined) {
      return 0;
    }
    return tabReorderShift(this.indexOf(tab.id), from, this.dropIndex, this.slotWidth(dragged));
  }

  private indexOf(tabId: string): number {
    return this.tabs.findIndex((tab: BrowserTab): boolean => tab.id === tabId);
  }

  /** A tab's footprint in the strip: its own width plus the gap that follows it. */
  private slotWidth(tab: BrowserTab): number {
    return this.tabWidth(tab) + TAB_STRIP_ITEM_GAP;
  }

  private schedulePreview(tabId: string): void {
    this.hoverToken += 1;
    const token: number = this.hoverToken;
    setTimeout((): void => {
      if (token === this.hoverToken) {
        this.previewTabId = tabId;
        this.previewVisible = true;
      }
    }, TAB_PREVIEW_DELAY_MS);
  }

  private dismissPreview(): void {
    this.hoverToken += 1;
    this.previewVisible = false;
  }

  private previewTabs(): BrowserTab[] {
    return this.tabs.filter((tab: BrowserTab): boolean => tab.id === this.previewTabId).slice(0, 1);
  }

  private thumbnailFor(tabId: string): TabThumbnail[] {
    return this.thumbnails.filter((thumbnail: TabThumbnail): boolean => thumbnail.id === tabId).slice(0, 1);
  }

  private previewState(tab: BrowserTab): ResourceStr {
    if (tab.isPrivate) {
      return $r('app.string.tab_preview_private');
    }
    if (tab.isLoading) {
      return $r('app.string.tab_preview_loading');
    }
    if (tab.loadError !== LoadErrorKind.None) {
      return $r('app.string.tab_preview_unavailable');
    }
    if (!isHomeUrl(tab.url) && !this.liveTabIds.includes(tab.id)) {
      return $r('app.string.tab_preview_sleeping');
    }
    return $r('app.string.tab_preview_unavailable');
  }

  private scrollActiveTabIntoView(smooth: boolean): void {
    const index: number = this.tabs.findIndex((tab: BrowserTab): boolean => tab.id === this.activeTabId);
    if (index >= 0) {
      this.scroller.scrollToIndex(index, smooth, ScrollAlign.CENTER);
    }
  }

  private tabWidth(tab: BrowserTab): number {
    if (tab.isPinned) {
      return TAB_STRIP_PINNED_WIDTH;
    }
    const pinnedCount: number = this.tabs.filter((item: BrowserTab): boolean => item.isPinned).length;
    return desktopTabWidth(this.availableWidth, this.tabs.length, pinnedCount);
  }

  private tabTitle(tab: BrowserTab): ResourceStr {
    if (tab.isPinned) {
      const host: string = displayHost(tab.url);
      return host.length > 0 ? host.slice(0, 1).toUpperCase() : '+';
    }
    if (tab.title.length > 0) {
      return tab.title;
    }
    return isHomeUrl(tab.url) ? $r('app.string.new_tab') : displayHost(tab.url);
  }
}
