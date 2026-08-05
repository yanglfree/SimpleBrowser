import { image } from '@kit.ImageKit';
import { BrowserTab } from '../models/BrowserModels';
import { displayHost, isHomeUrl } from '../utils/UrlUtils';
import { AppIcon, IconName } from './AppIcon';

const CARD_THUMB_HEIGHT: number = 170;
const CLOSE_SWIPE: number = 44;

/** A snapshot of a tab taken the last time it was on screen. */
export interface TabThumbnail {
  id: string;
  shot: image.PixelMap;
}

/**
 * 1e — two columns of cards, the active tab outlined in ink green. Reached by
 * continuing to swipe up from the action sheet.
 */
@Component
export struct TabOverview {
  @Prop tabs: BrowserTab[] = [];
  @Prop activeTabId: string = '';
  /** Snapshots captured when a tab was last on screen; absent for a cold tab. */
  thumbnails: TabThumbnail[] = [];
  onSelect: (id: string) => void = (_id: string): void => {};
  onClose: (id: string) => void = (_id: string): void => {};
  onCloseAll: () => void = (): void => {};
  onNewTab: () => void = (): void => {};
  onNewPrivateTab: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        Row() {
          Text() {
            Span(`${this.tabs.length}`)
            Span(' ')
            Span($r('app.string.tabs_count_suffix'))
          }
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .fontFeature('"tnum" 1')
          .layoutWeight(1)

          Text($r('app.string.close_all_tabs'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .onClick(() => this.onCloseAll())
        }
        .width('100%')
        .padding({ top: 22, left: 24, right: 24, bottom: 18 })

        Grid() {
          ForEach(this.tabs, (tab: BrowserTab) => {
            GridItem() {
              this.TabCard(tab)
            }
          }, (tab: BrowserTab) => tab.id)
        }
        .columnsTemplate('1fr 1fr')
        .columnsGap(16)
        .rowsGap(16)
        .padding({ left: 24, right: 24, bottom: 120 })
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')

      this.NewTabButton()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private TabCard(tab: BrowserTab) {
    Column() {
      Row() {
        Text(this.cardTitle(tab))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(tab.id === this.activeTabId
            ? $r('app.color.text_primary')
            : $r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        AppIcon({ name: IconName.Close, glyphSize: 13, color: $r('app.color.text_secondary') })
          .onClick(() => this.onClose(tab.id))
      }
      .width('100%')
      .padding({ top: 10, left: 12, right: 12, bottom: 8 })

      this.Thumbnail(tab)
    }
    .width('100%')
    .clip(true)
    .borderRadius(20)
    .backgroundColor($r('app.color.surface_panel'))
    .border({
      width: tab.id === this.activeTabId ? 1.5 : 1,
      color: tab.id === this.activeTabId ? $r('app.color.accent') : $r('app.color.border')
    })
    .shadow({ radius: 12, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: 2 })
    .onClick(() => this.onSelect(tab.id))
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: 8 })
        .onActionEnd((event: GestureEvent) => {
          if (event.offsetX <= -CLOSE_SWIPE) {
            this.onClose(tab.id);
          }
        })
    )
  }

  @Builder
  private Thumbnail(tab: BrowserTab) {
    Column() {
      // ForEach over a 0-or-1 element list: renders the snapshot when there is
      // one without handing a possibly-undefined PixelMap to Image().
      ForEach(this.thumbnailsFor(tab.id), (item: TabThumbnail) => {
        Image(item.shot)
          .width('100%')
          .height(CARD_THUMB_HEIGHT)
          .objectFit(ImageFit.Cover)
      }, (item: TabThumbnail) => item.id)

      if (this.thumbnailsFor(tab.id).length === 0) {
        this.ThumbnailPlaceholder(tab)
      }
    }
    .width('100%')
    .height(CARD_THUMB_HEIGHT)
    .clip(true)
    .backgroundColor($r('app.color.page_background'))
    .border({ width: { top: 1 }, color: $r('app.color.border') })
  }

  /** Shown until the tab has been on screen once and could be snapshotted. */
  @Builder
  private ThumbnailPlaceholder(tab: BrowserTab) {
    Column({ space: 8 }) {
      Row()
        .width('40%')
        .height(6)
        .borderRadius(3)
        .backgroundColor($r('app.color.skeleton_weak'))
      Row()
        .width('92%')
        .height(9)
        .borderRadius(4)
        .backgroundColor($r('app.color.skeleton_strong'))
      Row()
        .width('70%')
        .height(9)
        .borderRadius(4)
        .backgroundColor($r('app.color.skeleton_strong'))
      Row()
        .width('100%')
        .height(70)
        .borderRadius(8)
        .backgroundColor($r('app.color.surface_subtle'))
        .margin({ top: 6 })
      Row()
        .width('88%')
        .height(6)
        .borderRadius(3)
        .backgroundColor($r('app.color.skeleton_weak'))
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, left: 12, right: 12 })
    .opacity(tab.isPrivate ? 0.5 : 1)
  }

  @Builder
  private NewTabButton() {
    Row() {
      AppIcon({ name: IconName.Plus, glyphSize: 23, color: $r('app.color.text_primary') })
    }
    .width(56)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .borderRadius(28)
    .backgroundColor($r('app.color.surface_panel'))
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({ radius: 12, color: $r('app.color.shadow_soft'), offsetX: 0, offsetY: 2 })
    .margin({ bottom: 46 })
    .onClick(() => this.onNewTab())
    .gesture(
      LongPressGesture({ repeat: false, duration: 450 })
        .onAction(() => this.onNewPrivateTab())
    )
  }

  private thumbnailsFor(id: string): TabThumbnail[] {
    return this.thumbnails.filter((item: TabThumbnail) => item.id === id);
  }

  private cardTitle(tab: BrowserTab): ResourceStr {
    if (isHomeUrl(tab.url)) {
      return $r('app.string.new_tab');
    }
    const host: string = displayHost(tab.url);
    return host.length > 0 ? host : tab.title;
  }
}
