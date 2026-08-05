import { AppIcon, IconName } from './AppIcon';

const SWIPE_THRESHOLD: number = 26;

interface SheetAction {
  key: string;
  label: Resource;
  icon: IconName;
  enabled: boolean;
  active: boolean;
}

/**
 * 1c — the capsule swiped up. Seven actions on two rows of four; swiping up
 * again continues to the tab overview, swiping down or tapping the scrim puts
 * the capsule back.
 */
@Component
export struct ActionSheet {
  @Prop host: string = '';
  @Prop blockedCount: number = 0;
  @Prop canGoBack: boolean = false;
  @Prop canGoForward: boolean = false;
  @Prop isLoading: boolean = false;
  @Prop isBookmarked: boolean = false;
  @Prop isReader: boolean = false;
  @Prop isDesktop: boolean = false;
  onDismiss: () => void = (): void => {};
  onEscalate: () => void = (): void => {};
  onAction: (key: string) => void = (_key: string): void => {};

  build() {
    Column() {
      Column()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.scrim'))
        .onClick(() => this.onDismiss())

      this.Panel()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private Panel() {
    Column() {
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor($r('app.color.handle'))

      Row() {
        Text(this.host)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Row({ space: 7 }) {
          AppIcon({ name: IconName.ShieldCheck, glyphSize: 14, color: $r('app.color.accent') })
          Text(`${this.blockedCount}`)
            .fontSize(12.5)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .fontFeature('"tnum" 1')
        }
      }
      .width('100%')
      .margin({ top: 14 })

      Divider()
        .strokeWidth(1)
        .color($r('app.color.border'))
        .margin({ top: 18 })

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.actions(), (action: SheetAction) => {
          Column({ space: 7 }) {
            AppIcon({
              name: action.icon,
              glyphSize: 23,
              color: action.active ? $r('app.color.accent') : $r('app.color.text_primary'),
              filled: action.active && action.icon === IconName.Bookmark
            })
            Text(action.label)
              .fontSize(11)
              .fontColor(action.active ? $r('app.color.accent') : $r('app.color.text_secondary'))
              .maxLines(1)
          }
          .width('25%')
          .padding({ top: 12, bottom: 12 })
          .opacity(action.enabled ? 1 : 0.35)
          .onClick(() => {
            if (action.enabled) {
              this.onAction(action.key);
            }
          })
        }, (action: SheetAction) => action.key)
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 10, left: 24, right: 24, bottom: 46 })
    .backgroundColor($r('app.color.surface_panel'))
    .borderRadius({ topLeft: 20, topRight: 20 })
    .shadow({ radius: 12, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: -2 })
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 6 })
        .onActionEnd((event: GestureEvent) => {
          if (event.offsetY <= -SWIPE_THRESHOLD) {
            this.onEscalate();
          } else if (event.offsetY >= SWIPE_THRESHOLD) {
            this.onDismiss();
          }
        })
    )
  }

  private actions(): SheetAction[] {
    return [
      {
        key: 'back',
        label: $r('app.string.action_back'),
        icon: IconName.ChevronLeft,
        enabled: this.canGoBack,
        active: false
      },
      {
        key: 'forward',
        label: $r('app.string.action_forward'),
        icon: IconName.ChevronRight,
        enabled: this.canGoForward,
        active: false
      },
      {
        key: 'reload',
        label: this.isLoading ? $r('app.string.action_stop') : $r('app.string.action_reload'),
        icon: this.isLoading ? IconName.Stop : IconName.Refresh,
        enabled: true,
        active: false
      },
      {
        key: 'share',
        label: $r('app.string.action_share'),
        icon: IconName.Share,
        enabled: true,
        active: false
      },
      {
        key: 'bookmark',
        label: this.isBookmarked
          ? $r('app.string.action_bookmark_remove')
          : $r('app.string.action_bookmark_add'),
        icon: IconName.Bookmark,
        enabled: true,
        active: this.isBookmarked
      },
      {
        key: 'reader',
        label: $r('app.string.action_reader'),
        icon: IconName.Reader,
        enabled: true,
        active: this.isReader
      },
      {
        key: 'desktop',
        label: $r('app.string.action_desktop'),
        icon: IconName.Desktop,
        enabled: true,
        active: this.isDesktop
      }
    ];
  }
}
