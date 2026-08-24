import { AppIcon, IconName } from './AppIcon';

interface SheetAction {
  key: string;
  label: Resource;
  icon: IconName;
  enabled: boolean;
  active: boolean;
  featured: boolean;
}

interface QuickAction {
  key: string;
  label: Resource;
  icon: IconName;
  enabled: boolean;
  active: boolean;
}

const ACTION_SHEET_PAGE_COUNT: number = 2;
const ACTION_SHEET_GRID_HEIGHT: number = 160;
const ACTION_SHEET_MAX_DRAG: number = 180;
export const ACTION_SHEET_DISMISS_THRESHOLD: number = 64;

export function clampedActionSheetDrag(offsetY: number): number {
  return Math.min(ACTION_SHEET_MAX_DRAG, Math.max(0, offsetY));
}

export function shouldDismissActionSheet(offsetY: number): boolean {
  return offsetY >= ACTION_SHEET_DISMISS_THRESHOLD;
}

@Component
export struct ActionSheet {
  @Prop blockedCount: number = 0;
  @Prop isHome: boolean = false;
  @Prop isBookmarked: boolean = false;
  @Prop isReader: boolean = false;
  @Prop isDesktop: boolean = false;
  @State private page: number = 0;
  @State private dragOffset: number = 0;
  onDismiss: () => void = (): void => {};
  onAction: (key: string) => void = (_key: string): void => {};

