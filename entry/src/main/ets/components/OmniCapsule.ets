import { AppIcon, IconName } from './AppIcon';

const SWIPE_THRESHOLD: number = 22;

/**
 * 1b — the only chrome in the browsing view. Every hidden surface hangs off this
 * one control: tap for the address bar, swipe up for actions, swipe sideways for
 * the neighbouring tab, swipe down to get rid of it, long-press for the blocking
 * panel.
 */
@Component
export struct OmniCapsule {
  @Prop host: string = '';
  @Prop blockedCount: number = 0;
  @Prop isPrivate: boolean = false;
  onTap: () => void = (): void => {};
  onLongPress: () => void = (): void => {};
  onSwipeUp: () => void = (): void => {};
  onSwipeDown: () => void = (): void => {};
  onSwipeLeft: () => void = (): void => {};
  onSwipeRight: () => void = (): void => {};

  build() {
    Row({ space: 10 }) {
      AppIcon({
        name: this.isPrivate ? IconName.Shield : IconName.ShieldCheck,
        glyphSize: 18,
        color: $r('app.color.accent_strong'),
        strokeWidth: 1.8
      })
      Text(`${this.blockedCount}`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .fontFeature('"tnum" 1')

      Divider()
        .vertical(true)
        .height(16)
        .strokeWidth(1)
        .color($r('app.color.border'))

      if (this.isPrivate) {
        Text($r('app.string.private_badge'))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
      }

      Text(this.host)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 200 })
    }
    .height(46)
    .padding({ left: 20, right: 20 })
    .borderRadius(23)
    .backgroundColor($r('app.color.capsule_background'))
    .backdropBlur(20)
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({ radius: 12, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: 2 })
    .onClick(() => this.onTap())
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false, duration: 450 })
          .onAction(() => this.onLongPress()),
        PanGesture({ direction: PanDirection.All, distance: 6 })
          .onActionEnd((event: GestureEvent) => this.resolveSwipe(event))
      )
    )
  }

  private resolveSwipe(event: GestureEvent): void {
    const dx: number = event.offsetX;
    const dy: number = event.offsetY;
    if (Math.abs(dy) >= Math.abs(dx)) {
      if (dy <= -SWIPE_THRESHOLD) {
        this.onSwipeUp();
      } else if (dy >= SWIPE_THRESHOLD) {
        this.onSwipeDown();
      }
      return;
    }
    if (dx <= -SWIPE_THRESHOLD) {
      this.onSwipeLeft();
    } else if (dx >= SWIPE_THRESHOLD) {
      this.onSwipeRight();
    }
  }
}
