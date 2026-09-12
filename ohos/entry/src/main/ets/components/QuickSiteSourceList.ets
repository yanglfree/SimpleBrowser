import { HistoryEntry, SavedItem } from '../models/BrowserModels';
import { displayHost } from '../utils/UrlUtils';
import { AppIcon, IconName } from './AppIcon';
import {
  QUICK_SITE_EDITOR_SOURCE_ROW_HEIGHT,
  QUICK_SITE_SOURCE_EMPTY_FONT_SIZE,
  QUICK_SITE_SOURCE_EMPTY_ICON_SIZE,
  QUICK_SITE_SOURCE_ICON_SIZE,
  QUICK_SITE_SOURCE_LIST_GAP,
  QUICK_SITE_SOURCE_ROW_GAP,
  QUICK_SITE_SOURCE_ROW_PADDING,
  QUICK_SITE_SOURCE_ROW_RADIUS,
  QUICK_SITE_SOURCE_TITLE_FONT_SIZE,
  QUICK_SITE_SOURCE_TITLE_GAP,
  QUICK_SITE_SOURCE_URL_FONT_SIZE
} from './QuickSiteTokens';

@Component
export struct QuickSiteSourceList {
  @Prop savedItems: SavedItem[] = [];
  @Prop history: HistoryEntry[] = [];
  @Prop favorites: boolean = true;
  onSelect: (title: string, url: string) => void = (_title: string, _url: string): void => {};

  build() {
    if (this.entries().length === 0) {
      Column({ space: QUICK_SITE_SOURCE_ROW_GAP }) {
        AppIcon({
          name: this.favorites ? IconName.Bookmark : IconName.Clock,
          glyphSize: QUICK_SITE_SOURCE_EMPTY_ICON_SIZE,
          color: $r('app.color.text_secondary')
        })
        Text(this.favorites ? $r('app.string.favorites_empty') : $r('app.string.history_empty'))
          .fontSize(QUICK_SITE_SOURCE_EMPTY_FONT_SIZE)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: QUICK_SITE_SOURCE_LIST_GAP }) {
        ForEach(this.entries(), (entry: HistoryEntry) => {
          ListItem() {
            Row({ space: QUICK_SITE_SOURCE_ROW_GAP }) {
              AppIcon({
                name: this.favorites ? IconName.Bookmark : IconName.Clock,
                glyphSize: QUICK_SITE_SOURCE_ICON_SIZE,
                color: $r('app.color.text_secondary')
              })
              Column({ space: QUICK_SITE_SOURCE_TITLE_GAP }) {
                Text(entry.title.length > 0 ? entry.title : displayHost(entry.url))
                  .width('100%')
                  .fontSize(QUICK_SITE_SOURCE_TITLE_FONT_SIZE)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(displayHost(entry.url))
                  .width('100%')
                  .fontSize(QUICK_SITE_SOURCE_URL_FONT_SIZE)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .layoutWeight(1)
              AppIcon({
                name: IconName.Plus,
                glyphSize: QUICK_SITE_SOURCE_ICON_SIZE,
                color: $r('app.color.accent_strong')
              })
            }
            .width('100%')
            .height(QUICK_SITE_EDITOR_SOURCE_ROW_HEIGHT)
            .padding({ left: QUICK_SITE_SOURCE_ROW_PADDING, right: QUICK_SITE_SOURCE_ROW_PADDING })
            .borderRadius(QUICK_SITE_SOURCE_ROW_RADIUS)
            .onClick(() => this.onSelect(entry.title, entry.url))
          }
        }, (entry: HistoryEntry) => `${this.favorites ? 1 : 0}-${entry.id}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  private entries(): HistoryEntry[] {
    if (!this.favorites) {
      return this.history.slice(0, 30);
    }
    return this.savedItems.slice(0, 30).map((item: SavedItem): HistoryEntry => ({
      id: `favorite-${item.id}`,
      title: item.title,
      url: item.url,
      visitedAt: item.updatedAt,
      visitCount: 0
    }));
  }
}
