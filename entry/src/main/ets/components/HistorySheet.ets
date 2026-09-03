import { HistoryEntry, SavedItem } from '../models/BrowserModels';
import { dayKey } from '../utils/Formatting';
import { displayHost } from '../utils/UrlUtils';
import { AppIcon, IconName } from './AppIcon';

const HISTORY_SWIPE_DISTANCE: number = 26;
const HISTORY_HEADER_MIN_TOP_PADDING: number = 18;
const HISTORY_HEADER_SAFE_AREA_GAP: number = 12;

export function historyHeaderTopPadding(topInset: number): number {
  return Math.max(HISTORY_HEADER_MIN_TOP_PADDING, Math.max(0, topInset) + HISTORY_HEADER_SAFE_AREA_GAP);
}

export function resolveHistoryEntryDeleteTarget(
  entry: HistoryEntry,
  favoritesOnly: boolean,
  savedItems: SavedItem[]
): string {
  if (favoritesOnly || entry.id.startsWith('saved-search-')) {
    const saved: SavedItem | undefined = savedItems.find((item: SavedItem) => item.url === entry.url);
    return saved !== undefined ? saved.id : entry.id;
  }
  return entry.id;
}

interface HistoryGroup {
  key: string;
  title: Resource;
  entries: HistoryEntry[];
}

/** Full browsing history with calendar grouping and destructive swipe actions. */
@Component
export struct HistorySheet {
  @Prop @Watch('onDatasetChange') entries: HistoryEntry[] = [];
  @Prop @Watch('onDatasetChange') savedItems: SavedItem[] = [];
  @Prop favoritesOnly: boolean = false;
  @Prop topInset: number = 0;
  /**
   * Where the list was left the last time it was shown. The sidebar unmounts the
   * sheet when it closes, so opening a history item and coming back would
   * otherwise drop the reader at the top of an unfiltered list.
   */
  @Prop initialQuery: string = '';
  @Prop initialScrollOffset: number = 0;
  @State private query: string = '';
  @State private searchResults: HistoryEntry[] = [];
  @State private displayedEntries: HistoryEntry[] = [];
  private scroller: Scroller = new Scroller();
  private scrollOffset: number = 0;
  private hasRestoredOffset: boolean = false;

  aboutToAppear(): void {
    this.query = this.initialQuery;
    this.scrollOffset = this.initialScrollOffset;
    this.displayedEntries = this.entries.slice();
    this.searchResults = this.computeSearchResults(this.query);
  }

  private onDatasetChange(): void {
    this.displayedEntries = this.entries.slice();
    if (this.query.trim().length > 0) {
      this.searchResults = this.computeSearchResults(this.query);
    }
  }
  onDismiss: () => void = (): void => {};
  /** Reported on every change so the owner can hand it back on the next open. */
  onStateChange: (query: string, scrollOffset: number) => void =
    (_query: string, _scrollOffset: number): void => {};
  onSelect: (url: string) => void = (_url: string): void => {};
  onDelete: (id: string) => void = (_id: string): void => {};
  onDeleteSite: (host: string) => void = (_host: string): void => {};
  onEditItem: (item: SavedItem) => void = (_item: SavedItem): void => {};

