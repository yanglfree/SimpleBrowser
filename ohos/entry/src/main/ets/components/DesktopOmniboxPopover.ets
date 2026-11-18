import { Suggestion, SuggestionKind } from '../models/BrowserModels';
import { AppIcon, IconName } from './AppIcon';

export function moveOmniboxHighlight(currentIndex: number, count: number, delta: number): number {
  if (count <= 0) {
    return -1;
  }
  const total: number = count + 1;
  const currentOffset: number = currentIndex < 0 ? 0 : Math.min(currentIndex + 1, count);
  const nextOffset: number = ((currentOffset + delta) % total + total) % total;
  return nextOffset === 0 ? -1 : nextOffset - 1;
}

function suggestionIcon(kind: SuggestionKind): IconName {
  if (kind === SuggestionKind.History) {
    return IconName.Clock;
  }
  if (kind === SuggestionKind.Bookmark) {
    return IconName.Bookmark;
  }
  return IconName.Search;
}

@Component
export struct DesktopOmniboxPopover {
  @Prop suggestions: Suggestion[] = [];
  @Prop highlightedIndex: number = -1;
  onPick: (url: string) => void = (_url: string): void => {};
  onFill: (url: string) => void = (_url: string): void => {};
  onDismiss: () => void = (): void => {};

  build() {
    Column() {
      if (this.suggestions.length > 0) {
        Scroll() {
          Column({ space: 2 }) {
            ForEach(this.suggestions, (item: Suggestion, index: number) => {
              this.SuggestionRow(item, index)
            }, (item: Suggestion): string => item.id)
          }
          .width('100%')
          .padding(6)
        }
        .width('100%')
        .constraintSize({ maxHeight: 340 })
        .scrollBar(BarState.Auto)
      }
    }
    .id('desktop-omnibox-popover')
    .width(560)
    .constraintSize({ maxWidth: '92%' })
    .borderRadius(14)
    .backgroundColor($r('app.color.surface_panel'))
    .border({ width: 1, color: $r('app.color.border') })
    .shadow({ radius: 18, color: $r('app.color.shadow_soft'), offsetY: 6 })
    .clip(true)
  }

  @Builder
  private SuggestionRow(item: Suggestion, index: number) {
    Row({ space: 12 }) {
      AppIcon({
        name: suggestionIcon(item.kind),
        glyphSize: 16,
        color: index === this.highlightedIndex ? $r('app.color.accent') : $r('app.color.text_secondary')
      })
      Text() {
        Span(item.title)
        if (item.subtitle.length > 0) {
          Span(`  ${item.subtitle}`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .fontSize(14)
      .fontColor($r('app.color.text_primary'))
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .layoutWeight(1)

      Column() {
        AppIcon({ name: IconName.ArrowUpLeft, glyphSize: 15, color: $r('app.color.text_secondary') })
      }
      .id(`desktop-omnibox-fill-${index}`)
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .borderRadius(8)
      .hoverEffect(HoverEffect.Auto)
      .accessibilityText(item.url)
      .onClick(() => this.onFill(item.url))
    }
    .id(`desktop-omnibox-row-${index}`)
    .width('100%')
    .height(42)
    .padding({ left: 12, right: 6 })
    .borderRadius(10)
    .backgroundColor(index === this.highlightedIndex ? $r('app.color.surface_subtle') : Color.Transparent)
    .hoverEffect(HoverEffect.Auto)
    .onClick(() => this.onPick(item.url))
  }
}