  build() {
    Column() {
      Column()
        .layoutWeight(1)
        .width('100%')
        .backgroundColor(this.isHome ? $r('app.color.home_menu_scrim') : $r('app.color.scrim'))
        .onClick(() => this.onDismiss())

      this.Panel()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private Panel() {
    Column({ space: 12 }) {
      Row()
        .width(36)
        .height(4)
        .borderRadius(2)
        .backgroundColor(this.handleColor())

      this.QuickActions()

      Row()
        .width('100%')
        .height(1)
        .backgroundColor(this.handleColor())

      Swiper() {
        this.ActionPage(this.primaryActions())
        this.ActionPage(this.secondaryActions())
      }
      .width('100%')
      .height(ACTION_SHEET_GRID_HEIGHT)
      .index(this.page)
      .indicator(false)
      .loop(false)
      .duration(220)
      .onChange((index: number): void => {
        this.page = index;
      })

      Row({ space: 8 }) {
        ForEach(this.pageIndices(), (index: number) => {
          Row()
            .width(index === this.page ? 32 : 14)
            .height(4)
            .borderRadius(2)
            .backgroundColor(index === this.page ? this.primaryColor() : this.handleColor())
            .animation({ duration: 220, curve: Curve.EaseOut })
            .onClick(() => {
              this.page = index;
            })
        }, (index: number) => `action-page-${index}`)
      }

      if (!this.isHome) {
        this.BlockingRow()
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 10, left: 18, right: 18, bottom: 20 })
    .backgroundColor(this.panelColor())
    .borderRadius({ topLeft: 28, topRight: 28 })
    .shadow({ radius: 18, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: -4 })
    .translate({ y: this.dragOffset })
    .parallelGesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 6 })
        .onActionUpdate((event: GestureEvent): void => {
          this.dragOffset = clampedActionSheetDrag(event.offsetY);
        })
        .onActionEnd((event: GestureEvent): void => this.finishDrag(event.offsetY))
        .onActionCancel((): void => this.restorePanel())
    )
  }

  @Builder
  private QuickActions() {
    Scroll() {
      Row({ space: 10 }) {
        ForEach(this.quickActions(), (action: QuickAction) => {
          this.QuickActionCell(action)
        }, (action: QuickAction) => `quick-${action.key}-${action.active}`)
      }
      .padding({ left: 2, right: 2 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .width('100%')
    .height(70)
    .align(Alignment.Top)
  }

  @Builder
  private QuickActionCell(action: QuickAction) {
    Column({ space: 6 }) {
      AppIcon({
        name: action.icon,
        glyphSize: 26,
        color: action.active ? $r('app.color.accent_strong') : this.secondaryColor(),
        filled: action.active && action.icon === IconName.Bookmark,
        strokeWidth: 1.25
      })
      Text(action.label)
        .width('100%')
        .fontSize(10.5)
        .fontColor(action.active ? $r('app.color.accent_strong') : this.primaryColor())
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width(72)
    .height(68)
    .justifyContent(FlexAlign.Center)
    .borderRadius(16)
    .backgroundColor(this.cardColor())
    .opacity(action.enabled ? 1 : 0.5)
    .focusable(action.enabled)
    .hoverEffect(action.enabled ? HoverEffect.Auto : HoverEffect.None)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
    .onClick(() => {
      if (action.enabled) {
        this.onAction(action.key);
      }
    })
  }

  /** Blocking stats, demoted to a single row so the quick actions own the top. */
  @Builder
  private BlockingRow() {
    Row({ space: 10 }) {
      AppIcon({ name: IconName.ShieldCheck, glyphSize: 17, color: $r('app.color.accent') })
      Text() {
        Span($r('app.string.blocked_on_site'))
        Span(' ')
        Span(`${this.blockedCount}`)
        Span(' ')
        Span($r('app.string.blocked_cumulative_suffix'))
      }
      .fontSize(13.5)
      .fontColor(this.secondaryColor())
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .layoutWeight(1)
      AppIcon({ name: IconName.ChevronRight, glyphSize: 17, color: this.secondaryColor() })
    }
    .width('100%')
    .height(48)
    .padding({ left: 14, right: 14 })
    .borderRadius(14)
    .backgroundColor(this.cardColor())
    .accessibilityText($r('app.string.blocked_on_site'))
    .focusable(true)
    .hoverEffect(HoverEffect.Auto)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => this.onAction('blocking'))
  }

  @Builder
  private ActionPage(actions: SheetAction[]) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(actions, (action: SheetAction) => {
        this.ActionCell(action)
      }, (action: SheetAction) => action.key)
    }
    .width('100%')
    .height(ACTION_SHEET_GRID_HEIGHT)
  }

  @Builder
  private ActionCell(action: SheetAction) {
    Column({ space: 6 }) {
      AppIcon({
        name: action.icon,
        glyphSize: 30,
        color: action.featured || action.active ? $r('app.color.accent_strong') : this.secondaryColor(),
        filled: action.active && action.icon === IconName.Bookmark,
        strokeWidth: 1.25
      })
      Text(action.label)
        .width('100%')
        .height(32)
        .fontSize(10.5)
        .fontColor(action.active ? $r('app.color.accent_strong') : this.primaryColor())
        .textAlign(TextAlign.Center)
        .maxLines(2)
    }
    .width('25%')
    .height(80)
    .justifyContent(FlexAlign.Center)
    .opacity(action.enabled ? 1 : 0.5)
    .focusable(action.enabled)
    .hoverEffect(action.enabled ? HoverEffect.Auto : HoverEffect.None)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
    .onClick(() => {
      if (action.enabled) {
        this.onAction(action.key);
      }
    })
  }

  private primaryActions(): SheetAction[] {
    return [
      this.action('home', $r('app.string.home'), IconName.Home, !this.isHome, this.isHome, false),
      this.action('private', $r('app.string.new_private_tab'), IconName.Incognito, true, false, false),
      this.action('favorites', $r('app.string.favorites'), IconName.Bookmark, true, false, true),
      this.action('desktop', $r('app.string.action_desktop'), IconName.Desktop,
        !this.isHome, this.isDesktop, false)
    ];
  }

  private quickActions(): QuickAction[] {
    return [
      {
        key: 'bookmark',
        label: this.isBookmarked ? $r('app.string.action_bookmark_remove') : $r('app.string.action_bookmark_add'),
        icon: IconName.Bookmark,
        enabled: !this.isHome,
        active: this.isBookmarked
      },
      { key: 'history', label: $r('app.string.history_title'), icon: IconName.Clock, enabled: true, active: false },
      { key: 'downloads', label: $r('app.string.download_title'), icon: IconName.Download, enabled: true, active: false },
      { key: 'recent_tabs', label: $r('app.string.recent_tabs_title'), icon: IconName.Tabs, enabled: true, active: false },
      {
        key: 'article_library', label: $r('app.string.article_library'), icon: IconName.Reader,
        enabled: true, active: false
      },
      { key: 'settings', label: $r('app.string.settings'), icon: IconName.Settings, enabled: true, active: false }
    ];
  }

  private secondaryActions(): SheetAction[] {
    return [
      this.action('find', $r('app.string.find_title'), IconName.Search, !this.isHome, false, false),
      this.action('reader', $r('app.string.action_reader'), IconName.Reader, !this.isHome, this.isReader, false),
      this.action('share', $r('app.string.action_share'), IconName.Share, !this.isHome, false, false)
    ];
  }

  private pageIndices(): number[] {
    const indices: number[] = [];
    for (let index: number = 0; index < ACTION_SHEET_PAGE_COUNT; index += 1) {
      indices.push(index);
    }
    return indices;
  }

  private finishDrag(offsetY: number): void {
    if (shouldDismissActionSheet(offsetY)) {
      this.onDismiss();
      return;
    }
    this.restorePanel();
  }

  private restorePanel(): void {
    this.getUIContext().animateTo({ duration: 180, curve: Curve.EaseOut }, (): void => {
      this.dragOffset = 0;
    });
  }

  private action(
    key: string,
    label: Resource,
    icon: IconName,
    enabled: boolean,
    active: boolean,
    featured: boolean
  ): SheetAction {
    return {
      key: key,
      label: label,
      icon: icon,
      enabled: enabled,
      active: active,
      featured: featured
    };
  }

  private panelColor(): ResourceColor {
    return this.isHome ? $r('app.color.home_menu_background') : $r('app.color.surface_panel');
  }

  private cardColor(): ResourceColor {
    return this.isHome ? $r('app.color.home_panel_subtle') : $r('app.color.surface_subtle');
  }

  private primaryColor(): ResourceColor {
    return this.isHome ? $r('app.color.home_text_primary') : $r('app.color.text_primary');
  }

  private secondaryColor(): ResourceColor {
    return this.isHome ? $r('app.color.home_text_secondary') : $r('app.color.text_secondary');
  }

  private handleColor(): ResourceColor {
    return this.isHome ? $r('app.color.home_panel_divider') : $r('app.color.handle');
  }
}
