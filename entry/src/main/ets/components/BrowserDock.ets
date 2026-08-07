import { AppIcon, IconName } from './AppIcon';
import {
  DOCK_BADGE_SIZE,
  DOCK_COLLAPSED_PILL_HEIGHT,
  DOCK_HEIGHT,
  DOCK_ICON_SIZE,
  DOCK_ROW_HEIGHT,
  DOCK_SLOT_WIDTH
} from './TabTokens';

const SWIPE_THRESHOLD: number = 26;

/**
 * One bar, one row. The address reads as a pill flanked by the four controls that
 * earn a permanent slot; everything else lives in the menu or the tab overview.
 * Scrolling down collapses it to a Safari-style mini pill so the page keeps the
 * height it was given.
 */
@Component
export struct BrowserDock {
  @Prop isHome: boolean = false;
  @Prop collapsed: boolean = false;
  @Prop host: string = '';
  @Prop tabCount: number = 1;
  @Prop blockedCount: number = 0;
  @Prop isLoading: boolean = false;
  @Prop canGoBack: boolean = false;
  @Prop canGoForward: boolean = false;
  @Prop gesturesEnabled: boolean = true;
  @Prop actionsGestureEnabled: boolean = true;
  @Prop tabSwitchGestureEnabled: boolean = true;
  @Prop blockingGestureEnabled: boolean = true;
  onOpenAddress: () => void = (): void => {};
  onBack: () => void = (): void => {};
  onForward: () => void = (): void => {};
  onOpenTabs: () => void = (): void => {};
  onOpenRecentTabs: () => void = (): void => {};
  onOpenMenu: () => void = (): void => {};
  onOpenBlocking: () => void = (): void => {};
  /** Reload, or stop while a load is in flight — the page decides which. */
  onReload: () => void = (): void => {};
  onHide: () => void = (): void => {};
  onShow: () => void = (): void => {};
  onSwitchPrevious: () => void = (): void => {};
  onSwitchNext: () => void = (): void => {};

  build() {
    if (this.collapsed) {
      this.CollapsedBar()
    } else {
      this.ExpandedBar()
    }
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
    // The page reserves less than the bar occupies, so the bar carries its own
    // ground rather than floating half-over the article. Home keeps its artwork.
    .backgroundColor(this.isHome ? Color.Transparent : $r('app.color.page_background'))
  }

  @Builder
  private ExpandedRow() {
    Row({ space: 4 }) {
      this.NavButton(IconName.ChevronLeft, this.canGoBack, $r('app.string.action_back'), this.onBack)
      this.NavButton(IconName.ChevronRight, this.canGoForward, $r('app.string.action_forward'), this.onForward)

      // Shield, address, reload — the three things a page-level bar owes the
      // user. On the start page there is nothing to shield or reload, so the
      // placeholder gets the pill to itself.
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
          .padding({ left: 4, right: 4 })
          .accessibilityText($r('app.string.blocked_on_site'))
          .onClick(() => this.onOpenBlocking())
        }

        Text(this.isHome ? $r('app.string.address_placeholder') : this.host)
          .layoutWeight(1)
          .fontSize(15)
          .fontWeight(this.isHome ? FontWeight.Regular : FontWeight.Medium)
          .fontColor(this.primaryColor())
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (!this.isHome) {
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
      }
      .id('browser-address')
      .layoutWeight(1)
      .height(DOCK_ROW_HEIGHT)
      .padding({ left: 8, right: 8 })
      .borderRadius(DOCK_ROW_HEIGHT / 2)
      .backgroundColor(this.chromeColor())
      .backdropBlur(24)
      .border({
        width: 1,
        color: this.isHome ? $r('app.color.home_control_border') : $r('app.color.border')
      })
      .onClick(() => this.onOpenAddress())
      .gesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: 6 })
          .onActionEnd((event: GestureEvent) => this.resolveTabSwipe(event))
      )

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
      .margin({ left: (DOCK_SLOT_WIDTH - DOCK_BADGE_SIZE) / 2, right: (DOCK_SLOT_WIDTH - DOCK_BADGE_SIZE) / 2 })
      .accessibilityText($r('app.string.recent_tabs'))
      .onClick(() => this.onOpenTabs())
      .gesture(
        LongPressGesture({ repeat: false, duration: 450 })
          .onAction(() => this.onOpenRecentTabs())
      )

      this.NavButton(IconName.Menu, true, $r('app.string.tools_menu'), this.onOpenMenu)
    }
    .width('100%')
    .height(DOCK_ROW_HEIGHT)
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
    .height(DOCK_COLLAPSED_PILL_HEIGHT)
    .margin({ bottom: 8 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => this.onShow())
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 6 })
        .onActionEnd((event: GestureEvent) => {
          if (event.offsetY <= -8) {
            this.onShow();
          }
        })
    )
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
    return this.isHome ? $r('app.color.home_chrome_background') : $r('app.color.capsule_background');
  }

  private primaryColor(): ResourceColor {
    return this.isHome ? $r('app.color.home_text_primary') : $r('app.color.text_primary');
  }

  /**
   * Controls sit a step back from the address they surround: at full text weight
   * four black glyphs read as heavier than the page they belong to.
   */
  private iconColor(): ResourceColor {
    return this.isHome ? $r('app.color.home_text_secondary') : $r('app.color.dock_icon');
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
