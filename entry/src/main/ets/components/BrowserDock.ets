import { AppIcon, IconName } from './AppIcon';
import {
  DOCK_BADGE_SIZE,
  DOCK_COLLAPSED_HEIGHT,
  DOCK_COLLAPSED_PILL_HEIGHT,
  DOCK_HEIGHT,
  DOCK_ICON_SIZE,
  DOCK_ROW_HEIGHT,
  DOCK_SLOT_WIDTH,
  DOCK_TAB_INDICATOR_ACTIVE_WIDTH,
  DOCK_TAB_INDICATOR_BOTTOM_INSET,
  DOCK_TAB_INDICATOR_DOT_SIZE,
  DOCK_TAB_INDICATOR_GAP,
  DOCK_TAB_INDICATOR_LIMIT
} from './TabTokens';

const SWIPE_THRESHOLD: number = 26;
const ADDRESS_MENU_WIDTH: number = 228;
const ADDRESS_MENU_ROW_HEIGHT: number = 44;
const ADDRESS_MENU_GAP: number = 8;
const ADDRESS_MENU_HEIGHT: number = ADDRESS_MENU_ROW_HEIGHT * 2 + 1;
const WIDE_DOCK_MAX_WIDTH: number = 1080;

export function canUseDesktopPageActions(host: string, isHome: boolean): boolean {
  return host.length > 0 || !isHome;
}

export function compactDockOpticalOffset(
  bottomInset: number,
  wide: boolean,
  _collapsed: boolean
): number {
  if (wide || bottomInset <= 0) {
    return 0;
  }
  return bottomInset / 2;
}

/**
 * One bar, one row. Compact layouts keep the phone controls around an address pill;
 * desktop layouts expand the same interaction model into a full-width toolbar.
 * Scrolling down collapses it to a Safari-style mini pill so the page keeps the
 * height it was given.
 */