  build() {
    Column() {
      Row({ space: 12 }) {
        AppIcon({ name: IconName.ArrowLeft, glyphSize: 21, color: $r('app.color.text_primary') })
          .onClick(() => this.onDismiss())
        Text(this.favoritesOnly ? $r('app.string.favorites') : $r('app.string.history_title'))
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.favoritesOnly ? this.savedItems.length : this.entries.length}`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .fontFeature('"tnum" 1')
      }
      .width('100%')
      .padding({ top: historyHeaderTopPadding(this.topInset), left: 24, right: 24, bottom: 12 })

      TextInput({ text: this.query, placeholder: $r('app.string.global_search_placeholder') })
        .width('100%')
        .height(46)
        .margin({ left: 24, right: 24, bottom: 8 })
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.surface_subtle'))
        .borderRadius(12)
        .onChange((value: string): void => {
          this.query = value;
          this.searchResults = this.computeSearchResults(value);
          // A new filter means the remembered offset belongs to a list that no
          // longer exists; restoring it would land on an unrelated row.
          this.scrollOffset = 0;
          this.onStateChange(this.query, this.scrollOffset);
        })

      if (this.visibleEntries().length === 0) {
        Column() {
          AppIcon({
            name: this.favoritesOnly ? IconName.Bookmark : IconName.Clock,
            glyphSize: 28,
            color: $r('app.color.text_secondary')
          })
          Text(this.favoritesOnly ? $r('app.string.favorites_empty') : $r('app.string.history_empty'))
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll(this.scroller) {
          Column() {
            ForEach(this.groups(), (group: HistoryGroup) => {
              this.Group(group)
            }, (group: HistoryGroup) => this.groupRenderKey(group))
          }
          .width('100%')
          .padding({ left: 24, right: 24, bottom: 32 })
          // The rows are not laid out yet at onAppear, so the restore waits for
          // the content to report its size.
          .onAreaChange((_old: Area, _current: Area): void => this.restoreScrollOffset())
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onDidScroll((): void => {
          this.scrollOffset = Math.max(0, this.scroller.currentOffset().yOffset);
          this.onStateChange(this.query, this.scrollOffset);
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  private Group(group: HistoryGroup) {
    Column() {
      Text(group.title)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .padding({ top: 14, bottom: 7 })
      ForEach(group.entries, (entry: HistoryEntry) => {
        this.EntryRow(entry)
      }, (entry: HistoryEntry) => entry.id)
    }
    .width('100%')
  }

  @Builder
  private EntryRow(entry: HistoryEntry) {
    Row({ space: 12 }) {
      AppIcon({
        name: this.favoritesOnly ? IconName.Bookmark : IconName.Clock,
        glyphSize: 17,
        color: $r('app.color.text_secondary')
      })
      Column({ space: 4 }) {
        Text(entry.title.length > 0 ? entry.title : displayHost(entry.url))
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(displayHost(entry.url))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      Text(this.timeLabel(entry.visitedAt))
        .fontSize(11.5)
        .fontColor($r('app.color.text_secondary'))
        .fontFeature('"tnum" 1')
      if (!this.favoritesOnly) {
        Row() {
          AppIcon({ name: IconName.Trash, glyphSize: 15, color: $r('app.color.text_secondary') })
        }
        .id(`history-delete-${entry.id}`)
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .borderRadius(8)
        .hoverEffect(HoverEffect.Auto)
        .accessibilityText($r('app.string.history_delete'))
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          this.deleteEntry(entry);
        })
      }
    }
    .width('100%')
    .height(64)
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
    .onClick(() => this.onSelect(entry.url))
    .gesture(
      GestureGroup(GestureMode.Exclusive,
        LongPressGesture({ repeat: false, duration: 500 })
          .onAction(() => {
            if (this.favoritesOnly) {
              const saved: SavedItem | undefined = this.savedItemFor(entry);
              if (saved !== undefined) {
                this.onEditItem(saved);
              }
            }
          }),
        PanGesture({ direction: PanDirection.Horizontal, distance: HISTORY_SWIPE_DISTANCE })
          .onActionEnd((event: GestureEvent) => {
            if (event.offsetX <= -HISTORY_SWIPE_DISTANCE) {
              this.deleteEntry(entry);
            }
          })
      )
    )
  }

  private deleteEntry(entry: HistoryEntry): void {
    const targetId: string = resolveHistoryEntryDeleteTarget(entry, this.favoritesOnly, this.savedItems);
    this.onDelete(targetId);
    this.displayedEntries = this.displayedEntries.filter(
      (item: HistoryEntry): boolean => item.id !== entry.id
    );
    if (this.query.trim().length > 0) {
      this.searchResults = this.searchResults.filter((item: HistoryEntry): boolean => item.id !== entry.id);
    }
  }

  private restoreScrollOffset(): void {
    if (this.hasRestoredOffset || this.scrollOffset <= 0) {
      return;
    }
    this.hasRestoredOffset = true;
    this.scroller.scrollTo({ xOffset: 0, yOffset: this.scrollOffset, animation: false });
  }

  private savedItemFor(entry: HistoryEntry): SavedItem | undefined {
    return this.savedItems.find((item: SavedItem) => item.url === entry.url);
  }

  private groups(): HistoryGroup[] {
    const sorted: HistoryEntry[] = this.visibleEntries().slice(0).sort(
      (left: HistoryEntry, right: HistoryEntry): number => right.visitedAt - left.visitedAt
    );
    const today: string = dayKey(new Date());
    const yesterday: string = dayKey(new Date(Date.now() - 24 * 60 * 60 * 1000));
    const grouped: HistoryGroup[] = [];
    for (const entry of sorted) {
      const key: string = dayKey(new Date(entry.visitedAt));
      const title: Resource = key === today
        ? $r('app.string.history_today')
        : key === yesterday ? $r('app.string.history_yesterday') : $r('app.string.history_earlier');
      const existing: HistoryGroup | undefined = grouped.find((item: HistoryGroup) => item.key === key);
      if (existing === undefined) {
        grouped.push({ key: key, title: title, entries: [entry] });
      } else {
        existing.entries.push(entry);
      }
    }
    return grouped;
  }

  private groupRenderKey(group: HistoryGroup): string {
    let key: string = group.key;
    for (const entry of group.entries) {
      key += `:${entry.id}:${entry.title}:${entry.url}`;
    }
    return key;
  }

  private visibleEntries(): HistoryEntry[] {
    const query: string = this.query.trim().toLowerCase();
    if (query.length === 0) {
      return this.favoritesOnly ? this.favoriteEntries() : this.displayedEntries;
    }
    return this.searchResults;
  }

  private computeSearchResults(rawQuery: string): HistoryEntry[] {
    const query: string = rawQuery.trim().toLowerCase();
    if (query.length === 0) {
      return [];
    }

    const merged: HistoryEntry[] = [];
    for (const item of this.savedItems) {
      merged.push({
        id: `saved-search-${item.id}`,
        title: item.title,
        url: item.url,
        visitedAt: item.updatedAt,
        visitCount: 0
      });
    }
    if (!this.favoritesOnly) {
      for (const item of this.entries) {
        if (!merged.some((candidate: HistoryEntry): boolean => candidate.url === item.url)) {
          merged.push(item);
        }
      }
    }

    return merged
      .filter((item: HistoryEntry): boolean =>
        item.title.toLowerCase().includes(query) || item.url.toLowerCase().includes(query))
      .sort((left: HistoryEntry, right: HistoryEntry): number => {
        const scoreDifference: number = this.matchScore(right, query) - this.matchScore(left, query);
        return scoreDifference !== 0 ? scoreDifference : right.visitedAt - left.visitedAt;
      });
  }

  private favoriteEntries(): HistoryEntry[] {
    return this.savedItems.map((item: SavedItem): HistoryEntry => {
      return {
        id: `favorite-${item.id}`,
        title: item.title,
        url: item.url,
        visitedAt: item.updatedAt,
        visitCount: 0
      };
    });
  }

  private matchScore(entry: HistoryEntry, query: string): number {
    const title: string = entry.title.toLowerCase();
    const url: string = entry.url.toLowerCase();
    let score: number = 0;
    if (title === query || url === query) {
      score += 1000;
    }
    if (title.startsWith(query)) {
      score += 400;
    }
    if (url.startsWith(query)) {
      score += 300;
    }
    if (title.includes(query)) {
      score += 200;
    }
    if (url.includes(query)) {
      score += 100;
    }
    return score;
  }

  private timeLabel(timestamp: number): string {
    const date: Date = new Date(timestamp);
    const hour: string = `${date.getHours()}`.padStart(2, '0');
    const minute: string = `${date.getMinutes()}`.padStart(2, '0');
    return `${hour}:${minute}`;
  }
}
