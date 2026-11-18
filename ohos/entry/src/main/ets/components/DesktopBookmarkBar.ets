import { SavedItem, SiteIcon, siteIconPath } from '../models/BrowserModels';
import { displayHost, rawHost } from '../utils/UrlUtils';
import { AppIcon, IconName } from './AppIcon';

export const DESKTOP_BOOKMARK_BAR_HEIGHT: number = 34;

export function shouldShowDesktopBookmarkBar(
  usesDesktopStrip: boolean,
  isFullscreen: boolean,
  bookmarkCount: number
): boolean {
  return usesDesktopStrip && !isFullscreen && bookmarkCount > 0;
}

@Component
export struct DesktopBookmarkBar {
  @Prop items: SavedItem[] = [];
  @Prop siteIcons: SiteIcon[] = [];
  onSelect: (url: string) => void = (_url: string): void => {};
  onOpenBackground: (url: string) => void = (_url: string): void => {};
  onDelete: (id: string) => void = (_id: string): void => {};
  @State private brokenHosts: string[] = [];
  private contextItem: SavedItem | undefined = undefined;

  build() {
    Row() {
      List({ space: 4 }) {
        ForEach(this.items, (item: SavedItem) => {
          ListItem() {
            this.BookmarkChip(item)
          }
        }, (item: SavedItem): string => `${item.id}-${item.title}-${item.url}-${this.iconPath(item.url)}`)
      }
      .listDirection(Axis.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(DESKTOP_BOOKMARK_BAR_HEIGHT)
      .alignListItem(ListItemAlign.Center)
    }
    .id('desktop-bookmark-bar')
    .width('100%')
    .height(DESKTOP_BOOKMARK_BAR_HEIGHT)
    .padding({ left: 10, right: 10 })
    .backgroundColor($r('app.color.page_background'))
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
  }

  @Builder
  private BookmarkChip(item: SavedItem) {
    Row({ space: 6 }) {
      if (this.iconPath(item.url).length > 0) {
        Image(this.iconPath(item.url))
          .width(14)
          .height(14)
          .objectFit(ImageFit.Contain)
          .interpolation(ImageInterpolation.High)
          .borderRadius(3)
          .draggable(false)
          .onError(() => this.markBroken(item.url))
      } else {
        AppIcon({ name: IconName.Bookmark, glyphSize: 13, color: $r('app.color.text_secondary') })
      }
      Text(this.itemLabel(item))
        .fontSize(12.5)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 160 })
    }
    .id(`desktop-bookmark-${item.id}`)
    .height(26)
    .padding({ left: 8, right: 10 })
    .borderRadius(8)
    .hoverEffect(HoverEffect.Auto)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .onClick(() => this.onSelect(item.url))
    .onMouse((event: MouseEvent): void => {
      if (event.button === MouseButton.Right && event.action === MouseAction.Press) {
        this.contextItem = item;
      } else if (event.button === MouseButton.Middle && event.action === MouseAction.Release) {
        this.onOpenBackground(item.url);
      }
    })
    .bindContextMenu(this.BookmarkContextMenu, ResponseType.RightClick)
  }

  @Builder
  private BookmarkContextMenu() {
    Menu() {
      MenuItem({ content: $r('app.string.link_menu_open_background') })
        .onClick(() => {
          if (this.contextItem !== undefined) {
            this.onOpenBackground(this.contextItem.url);
          }
        })
      MenuItem({ content: $r('app.string.favorite_delete') })
        .onClick(() => {
          if (this.contextItem !== undefined) {
            this.onDelete(this.contextItem.id);
          }
        })
    }
  }

  private iconPath(url: string): string {
    const host: string = rawHost(url);
    if (host.length === 0 || this.brokenHosts.includes(host)) {
      return '';
    }
    return siteIconPath(this.siteIcons, host);
  }

  private markBroken(url: string): void {
    const host: string = rawHost(url);
    if (host.length > 0 && !this.brokenHosts.includes(host)) {
      this.brokenHosts = this.brokenHosts.concat([host]);
    }
  }

  private itemLabel(item: SavedItem): string {
    const title: string = item.title.trim();
    return title.length > 0 ? title : displayHost(item.url);
  }
}
