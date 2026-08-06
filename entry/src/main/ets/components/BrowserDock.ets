import { AppIcon, IconName } from './AppIcon';

const SWIPE_THRESHOLD: number = 26;

@Component
export struct BrowserDock {
  @Prop isHome: boolean = false;
  @Prop host: string = '';
  @Prop tabCount: number = 1;
  @Prop canGoBack: boolean = false;
  @Prop canGoForward: boolean = false;
  @Prop gesturesEnabled: boolean = true;
  @Prop actionsGestureEnabled: boolean = true;
  @Prop tabSwitchGestureEnabled: boolean = true;
  @Prop blockingGestureEnabled: boolean = true;
  onOpenAddress: () => void = (): void => {};
  onBack: () => void = (): void => {};
  onForward: () => void = (): void => {};
  onNewTab: () => void = (): void => {};
  onOpenTabs: () => void = (): void => {};
  onOpenMenu: () => void = (): void => {};
  onOpenBlocking: () => void = (): void => {};
  onHide: () => void = (): void => {};
  onSwitchPrevious: () => void = (): void => {};
  onSwitchNext: () => void = (): void => {};

  build() {
    Column({ space: 10 }) {
      Row() {
        Text(this.isHome ? $r('app.string.address_placeholder') : this.host)
          .layoutWeight(1)
          .fontSize(16)
          .fontWeight(this.isHome ? FontWeight.Regular : FontWeight.Medium)
          .fontColor(this.primaryColor())
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ left: 36 })

        AppIcon({ name: IconName.Mic, glyphSize: 30, color: this.primaryColor(), strokeWidth: 1.9 })
          .width(36)
          .opacity(0.88)
      }
      .id('browser-address')
      .width('100%')
      .height(54)
      .padding({ left: 18, right: 12 })
      .borderRadius(27)
      .backgroundColor(this.chromeColor())
      .backdropBlur(24)
      .border({
        width: 1,
        color: this.isHome ? $r('app.color.home_control_border') : $r('app.color.border')
      })
      .onClick(() => this.onOpenAddress())

      Row() {
        this.NavButton(IconName.ChevronLeft, this.canGoBack, this.onBack)
        this.NavButton(IconName.ChevronRight, this.canGoForward, this.onForward)
        this.NavButton(IconName.Plus, true, this.onNewTab)

        Stack() {
          AppIcon({ name: IconName.Tabs, glyphSize: 34, color: this.primaryColor(), strokeWidth: 1.9 })
          Text(`${this.tabCount}`)
            .fontSize(this.tabCount > 9 ? 8 : 10)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryColor())
        }
        .layoutWeight(1)
        .height(44)
        .onClick(() => this.onOpenTabs())

        this.NavButton(IconName.Menu, true, this.onOpenMenu)
      }
      .width('100%')
      .height(44)
    }
    .width('100%')
    .padding({ left: 18, right: 18, bottom: 12 })
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false, duration: 450 })
          .onAction(() => {
            if (this.gesturesEnabled && this.blockingGestureEnabled && !this.isHome) {
              this.onOpenBlocking();
            }
          }),
        PanGesture({ direction: PanDirection.All, distance: 6 })
          .onActionEnd((event: GestureEvent) => this.resolveSwipe(event))
      )
    )
  }

  @Builder
  private NavButton(icon: IconName, enabled: boolean, onTap: () => void) {
    Column() {
      AppIcon({ name: icon, glyphSize: 34, color: this.primaryColor(), strokeWidth: 1.9 })
    }
    .layoutWeight(1)
    .height(44)
    .justifyContent(FlexAlign.Center)
    .opacity(enabled ? 1 : 0.34)
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

  private resolveSwipe(event: GestureEvent): void {
    if (!this.gesturesEnabled) {
      return;
    }
    const dx: number = event.offsetX;
    const dy: number = event.offsetY;
    if (Math.abs(dy) >= Math.abs(dx)) {
      if (dy <= -SWIPE_THRESHOLD && this.actionsGestureEnabled) {
        this.onOpenMenu();
      } else if (dy >= SWIPE_THRESHOLD) {
        this.onHide();
      }
      return;
    }
    if (!this.tabSwitchGestureEnabled) {
      return;
    }
    if (dx <= -SWIPE_THRESHOLD) {
      this.onSwitchNext();
    } else if (dx >= SWIPE_THRESHOLD) {
      this.onSwitchPrevious();
    }
  }
}
