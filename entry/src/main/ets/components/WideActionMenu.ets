import { AppIcon, IconName } from './AppIcon';

interface WideMenuAction {
  key: string;
  label: Resource;
  icon: IconName;
  enabled: boolean;
  active: boolean;
}

@Component
export struct WideActionMenu {
  @Prop blockedCount: number = 0;
  @Prop isHome: boolean = false;
  @Prop isBookmarked: boolean = false;
  @Prop isReader: boolean = false;
  @Prop isDesktop: boolean = false;
  onDismiss: () => void = (): void => {};
  onAction: (key: string) => void = (_key: string): void => {};

  build() {
    Column({ space: 8 }) {
      this.Header()
      this.ActionGrid(this.pageActions())
      Divider()
        .color($r('app.color.border'))
        .margin({ top: 2, bottom: 2 })
      this.ActionGrid(this.browserActions())
      if (!this.isHome) {
        this.BlockingRow()
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.surface_panel'))
    .borderRadius(20)
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({ radius: 18, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: 6 })
  }

  @Builder
  private Header() {
    Row({ space: 12 }) {
      Text($r('app.string.tools_menu'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
      Row() {
        AppIcon({ name: IconName.Close, glyphSize: 16, color: $r('app.color.text_secondary') })
      }
      .id('wide-action-menu-close')
      .accessibilityText($r('app.string.close'))
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .borderRadius(10)
      .hoverEffect(HoverEffect.Auto)
      .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.94 })
      .onClick(() => this.onDismiss())
    }
    .width('100%')
    .height(40)
    .padding({ left: 4 })
  }

  @Builder
  private ActionGrid(actions: WideMenuAction[]) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(actions, (action: WideMenuAction) => {
        this.ActionRow(action)
      }, (action: WideMenuAction): string => `${action.key}-${action.active}-${action.enabled}`)
    }
    .width('100%')
  }

  @Builder
  private ActionRow(action: WideMenuAction) {
    Row({ space: 10 }) {
      Row() {
        AppIcon({
          name: action.icon,
          glyphSize: 18,
          color: action.active ? $r('app.color.accent_strong') : $r('app.color.text_secondary'),
          filled: action.active && action.icon === IconName.Bookmark,
          strokeWidth: 1.35
        })
      }
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .borderRadius(9)
      .backgroundColor(action.active ? $r('app.color.surface_subtle') : Color.Transparent)
      Text(action.label)
        .fontSize(13.5)
        .fontColor(action.active ? $r('app.color.accent_strong') : $r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('50%')
    .height(48)
    .padding({ left: 8, right: 8 })
    .borderRadius(12)
    .opacity(action.enabled ? 1 : 0.42)
    .focusable(action.enabled)
    .hoverEffect(action.enabled ? HoverEffect.Auto : HoverEffect.None)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .onClick(() => {
      if (action.enabled) {
        this.onAction(action.key);
      }
    })
  }

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
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .layoutWeight(1)
      AppIcon({ name: IconName.ChevronRight, glyphSize: 16, color: $r('app.color.text_secondary') })
    }
    .width('100%')
    .height(44)
    .padding({ left: 12, right: 12 })
    .borderRadius(12)
    .backgroundColor($r('app.color.surface_subtle'))
    .hoverEffect(HoverEffect.Auto)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.98 })
    .onClick(() => this.onAction('blocking'))
  }

  private pageActions(): WideMenuAction[] {
    return [
      this.action(
        'bookmark',
        this.isBookmarked ? $r('app.string.action_bookmark_remove') : $r('app.string.action_bookmark_add'),
        IconName.Bookmark,
        !this.isHome,
        this.isBookmarked
      ),
      this.action('home', $r('app.string.home'), IconName.Home, !this.isHome, this.isHome),
      this.action('private', $r('app.string.new_private_tab'), IconName.Incognito, true, false),
      this.action('desktop', $r('app.string.action_desktop'), IconName.Desktop, !this.isHome, this.isDesktop),
      this.action('find', $r('app.string.find_title'), IconName.Search, !this.isHome, false),
      this.action('reader', $r('app.string.action_reader'), IconName.Reader, !this.isHome, this.isReader)
    ];
  }

  private browserActions(): WideMenuAction[] {
    return [
      this.action('favorites', $r('app.string.favorites'), IconName.Bookmark, true, false),
      this.action('history', $r('app.string.history_title'), IconName.Clock, true, false),
      this.action('downloads', $r('app.string.download_title'), IconName.Download, true, false),
      this.action('recent_tabs', $r('app.string.recent_tabs_title'), IconName.Tabs, true, false),
      this.action('article_library', $r('app.string.article_library'), IconName.Reader, true, false),
      this.action('settings', $r('app.string.settings'), IconName.Settings, true, false),
      this.action('share', $r('app.string.action_share'), IconName.Share, !this.isHome, false)
    ];
  }

  private action(
    key: string,
    label: Resource,
    icon: IconName,
    enabled: boolean,
    active: boolean
  ): WideMenuAction {
    return { key: key, label: label, icon: icon, enabled: enabled, active: active };
  }
}
