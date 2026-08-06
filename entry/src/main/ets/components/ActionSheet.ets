import { AppIcon, IconName } from './AppIcon';

interface SheetAction {
  key: string;
  label: Resource;
  icon: IconName;
  enabled: boolean;
  active: boolean;
  featured: boolean;
}

@Component
export struct ActionSheet {
  @Prop host: string = '';
  @Prop blockedCount: number = 0;
  @Prop isHome: boolean = false;
  @Prop isBookmarked: boolean = false;
  @Prop isReader: boolean = false;
  @Prop isDesktop: boolean = false;
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

      Row({ space: 14 }) {
        Image($r('app.media.app_icon'))
          .width(46)
          .height(46)
          .borderRadius(14)

        Column({ space: 4 }) {
          Text(this.isHome ? $r('app.string.browser_profile_title') : this.host)
            .width('100%')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.primaryColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text() {
            if (this.isHome) {
              Span($r('app.string.browser_profile_subtitle'))
            } else {
              Span(`${this.blockedCount}`)
              Span(' ')
              Span($r('app.string.blocked_cumulative_suffix'))
            }
          }
            .width('100%')
            .fontSize(13)
            .fontColor(this.secondaryColor())
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        AppIcon({ name: IconName.ChevronRight, glyphSize: 18, color: this.secondaryColor() })
      }
      .width('100%')
      .height(68)
      .padding({ left: 16, right: 16 })
      .borderRadius(18)
      .backgroundColor(this.cardColor())

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.actions(), (action: SheetAction) => {
          this.ActionCell(action)
        }, (action: SheetAction) => action.key)
      }
      .width('100%')

      Row({ space: 8 }) {
        Row()
          .width(32)
          .height(4)
          .borderRadius(2)
          .backgroundColor(this.primaryColor())
        Row()
          .width(14)
          .height(4)
          .borderRadius(2)
          .backgroundColor(this.handleColor())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: 10, left: 18, right: 18, bottom: 20 })
    .backgroundColor(this.panelColor())
    .borderRadius({ topLeft: 28, topRight: 28 })
    .shadow({ radius: 18, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: -4 })
  }

  @Builder
  private ActionCell(action: SheetAction) {
    Column({ space: 6 }) {
      AppIcon({
        name: action.icon,
        glyphSize: 30,
        color: action.featured || action.active ? $r('app.color.accent_strong') : this.primaryColor(),
        filled: action.active && action.icon === IconName.Bookmark,
        strokeWidth: 1.7
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
    .onClick(() => {
      if (action.enabled) {
        this.onAction(action.key);
      }
    })
  }

  private actions(): SheetAction[] {
    return [
      this.action('favorites', $r('app.string.favorites'), IconName.Bookmark, true, false, true),
      this.action('history', $r('app.string.history_title'), IconName.Clock, true, false, true),
      this.action('downloads', $r('app.string.download_title'), IconName.Download, true, false, true),
      this.action('settings', $r('app.string.settings'), IconName.Settings, true, false, true),
      this.action('home', $r('app.string.home'), IconName.Home, !this.isHome, this.isHome, false),
      this.action('private', $r('app.string.new_private_tab'), IconName.Incognito, true, false, false),
      this.action('bookmark', $r('app.string.edit_favorites'), IconName.Bookmark,
        !this.isHome, this.isBookmarked, false),
      this.action('tabs', $r('app.string.recent_tabs'), IconName.Tabs, true, false, false),
      this.action('desktop', $r('app.string.action_desktop'), IconName.Desktop,
        !this.isHome, this.isDesktop, false),
      this.action('find', $r('app.string.find_title'), IconName.Search, !this.isHome, false, false),
      this.action('reader', $r('app.string.action_reader'), IconName.Reader, !this.isHome, this.isReader, false),
      this.action('share', $r('app.string.action_share'), IconName.Share, !this.isHome, false, false)
    ];
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