@Component
export struct BrowserDock {
  @Prop isHome: boolean = false;
  @Prop homeBackgroundEnabled: boolean = true;
  @Prop collapsed: boolean = false;
  @Prop wide: boolean = false;
  @Prop desktop: boolean = false;
  @Prop host: string = '';
  @Prop tabCount: number = 1;
  @Prop activeTabIndex: number = 0;
  @Prop blockedCount: number = 0;
  @Prop isLoading: boolean = false;
  @Prop canGoBack: boolean = false;
  @Prop canGoForward: boolean = false;
  @Prop gesturesEnabled: boolean = true;
  @Prop actionsGestureEnabled: boolean = true;
  @Prop tabSwitchGestureEnabled: boolean = true;
  @Prop blockingGestureEnabled: boolean = true;
  @Prop addressMenuVisible: boolean = false;
  @Prop isBookmarked: boolean = false;
  /** Drives the history button's active tint while its panel owns the screen. */
  @Prop historyOpen: boolean = false;
  onOpenAddress: () => void = (): void => {};
  onBack: () => void = (): void => {};
  onForward: () => void = (): void => {};
  onHome: () => void = (): void => {};
  onBookmark: () => void = (): void => {};
  onOpenTabs: () => void = (): void => {};
  onOpenRecentTabs: () => void = (): void => {};
  onOpenMenu: () => void = (): void => {};
  onOpenHistory: () => void = (): void => {};
  onOpenBlocking: () => void = (): void => {};
  /** Reload, or stop while a load is in flight — the page decides which. */
  onReload: () => void = (): void => {};
  onHide: () => void = (): void => {};
  onShow: () => void = (): void => {};
  onSwitchPrevious: () => void = (): void => {};
  onSwitchNext: () => void = (): void => {};
  onOpenAddressMenu: () => void = (): void => {};
  onDismissAddressMenu: () => void = (): void => {};
  onVisitClipboardLink: () => void = (): void => {};
  onClipboardAccessFailed: () => void = (): void => {};
  onCopyLink: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      if (this.collapsed) {
        this.CollapsedBar()
      } else {
        this.ExpandedBar()
        if (this.addressMenuVisible && !this.isHome) {
          this.AddressMenu()
        }
      }
    }
    .width(this.desktop ? '100%' : this.wide ? '96%' : '100%')
    .constraintSize({ maxWidth: this.desktop ? '100%' : this.wide ? WIDE_DOCK_MAX_WIDTH : '100%' })
    .height(this.viewportHeight())
    .clip(true)
  }

  /** The resting bar: back, forward, address, tabs, menu on a single line. */
  @Builder
  private ExpandedBar() {
    Column() {
      this.ExpandedRow()
    }
    .width('100%')
    .height(DOCK_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.usesHomeColors() ? Color.Transparent : $r('app.color.page_background'))
    .borderRadius(this.desktop ? 0 : this.wide ? DOCK_HEIGHT / 2 : 0)
    .shadow(this.desktop ? undefined : this.wide
      ? { radius: 16, color: $r('app.color.shadow_soft'), offsetY: 3 }
      : undefined)
  }

  @Builder
  private ExpandedRow() {
    Row({ space: 4 }) {
      this.NavButton(IconName.ChevronLeft, this.canGoBack, $r('app.string.action_back'), this.onBack)
      this.NavButton(IconName.ChevronRight, this.canGoForward, $r('app.string.action_forward'), this.onForward)
      if (this.desktop) {
        this.NavButton(
          this.isLoading ? IconName.Stop : IconName.Refresh,
          canUseDesktopPageActions(this.host, this.isHome),
          this.isLoading ? $r('app.string.action_stop') : $r('app.string.action_reload'),
          this.onReload
        )
        this.NavButton(
          IconName.Home,
          canUseDesktopPageActions(this.host, this.isHome),
          $r('app.string.home'),
          this.onHome
        )
      }

      // Shield, address, reload — the three things a page-level bar owes the
      // user. On the start page there is nothing to shield or reload, so the
      // placeholder gets the pill to itself.
      Stack({ alignContent: Alignment.Bottom }) {
        Row() {
          if (!this.isHome && this.blockedCount > 0) {
            Row({ space: 3 }) {
              AppIcon({
                name: IconName.ShieldCheck,
                glyphSize: 16,
                color: $r('app.color.accent'),
                strokeWidth: 1.8
              })
              Text(`${this.blockedCount}`)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.accent'))
                .fontFeature('"tnum" 1')
            }
            .height(DOCK_ROW_HEIGHT)
            .alignItems(VerticalAlign.Center)
            .padding({ left: 4, right: 4 })
            .accessibilityText($r('app.string.blocked_on_site'))
            .onClick(() => this.onOpenBlocking())
          }

          Text(this.isHome ? $r('app.string.address_placeholder') : this.host)
            .layoutWeight(1)
            .fontSize(15)
            .fontWeight(this.isHome ? FontWeight.Regular : FontWeight.Medium)
            .fontColor(this.primaryColor())
            .textAlign(this.desktop ? TextAlign.Start : TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (!this.isHome && !this.desktop) {
            Column() {
              AppIcon({
                name: this.isLoading ? IconName.Stop : IconName.Refresh,
                glyphSize: 19,
                color: this.iconColor(),
                strokeWidth: 1.8
              })
            }
            .width(28)
            .height(DOCK_ROW_HEIGHT)
            .justifyContent(FlexAlign.Center)
            .accessibilityText(this.isLoading ? $r('app.string.action_stop') : $r('app.string.action_reload'))
            .onClick(() => this.onReload())
          }

          if (!this.isHome && this.desktop) {
            Row() {
              AppIcon({
                name: IconName.Star,
                glyphSize: 19,
                color: this.isBookmarked ? $r('app.color.accent') : this.iconColor(),
                strokeWidth: 1.8,
                filled: this.isBookmarked
              })
            }
            .width(28)
            .height(DOCK_ROW_HEIGHT)
            .justifyContent(FlexAlign.Center)
            .accessibilityText(this.isBookmarked
              ? $r('app.string.action_bookmark_remove')
              : $r('app.string.action_bookmark_add'))
            .onClick(() => this.onBookmark())
          }
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Center)

        if (this.canSwitchTabs()) {
          this.TabSwipeIndicator()
        }
      }
      .id('browser-address')
      .layoutWeight(1)
      .height(DOCK_ROW_HEIGHT)
      .padding({ left: 8, right: 8 })
      .borderRadius(this.desktop ? 12 : DOCK_ROW_HEIGHT / 2)
      .backgroundColor(this.chromeColor())
      .backdropBlur(24)
      .border({
        width: 1,
        color: this.usesHomeColors() ? $r('app.color.home_control_border') : $r('app.color.border')
      })
      .focusable(true)
      .defaultFocus(this.wide)
      .focusOnTouch(true)
      .hoverEffect(HoverEffect.Auto)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.995 })
      .onAppear(() => {
        if (this.wide) {
          focusControl.requestFocus('browser-address');
        }
      })
      .onClick(() => {
        if (this.addressMenuVisible) {
          this.onDismissAddressMenu();
        } else {
          this.onOpenAddress();
        }
      })
      .gesture(
        GestureGroup(GestureMode.Exclusive,
          LongPressGesture({ repeat: false, duration: 450 })
            .onAction(() => {
              if (!this.isHome) {
                this.onOpenAddressMenu();
              }
            }),
          PanGesture({ direction: PanDirection.Horizontal, distance: 6 })
            .onActionEnd((event: GestureEvent) => this.resolveTabSwipe(event))
        )
      )

      if (this.desktop) {
        this.NavButton(IconName.Tabs, true, $r('app.string.recent_tabs'), this.onOpenTabs)
      } else {
        // The count sits inside its own outline instead of on top of the stacked-
        // card glyph, where the digits and the strokes were fighting for the same
        // pixels. This is the counter every mobile browser draws.
        Stack() {
          Text(this.tabCount > 99 ? ':)' : `${this.tabCount}`)
            .fontSize(this.tabCount > 9 ? 11 : 12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.iconColor())
            .fontFeature('"tnum" 1')
        }
        .width(DOCK_BADGE_SIZE)
        .height(DOCK_BADGE_SIZE)
        .borderRadius(7)
        .border({ width: 1.8, color: this.iconColor() })
        .margin({
          left: (DOCK_SLOT_WIDTH - DOCK_BADGE_SIZE) / 2,
          right: (DOCK_SLOT_WIDTH - DOCK_BADGE_SIZE) / 2
        })
        .accessibilityText($r('app.string.recent_tabs'))
        .focusable(true)
        .hoverEffect(HoverEffect.Auto)
        .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
        .onClick(() => this.onOpenTabs())
        .gesture(
          LongPressGesture({ repeat: false, duration: 450 })
            .onAction(() => this.onOpenRecentTabs())
        )
      }

      // Wide windows have the room to promote history out of the tools menu, and
      // the sidebar it opens is a two-tap round trip without it. Compact keeps it
      // in the menu, where the row has no width to spare.
      if (this.wide) {
        this.HistoryButton()
      }

      this.NavButton(IconName.Menu, true, $r('app.string.tools_menu'), this.onOpenMenu)
    }
    .width('100%')
    .height(DOCK_ROW_HEIGHT)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 10, right: 10 })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false, duration: 450 })
          .onAction(() => {
            if (this.gesturesEnabled && this.blockingGestureEnabled && !this.isHome) {
              this.onOpenBlocking();
            }
          }),
        PanGesture({ direction: PanDirection.Vertical, distance: 6 })
          .onActionEnd((event: GestureEvent) => this.resolveVerticalSwipe(event))
      )
    )
  }

  @Builder
  private AddressMenu() {
    Column() {
      this.VisitClipboardMenuItem()
      Divider()
        .width('100%')
        .strokeWidth(1)
        .color($r('app.color.border'))
      this.AddressMenuItem(
        IconName.ArrowUpLeft,
        $r('app.string.address_menu_copy_link'),
        this.onCopyLink
      )
    }
    .width(ADDRESS_MENU_WIDTH)
    .height(ADDRESS_MENU_HEIGHT)
    .margin({ bottom: DOCK_HEIGHT + ADDRESS_MENU_GAP })
    .borderRadius(16)
    .backgroundColor($r('app.color.capsule_background'))
    .backdropBlur(28)
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({ radius: 18, color: $r('app.color.shadow_soft'), offsetY: 4 })
    .transition(TransitionEffect.OPACITY.animation({ duration: 150 })
      .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 })))
  }

  @Builder
  private VisitClipboardMenuItem() {
    Row({ space: 10 }) {
      AppIcon({
        name: IconName.ChevronRight,
        glyphSize: 18,
        color: $r('app.color.text_secondary'),
        strokeWidth: 1.8
      })
      Text($r('app.string.address_menu_visit_clipboard'))
        .layoutWeight(1)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
      PasteButton({
        icon: PasteIconStyle.LINES,
        text: PasteDescription.PASTE,
        buttonType: ButtonType.Capsule
      })
        .width(64)
        .height(32)
        .fontSize(12)
        .fontColor($r('app.color.accent'))
        .iconSize(14)
        .iconColor($r('app.color.accent'))
        .backgroundColor($r('app.color.surface_subtle'))
        .borderWidth(0)
        .padding({ left: 8, right: 8 })
        .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
          if (result === PasteButtonOnClickResult.SUCCESS) {
            this.onDismissAddressMenu();
            this.onVisitClipboardLink();
          } else {
            this.onClipboardAccessFailed();
          }
        })
    }
    .width('100%')
    .height(ADDRESS_MENU_ROW_HEIGHT)
    .padding({ left: 16, right: 10 })
    .accessibilityText($r('app.string.address_menu_visit_clipboard'))
    .focusable(true)
    .hoverEffect(HoverEffect.Auto)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
  }

  @Builder
  private AddressMenuItem(icon: IconName, label: Resource, action: () => void) {
    Row({ space: 12 }) {
      AppIcon({ name: icon, glyphSize: 18, color: $r('app.color.text_secondary'), strokeWidth: 1.8 })
      Text(label)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
    }
    .width('100%')
    .height(ADDRESS_MENU_ROW_HEIGHT)
    .padding({ left: 16, right: 16 })
    .accessibilityText(label)
    .focusable(true)
    .hoverEffect(HoverEffect.Auto)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
    .onClick(() => {
      this.onDismissAddressMenu();
      action();
    })
  }

  @Builder
  private TabSwipeIndicator() {
    Row({ space: DOCK_TAB_INDICATOR_GAP }) {
      ForEach(this.visibleTabIndices(), (index: number) => {
        Row()
          .id(`tab-swipe-indicator-${index}`)
          .width(index === this.activeTabIndex
            ? DOCK_TAB_INDICATOR_ACTIVE_WIDTH
            : DOCK_TAB_INDICATOR_DOT_SIZE)
          .height(DOCK_TAB_INDICATOR_DOT_SIZE)
          .borderRadius(DOCK_TAB_INDICATOR_DOT_SIZE / 2)
          .backgroundColor(index === this.activeTabIndex
            ? this.tabIndicatorActiveColor()
            : this.tabIndicatorInactiveColor())
      }, (index: number) => `tab-swipe-indicator-${index}`)
    }
    .id('tab-swipe-indicator')
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ bottom: DOCK_TAB_INDICATOR_BOTTOM_INSET })
    .hitTestBehavior(HitTestMode.None)
  }

  /**
   * Scrolled-away state: a host-only pill rather than an invisible strip, so the
   * bar reads as parked instead of gone. Tap or swipe up brings it back.
   */
  @Builder
  private CollapsedBar() {
    Row() {
      Row() {
        Text(this.host)
          .fontSize(12.5)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .constraintSize({ maxWidth: '62%' })
      .height(DOCK_COLLAPSED_PILL_HEIGHT)
      .padding({ left: 16, right: 16 })
      .borderRadius(DOCK_COLLAPSED_PILL_HEIGHT / 2)
      .backgroundColor($r('app.color.capsule_background'))
      .backdropBlur(24)
      .border({ width: 1, color: $r('app.color.border') })
      .opacity(0.94)
    }
    .width('100%')
    .height(DOCK_COLLAPSED_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.onShow())
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false, duration: 450 })
          .onAction(() => {
            this.onShow();
            this.onOpenAddressMenu();
          }),
        PanGesture({ direction: PanDirection.Vertical, distance: 6 })
          .onActionEnd((event: GestureEvent) => {
            if (event.offsetY <= -8) {
              this.onShow();
            }
          })
      )
    )
  }

  /**
   * Its own builder rather than a NavButton call: the active tint is read from
   * state, and a @Builder value parameter binds once and would never refresh it.
   */
  @Builder
  private HistoryButton() {
    Column() {
      AppIcon({
        name: IconName.Clock,
        glyphSize: DOCK_ICON_SIZE,
        color: this.historyOpen ? $r('app.color.accent') : this.iconColor(),
        strokeWidth: 1.8
      })
    }
    .id('browser-dock-history')
    .width(DOCK_SLOT_WIDTH)
    .height(DOCK_ROW_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .borderRadius(DOCK_ROW_HEIGHT / 2)
    .backgroundColor(this.historyOpen ? $r('app.color.surface_subtle') : Color.Transparent)
    .accessibilityText($r('app.string.history_title'))
    .focusable(true)
    .hoverEffect(HoverEffect.Auto)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.92 })
    .onClick(() => this.onOpenHistory())
  }

  @Builder
  private NavButton(icon: IconName, enabled: boolean, label: Resource, onTap: () => void) {
    Column() {
      AppIcon({ name: icon, glyphSize: DOCK_ICON_SIZE, color: this.iconColor(), strokeWidth: 1.8 })
    }
    .width(DOCK_SLOT_WIDTH)
    .height(DOCK_ROW_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .opacity(enabled ? 1 : 0.34)
    .accessibilityText(label)
    .onClick(() => {
      if (enabled) {
        onTap();
      }
    })
  }

  private chromeColor(): ResourceColor {
    return this.usesHomeColors() ? $r('app.color.home_chrome_background') : $r('app.color.capsule_background');
  }

  private primaryColor(): ResourceColor {
    return this.usesHomeColors() ? $r('app.color.home_text_primary') : $r('app.color.text_primary');
  }

  /**
   * Controls sit a step back from the address they surround: at full text weight
   * four black glyphs read as heavier than the page they belong to.
   */
  private iconColor(): ResourceColor {
    return this.usesHomeColors() ? $r('app.color.home_text_secondary') : $r('app.color.dock_icon');
  }

  private canSwitchTabs(): boolean {
    return this.gesturesEnabled && this.tabSwitchGestureEnabled && this.tabCount > 1;
  }

  private viewportHeight(): number {
    if (this.collapsed) {
      return DOCK_COLLAPSED_HEIGHT;
    }
    return this.addressMenuVisible && !this.isHome
      ? DOCK_HEIGHT + ADDRESS_MENU_GAP + ADDRESS_MENU_HEIGHT
      : DOCK_HEIGHT;
  }

  private visibleTabIndices(): number[] {
    const visibleCount: number = Math.min(this.tabCount, DOCK_TAB_INDICATOR_LIMIT);
    const halfWindow: number = Math.floor(visibleCount / 2);
    const maxStart: number = Math.max(0, this.tabCount - visibleCount);
    const start: number = Math.min(Math.max(0, this.activeTabIndex - halfWindow), maxStart);
    const indices: number[] = [];
    for (let index: number = start; index < start + visibleCount; index++) {
      indices.push(index);
    }
    return indices;
  }

  private tabIndicatorActiveColor(): ResourceColor {
    return this.usesHomeColors() ? $r('app.color.home_text_primary') : $r('app.color.accent');
  }

  private tabIndicatorInactiveColor(): ResourceColor {
    return this.usesHomeColors() ? $r('app.color.home_text_secondary') : $r('app.color.border');
  }

  private usesHomeColors(): boolean {
    return this.isHome && this.homeBackgroundEnabled && !this.wide;
  }

  private resolveVerticalSwipe(event: GestureEvent): void {
    if (!this.gesturesEnabled) {
      return;
    }
    const dy: number = event.offsetY;
    if (dy <= -SWIPE_THRESHOLD && this.actionsGestureEnabled) {
      this.onOpenMenu();
    } else if (dy >= SWIPE_THRESHOLD) {
      this.onHide();
    }
  }

  private resolveTabSwipe(event: GestureEvent): void {
    if (!this.gesturesEnabled || !this.tabSwitchGestureEnabled) {
      return;
    }
    const dx: number = event.offsetX;
    if (dx <= -SWIPE_THRESHOLD) {
      this.onSwitchNext();
    } else if (dx >= SWIPE_THRESHOLD) {
      this.onSwitchPrevious();
    }
  }
}
