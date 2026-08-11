import { BrowserTab } from '../models/BrowserModels';
import { displayHost, isHomeUrl } from '../utils/UrlUtils';
import { AppIcon, IconName } from './AppIcon';

export const DESKTOP_TAB_STRIP_HEIGHT: number = 44;

const TAB_STRIP_MAX_WIDTH: number = 1080;
const TAB_STRIP_MIN_TAB_WIDTH: number = 112;
const TAB_STRIP_MEDIUM_TAB_WIDTH: number = 140;
const TAB_STRIP_MAX_TAB_WIDTH: number = 180;
const TAB_STRIP_PINNED_WIDTH: number = 52;
const TAB_REORDER_DISTANCE: number = 36;

@Component
export struct DesktopTabStrip {
  @Prop tabs: BrowserTab[] = [];
  @Prop @Watch('activeTabChanged') activeTabId: string = '';
  onSelect: (id: string) => void = (_id: string): void => {};
  onClose: (id: string) => void = (_id: string): void => {};
  onReorder: (id: string, direction: number) => void = (_id: string, _direction: number): void => {};
  onCloseOthers: (id: string) => void = (_id: string): void => {};
  onCopyUrl: (id: string) => void = (_id: string): void => {};
  onTogglePinned: (id: string) => void = (_id: string): void => {};
  onNewTab: () => void = (): void => {};
  private scroller: Scroller = new Scroller();
  private contextTabId: string = '';

  build() {
    Row({ space: 8 }) {
      List({ space: 4, scroller: this.scroller }) {
        ForEach(this.tabs, (tab: BrowserTab) => {
          ListItem() {
            this.Tab(tab)
          }
          .width(this.tabWidth(tab))
        }, (tab: BrowserTab): string => `${tab.id}-${tab.isPinned}`)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .layoutWeight(1)
      .height(DESKTOP_TAB_STRIP_HEIGHT)
      .onAppear(() => this.scrollActiveTabIntoView(false))

      Row() {
        AppIcon({ name: IconName.Plus, glyphSize: 17, color: $r('app.color.text_secondary') })
      }
      .id('desktop-new-tab')
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .borderRadius(18)
      .focusable(true)
      .hoverEffect(HoverEffect.Auto)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
      .accessibilityText($r('app.string.new_tab'))
      .onClick(() => this.onNewTab())
    }
    .width('96%')
    .constraintSize({ maxWidth: TAB_STRIP_MAX_WIDTH })
    .height(DESKTOP_TAB_STRIP_HEIGHT)
    .padding({ left: 8, right: 8 })
  }

  @Builder
  private Tab(tab: BrowserTab) {
    Row({ space: 7 }) {
      if (tab.isPrivate) {
        AppIcon({ name: IconName.Incognito, glyphSize: 15, color: $r('app.color.text_secondary') })
      }
      Text(this.tabTitle(tab))
        .fontSize(13)
        .fontWeight(tab.id === this.activeTabId ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(tab.id === this.activeTabId
          ? $r('app.color.text_primary')
          : $r('app.color.text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (!tab.isPinned) {
        Row() {
          AppIcon({ name: IconName.Close, glyphSize: 13, color: $r('app.color.text_secondary') })
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
    .height(36)
    .padding({ left: tab.isPinned ? 10 : 12, right: tab.isPinned ? 10 : 5 })
    .borderRadius(10)
    .backgroundColor(tab.id === this.activeTabId
      ? $r('app.color.surface_panel')
      : $r('app.color.surface_subtle'))
    .border({
      width: 1,
      color: tab.id === this.activeTabId ? $r('app.color.accent') : $r('app.color.border')
    })
    .focusable(true)
    .defaultFocus(tab.id === this.activeTabId)
    .hoverEffect(HoverEffect.Auto)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => this.onSelect(tab.id))
    .onMouse((event: MouseEvent): void => {
      if (event.button === MouseButton.Right && event.action === MouseAction.Press) {
        this.contextTabId = tab.id;
      } else if (event.button === MouseButton.Middle && event.action === MouseAction.Release) {
        this.onClose(tab.id);
      }
    })
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
        .onActionEnd((event: GestureEvent): void => {
          if (Math.abs(event.offsetX) >= TAB_REORDER_DISTANCE) {
            this.onReorder(tab.id, event.offsetX < 0 ? 1 : -1);
          }
        })
    )
    .bindContextMenu(this.TabContextMenu, ResponseType.RightClick)
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
    this.scrollActiveTabIntoView(true);
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
    if (this.tabs.length <= 6) {
      return TAB_STRIP_MAX_TAB_WIDTH;
    }
    if (this.tabs.length <= 12) {
      return TAB_STRIP_MEDIUM_TAB_WIDTH;
    }
    return TAB_STRIP_MIN_TAB_WIDTH;
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
