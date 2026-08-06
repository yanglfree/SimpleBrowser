import { HistoryEntry, SavedItem } from '../models/BrowserModels';
import { dayKey } from '../utils/Formatting';
import { displayHost, rawHost } from '../utils/UrlUtils';
import { AppIcon, IconName } from './AppIcon';

const HISTORY_SWIPE_DISTANCE: number = 26;

interface HistoryGroup {
  key: string;
  title: Resource;
  entries: HistoryEntry[];
}

/** Full browsing history with calendar grouping and destructive swipe actions. */
@Component
export struct HistorySheet {
  @Prop entries: HistoryEntry[] = [];
  @Prop savedItems: SavedItem[] = [];
  @State private query: string = '';
  @State private searchResults: HistoryEntry[] = [];

  aboutToAppear(): void {
    this.searchResults = this.computeSearchResults('');
  }
  onDismiss: () => void = (): void => {};
  onSelect: (url: string) => void = (_url: string): void => {};
  onDelete: (id: string) => void = (_id: string): void => {};
  onDeleteSite: (host: string) => void = (_host: string): void => {};

  build() {
    Column() {
      Row({ space: 12 }) {
        AppIcon({ name: IconName.ArrowLeft, glyphSize: 21, color: $r('app.color.text_primary') })
          .onClick(() => this.onDismiss())
        Text($r('app.string.history_title'))
          .fontSize(24)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(`${this.entries.length}`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .fontFeature('"tnum" 1')
      }
      .width('100%')
        .padding({ top: 18, left: 24, right: 24, bottom: 12 })

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
        })

      if (this.visibleEntries().length === 0) {
        Column() {
          AppIcon({ name: IconName.Clock, glyphSize: 28, color: $r('app.color.text_secondary') })
          Text($r('app.string.history_empty'))
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            ForEach(this.groups(), (group: HistoryGroup) => {
              this.Group(group)
            }, (group: HistoryGroup) => group.key)
          }
          .width('100%')
          .padding({ left: 24, right: 24, bottom: 32 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
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
      AppIcon({ name: IconName.Clock, glyphSize: 17, color: $r('app.color.text_secondary') })
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
      AppIcon({ name: IconName.Close, glyphSize: 15, color: $r('app.color.text_secondary') })
        .onClick(() => this.onDeleteSite(rawHost(entry.url)))
    }
    .width('100%')
    .height(64)
    .border({ width: { bottom: 1 }, color: $r('app.color.border') })
    .onClick(() => this.onSelect(entry.url))
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal, distance: HISTORY_SWIPE_DISTANCE })
        .onActionEnd((event: GestureEvent) => {
          if (event.offsetX <= -HISTORY_SWIPE_DISTANCE) {
            this.onDelete(entry.id);
          }
        })
    )
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

  private visibleEntries(): HistoryEntry[] {
    const query: string = this.query.trim().toLowerCase();
    if (query.length === 0) {
      return this.entries;
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
    for (const item of this.entries) {
      if (!merged.some((candidate: HistoryEntry): boolean => candidate.url === item.url)) {
        merged.push(item);
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
